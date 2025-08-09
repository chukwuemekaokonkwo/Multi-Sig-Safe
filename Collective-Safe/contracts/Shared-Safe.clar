;; Multi-Signature Treasury Governance Contract
;; 
;; A decentralized treasury management system enabling secure collaborative control
;; of digital assets through consensus-driven governance with essential on-chain features.

;; ERROR CODE DEFINITIONS

(define-constant ERR-ACCESS-DENIED (err u100))
(define-constant ERR-INVALID-INPUT-PARAMETER (err u101))
(define-constant ERR-PROPOSAL-NOT-FOUND (err u102))
(define-constant ERR-PROPOSAL-ALREADY-EXECUTED (err u103))
(define-constant ERR-PROPOSAL-ALREADY-REJECTED (err u104))
(define-constant ERR-PROPOSAL-DEADLINE-EXPIRED (err u105))
(define-constant ERR-TREASURY-INSUFFICIENT-FUNDS (err u106))
(define-constant ERR-APPROVAL-REQUIREMENT-TOO-HIGH (err u107))
(define-constant ERR-GUARDIAN-ALREADY-REGISTERED (err u108))
(define-constant ERR-GUARDIAN-NOT-REGISTERED (err u109))
(define-constant ERR-GUARDIAN-ALREADY-APPROVED-PROPOSAL (err u110))
(define-constant ERR-GUARDIAN-HAS-NOT-APPROVED-PROPOSAL (err u111))
(define-constant ERR-MEMO-DATA-INVALID (err u112))
(define-constant ERR-TIMELOCK-NOT-EXPIRED (err u113))
(define-constant ERR-EMERGENCY-MODE-ACTIVE (err u114))
(define-constant ERR-SPENDING-LIMIT-EXCEEDED (err u115))

;; SYSTEM STATE VARIABLES

(define-data-var next-proposal-identifier uint u0)
(define-data-var active-guardian-count uint u0)
(define-data-var required-approval-threshold uint u0)
(define-data-var is-emergency-mode-active bool false)
(define-data-var emergency-guardian principal 'SP000000000000000000002Q6VF78)
(define-data-var proposal-timelock-duration uint u144)
(define-data-var daily-spending-limit uint u1000000000)
(define-data-var daily-spent-amount uint u0)
(define-data-var last-spending-reset-day uint u0)

;; DATA STORAGE STRUCTURES

(define-map governance-proposals
  { proposal-id: uint }
  {
    initiating-guardian: principal,
    target-recipient: principal,
    transfer-amount-micro-stx: uint,
    proposal-description: (optional (buff 256)),
    proposal-type: (string-ascii 20),
    is-executed: bool,
    is-cancelled: bool,
    current-approval-count: uint,
    deadline-block-height: uint,
    timelock-expiry-block: uint,
    creation-block-height: uint
  }
)

(define-map treasury-guardians
  { guardian-principal: principal }
  { 
    is-active-guardian: bool,
    guardian-role: (string-ascii 15),
    spending-limit: uint,
    joining-block-height: uint
  }
)

(define-map guardian-proposal-votes
  { proposal-id: uint, guardian-principal: principal }
  { 
    has-approved: bool,
    vote-block-height: uint
  }
)

(define-map guardian-delegations
  { delegating-guardian: principal }
  {
    delegated-to: principal,
    delegation-end-block: uint
  }
)

;; INPUT VALIDATION HELPERS

(define-private (is-valid-principal (address principal))
  (not (is-eq address 'SP000000000000000000002Q6VF78)))

(define-private (is-valid-description (desc (optional (buff 256))))
  (match desc
    some-desc (and (>= (len some-desc) u1) (<= (len some-desc) u256))
    true))

(define-private (is-valid-proposal-id (proposal-id uint))
  (< proposal-id (var-get next-proposal-identifier)))

(define-private (is-valid-duration-blocks (duration uint))
  (and (> duration u0) (<= duration u52560))) ;; Max ~1 year in blocks

;; ON-CHAIN FUNCTIONALITIES

;; TREASURY INITIALIZATION
(define-public (initialize-treasury-governance (founding-guardians (list 20 principal)) 
                                               (minimum-approvals-required uint)
                                               (emergency-guardian-address principal))
  (begin
    (asserts! (is-eq (var-get active-guardian-count) u0) ERR-ACCESS-DENIED)
    (asserts! (<= minimum-approvals-required (len founding-guardians)) ERR-APPROVAL-REQUIREMENT-TOO-HIGH)
    (asserts! (> minimum-approvals-required u0) ERR-INVALID-INPUT-PARAMETER)
    ;; Validate emergency guardian address
    (asserts! (is-valid-principal emergency-guardian-address) ERR-INVALID-INPUT-PARAMETER)
    ;; Validate all founding guardian addresses
    (asserts! (is-eq (len (filter is-valid-principal founding-guardians)) (len founding-guardians)) ERR-INVALID-INPUT-PARAMETER)
    
    (var-set required-approval-threshold minimum-approvals-required)
    (var-set emergency-guardian emergency-guardian-address)
    (map register-founding-guardian founding-guardians)
    (ok true)))

(define-private (register-founding-guardian (guardian-address principal))
  (begin
    (map-set treasury-guardians 
      { guardian-principal: guardian-address } 
      { is-active-guardian: true, guardian-role: "standard", 
        spending-limit: u1000000000, joining-block-height: block-height })
    (var-set active-guardian-count (+ (var-get active-guardian-count) u1))
    true))

;; PROPOSAL CREATION
(define-public (create-transfer-proposal (recipient-address principal) 
                                        (amount-micro-stx uint) 
                                        (description (optional (buff 256))) 
                                        (expiration-blocks uint))
  (let ((current-proposal-id (var-get next-proposal-identifier))
        (guardian-info (unwrap! (map-get? treasury-guardians { guardian-principal: tx-sender }) ERR-ACCESS-DENIED)))
    
    ;; Input validation
    (asserts! (is-valid-principal recipient-address) ERR-INVALID-INPUT-PARAMETER)
    (asserts! (is-valid-description description) ERR-INVALID-INPUT-PARAMETER)
    (asserts! (is-valid-duration-blocks expiration-blocks) ERR-INVALID-INPUT-PARAMETER)
    
    (asserts! (get is-active-guardian guardian-info) ERR-ACCESS-DENIED)
    (asserts! (not (var-get is-emergency-mode-active)) ERR-EMERGENCY-MODE-ACTIVE)
    (asserts! (> amount-micro-stx u0) ERR-INVALID-INPUT-PARAMETER)
    (asserts! (<= amount-micro-stx (stx-get-balance (as-contract tx-sender))) ERR-TREASURY-INSUFFICIENT-FUNDS)
    (asserts! (<= amount-micro-stx (get spending-limit guardian-info)) ERR-SPENDING-LIMIT-EXCEEDED)
    
    (update-daily-spending amount-micro-stx)
    (asserts! (<= (var-get daily-spent-amount) (var-get daily-spending-limit)) ERR-SPENDING-LIMIT-EXCEEDED)
    
    (map-set governance-proposals
      { proposal-id: current-proposal-id }
      {
        initiating-guardian: tx-sender,
        target-recipient: recipient-address,
        transfer-amount-micro-stx: amount-micro-stx,
        proposal-description: description,
        proposal-type: "transfer",
        is-executed: false,
        is-cancelled: false,
        current-approval-count: u1,
        deadline-block-height: (+ block-height expiration-blocks),
        timelock-expiry-block: (+ block-height (var-get proposal-timelock-duration)),
        creation-block-height: block-height
      })
    
    (map-set guardian-proposal-votes
      { proposal-id: current-proposal-id, guardian-principal: tx-sender }
      { has-approved: true, vote-block-height: block-height })
    
    (var-set next-proposal-identifier (+ current-proposal-id u1))
    (ok current-proposal-id)))

;; PROPOSAL VOTING
(define-public (approve-proposal (proposal-id uint))
  (begin
    ;; Validate proposal ID
    (asserts! (is-valid-proposal-id proposal-id) ERR-PROPOSAL-NOT-FOUND)
    
    (asserts! (is-authorized-guardian tx-sender) ERR-ACCESS-DENIED)
    (asserts! (is-some (map-get? governance-proposals { proposal-id: proposal-id })) ERR-PROPOSAL-NOT-FOUND)
    
    (match (map-get? governance-proposals { proposal-id: proposal-id })
      proposal-details
        (begin
          (asserts! (not (get is-executed proposal-details)) ERR-PROPOSAL-ALREADY-EXECUTED)
          (asserts! (not (get is-cancelled proposal-details)) ERR-PROPOSAL-ALREADY-REJECTED)
          (asserts! (<= block-height (get deadline-block-height proposal-details)) ERR-PROPOSAL-DEADLINE-EXPIRED)
          (asserts! (not (has-guardian-approved-proposal proposal-id tx-sender)) ERR-GUARDIAN-ALREADY-APPROVED-PROPOSAL)
          
          (map-set guardian-proposal-votes
            { proposal-id: proposal-id, guardian-principal: tx-sender }
            { has-approved: true, vote-block-height: block-height })
          
          (map-set governance-proposals
            { proposal-id: proposal-id }
            (merge proposal-details 
              { current-approval-count: (+ (get current-approval-count proposal-details) u1) }))
          
          (if (>= (+ (get current-approval-count proposal-details) u1) (var-get required-approval-threshold))
            (begin
              (try! (execute-approved-proposal proposal-id))
              (ok proposal-id))
            (ok proposal-id)))
      ERR-PROPOSAL-NOT-FOUND)))

;; PROPOSAL EXECUTION
(define-public (execute-approved-proposal (proposal-id uint))
  (begin
    ;; Validate proposal ID
    (asserts! (is-valid-proposal-id proposal-id) ERR-PROPOSAL-NOT-FOUND)
    
    (asserts! (is-some (map-get? governance-proposals { proposal-id: proposal-id })) ERR-PROPOSAL-NOT-FOUND)
    
    (match (map-get? governance-proposals { proposal-id: proposal-id })
      proposal-details
        (begin
          (asserts! (not (get is-executed proposal-details)) ERR-PROPOSAL-ALREADY-EXECUTED)
          (asserts! (not (get is-cancelled proposal-details)) ERR-PROPOSAL-ALREADY-REJECTED)
          (asserts! (<= block-height (get deadline-block-height proposal-details)) ERR-PROPOSAL-DEADLINE-EXPIRED)
          (asserts! (>= block-height (get timelock-expiry-block proposal-details)) ERR-TIMELOCK-NOT-EXPIRED)
          (asserts! (>= (get current-approval-count proposal-details) (var-get required-approval-threshold)) ERR-ACCESS-DENIED)
          
          (map-set governance-proposals
            { proposal-id: proposal-id }
            (merge proposal-details { is-executed: true }))
          
          (if (is-eq (get proposal-type proposal-details) "transfer")
            (as-contract 
              (stx-transfer? (get transfer-amount-micro-stx proposal-details) 
                            tx-sender 
                            (get target-recipient proposal-details)))
            (ok true)))
      ERR-PROPOSAL-NOT-FOUND)))

;; GUARDIAN MANAGEMENT
(define-public (propose-add-guardian (new-guardian-address principal))
  (let ((current-proposal-id (var-get next-proposal-identifier)))
    ;; Validate guardian address
    (asserts! (is-valid-principal new-guardian-address) ERR-INVALID-INPUT-PARAMETER)
    
    (asserts! (is-authorized-guardian tx-sender) ERR-ACCESS-DENIED)
    (asserts! (not (is-authorized-guardian new-guardian-address)) ERR-GUARDIAN-ALREADY-REGISTERED)
    
    (map-set governance-proposals
      { proposal-id: current-proposal-id }
      {
        initiating-guardian: tx-sender,
        target-recipient: new-guardian-address,
        transfer-amount-micro-stx: u0,
        proposal-description: none,
        proposal-type: "add-guardian",
        is-executed: false,
        is-cancelled: false,
        current-approval-count: u1,
        deadline-block-height: (+ block-height u1008),
        timelock-expiry-block: (+ block-height (var-get proposal-timelock-duration)),
        creation-block-height: block-height
      })
    
    (var-set next-proposal-identifier (+ current-proposal-id u1))
    (ok current-proposal-id)))

(define-public (execute-add-guardian (proposal-id uint))
  (begin
    ;; Validate proposal ID
    (asserts! (is-valid-proposal-id proposal-id) ERR-PROPOSAL-NOT-FOUND)
    
    (asserts! (is-some (map-get? governance-proposals { proposal-id: proposal-id })) ERR-PROPOSAL-NOT-FOUND)
    
    (match (map-get? governance-proposals { proposal-id: proposal-id })
      proposal-details
        (begin
          (asserts! (is-eq (get proposal-type proposal-details) "add-guardian") ERR-INVALID-INPUT-PARAMETER)
          (asserts! (>= (get current-approval-count proposal-details) (var-get required-approval-threshold)) ERR-ACCESS-DENIED)
          (asserts! (>= block-height (get timelock-expiry-block proposal-details)) ERR-TIMELOCK-NOT-EXPIRED)
          
          (map-set governance-proposals
            { proposal-id: proposal-id }
            (merge proposal-details { is-executed: true }))
          
          (map-set treasury-guardians 
            { guardian-principal: (get target-recipient proposal-details) } 
            { is-active-guardian: true, guardian-role: "standard", 
              spending-limit: u1000000000, joining-block-height: block-height })
          
          (var-set active-guardian-count (+ (var-get active-guardian-count) u1))
          (ok proposal-id))
      ERR-PROPOSAL-NOT-FOUND)))

;; DELEGATION SYSTEM
(define-public (delegate-voting-power (delegate-to principal) (delegation-duration-blocks uint))
  (let ((delegator-info (unwrap! (map-get? treasury-guardians { guardian-principal: tx-sender }) ERR-ACCESS-DENIED))
        (delegate-info (unwrap! (map-get? treasury-guardians { guardian-principal: delegate-to }) ERR-GUARDIAN-NOT-REGISTERED)))
    
    ;; Input validation
    (asserts! (is-valid-principal delegate-to) ERR-INVALID-INPUT-PARAMETER)
    (asserts! (is-valid-duration-blocks delegation-duration-blocks) ERR-INVALID-INPUT-PARAMETER)
    
    (asserts! (get is-active-guardian delegator-info) ERR-ACCESS-DENIED)
    (asserts! (get is-active-guardian delegate-info) ERR-ACCESS-DENIED)
    (asserts! (not (is-eq tx-sender delegate-to)) ERR-INVALID-INPUT-PARAMETER)
    
    (map-set guardian-delegations
      { delegating-guardian: tx-sender }
      {
        delegated-to: delegate-to,
        delegation-end-block: (+ block-height delegation-duration-blocks)
      })
    
    (ok true)))

(define-public (revoke-delegation)
  (begin
    (asserts! (is-some (map-get? guardian-delegations { delegating-guardian: tx-sender })) ERR-INVALID-INPUT-PARAMETER)
    (map-delete guardian-delegations { delegating-guardian: tx-sender })
    (ok true)))

;; EMERGENCY CONTROLS
(define-public (activate-emergency-mode)
  (begin
    (asserts! (is-eq tx-sender (var-get emergency-guardian)) ERR-ACCESS-DENIED)
    (asserts! (not (var-get is-emergency-mode-active)) ERR-EMERGENCY-MODE-ACTIVE)
    (var-set is-emergency-mode-active true)
    (ok true)))

(define-public (deactivate-emergency-mode)
  (begin
    (asserts! (is-authorized-guardian tx-sender) ERR-ACCESS-DENIED)
    (asserts! (var-get is-emergency-mode-active) ERR-INVALID-INPUT-PARAMETER)
    (var-set is-emergency-mode-active false)
    (ok true)))

;; TREASURY DEPOSIT
(define-public (deposit-funds (amount uint))
  (stx-transfer? amount tx-sender (as-contract tx-sender)))

;; GOVERNANCE PARAMETER UPDATES
(define-public (propose-threshold-change (new-threshold uint))
  (let ((current-proposal-id (var-get next-proposal-identifier)))
    (asserts! (is-authorized-guardian tx-sender) ERR-ACCESS-DENIED)
    (asserts! (> new-threshold u0) ERR-INVALID-INPUT-PARAMETER)
    (asserts! (<= new-threshold (var-get active-guardian-count)) ERR-APPROVAL-REQUIREMENT-TOO-HIGH)
    
    (map-set governance-proposals
      { proposal-id: current-proposal-id }
      {
        initiating-guardian: tx-sender,
        target-recipient: tx-sender,
        transfer-amount-micro-stx: new-threshold,
        proposal-description: none,
        proposal-type: "threshold-change",
        is-executed: false,
        is-cancelled: false,
        current-approval-count: u1,
        deadline-block-height: (+ block-height u1008),
        timelock-expiry-block: (+ block-height (var-get proposal-timelock-duration)),
        creation-block-height: block-height
      })
    
    (var-set next-proposal-identifier (+ current-proposal-id u1))
    (ok current-proposal-id)))

(define-public (execute-threshold-change (proposal-id uint))
  (begin
    ;; Validate proposal ID
    (asserts! (is-valid-proposal-id proposal-id) ERR-PROPOSAL-NOT-FOUND)
    
    (match (map-get? governance-proposals { proposal-id: proposal-id })
      proposal-details
        (begin
          (asserts! (is-eq (get proposal-type proposal-details) "threshold-change") ERR-INVALID-INPUT-PARAMETER)
          (asserts! (>= (get current-approval-count proposal-details) (var-get required-approval-threshold)) ERR-ACCESS-DENIED)
          (asserts! (>= block-height (get timelock-expiry-block proposal-details)) ERR-TIMELOCK-NOT-EXPIRED)
          
          (var-set required-approval-threshold (get transfer-amount-micro-stx proposal-details))
          (map-set governance-proposals
            { proposal-id: proposal-id }
            (merge proposal-details { is-executed: true }))
          (ok proposal-id))
      ERR-PROPOSAL-NOT-FOUND)))

;; PROPOSAL CANCELLATION
(define-public (cancel-proposal (proposal-id uint))
  (begin
    ;; Validate proposal ID
    (asserts! (is-valid-proposal-id proposal-id) ERR-PROPOSAL-NOT-FOUND)
    
    (match (map-get? governance-proposals { proposal-id: proposal-id })
      proposal-details
        (begin
          (asserts! (not (get is-executed proposal-details)) ERR-PROPOSAL-ALREADY-EXECUTED)
          (asserts! (not (get is-cancelled proposal-details)) ERR-PROPOSAL-ALREADY-REJECTED)
          (asserts! (or (is-eq (get initiating-guardian proposal-details) tx-sender)
                       (>= (get current-approval-count proposal-details) (var-get required-approval-threshold))) ERR-ACCESS-DENIED)
          
          (map-set governance-proposals
            { proposal-id: proposal-id }
            (merge proposal-details { is-cancelled: true }))
          (ok proposal-id))
      ERR-PROPOSAL-NOT-FOUND)))

;; HELPER FUNCTIONS

(define-private (update-daily-spending (amount uint))
  (let ((current-day (/ block-height u144)))
    (if (> current-day (var-get last-spending-reset-day))
      (begin
        (var-set daily-spent-amount amount)
        (var-set last-spending-reset-day current-day)
        true)
      (begin
        (var-set daily-spent-amount (+ (var-get daily-spent-amount) amount))
        true))))

;; READ-ONLY QUERY FUNCTIONS

(define-read-only (get-approval-threshold) (var-get required-approval-threshold))
(define-read-only (get-guardian-count) (var-get active-guardian-count))
(define-read-only (get-treasury-balance) (stx-get-balance (as-contract tx-sender)))
(define-read-only (get-emergency-status) (var-get is-emergency-mode-active))
(define-read-only (get-daily-spending-status) 
  { spent: (var-get daily-spent-amount), limit: (var-get daily-spending-limit) })

(define-read-only (is-authorized-guardian (address principal))
  (default-to false 
    (get is-active-guardian 
      (map-get? treasury-guardians { guardian-principal: address }))))

(define-read-only (get-proposal-details (proposal-id uint))
  (map-get? governance-proposals { proposal-id: proposal-id }))

(define-read-only (has-guardian-approved-proposal (proposal-id uint) (guardian-address principal))
  (default-to false 
    (get has-approved 
      (map-get? guardian-proposal-votes 
        { proposal-id: proposal-id, guardian-principal: guardian-address }))))

(define-read-only (get-guardian-details (address principal))
  (map-get? treasury-guardians { guardian-principal: address }))

(define-read-only (get-delegation-status (delegating-guardian principal))
  (map-get? guardian-delegations { delegating-guardian: delegating-guardian }))