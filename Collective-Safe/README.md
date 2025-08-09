# Multi-Signature Treasury Governance Contract

A decentralized treasury management system enabling secure collaborative control of digital assets through consensus-driven governance with essential on-chain features.

## Overview

This Clarity smart contract implements a multi-signature treasury system for the Stacks blockchain, allowing multiple guardians to collectively manage funds through a proposal-based governance system. The contract includes advanced features like delegation, emergency controls, spending limits, and timelock mechanisms for enhanced security.

## Key Features

### Multi-Signature Security
- Configurable approval thresholds
- Guardian-based voting system
- Timelock mechanisms for proposal execution

### Governance System
- Proposal creation and voting
- Support for different proposal types (transfers, guardian management, parameter changes)
- Guardian delegation system

### Emergency Controls
- Emergency mode activation/deactivation
- Emergency guardian with special privileges
- Spending limits and daily caps

### Treasury Management
- Secure fund deposits
- Controlled withdrawals through proposals
- Balance tracking and spending limits

## Contract Architecture

### Core Components

1. **Guardian System**: Manages authorized users who can create and vote on proposals
2. **Proposal System**: Handles creation, voting, and execution of governance proposals
3. **Treasury Management**: Controls fund deposits, withdrawals, and balance tracking
4. **Emergency Controls**: Provides safety mechanisms during critical situations

### Data Structures

- `governance-proposals`: Stores proposal information and voting status
- `treasury-guardians`: Tracks guardian details and permissions
- `guardian-proposal-votes`: Records individual guardian votes
- `guardian-delegations`: Manages voting power delegation

## Getting Started

### Prerequisites

- Stacks blockchain testnet/mainnet access
- Clarity CLI or compatible development environment
- STX tokens for transaction fees

### Deployment

1. Deploy the contract to the Stacks blockchain
2. Initialize the treasury with founding guardians
3. Set initial governance parameters

### Initialization

```clarity
;; Initialize the treasury with founding guardians and parameters
(contract-call? .treasury-contract initialize-treasury-governance
  (list principal1 principal2 principal3)  ;; founding guardians
  u2                                        ;; minimum approvals required
  emergency-guardian-principal)             ;; emergency guardian address
```

## Usage Guide

### For Guardians

#### Creating a Proposal

```clarity
;; Create a transfer proposal
(contract-call? .treasury-contract create-transfer-proposal
  recipient-address     ;; where to send funds
  u1000000             ;; amount in micro-STX
  (some "Payment for services")  ;; optional description
  u1008)               ;; expiration in blocks (7 days)
```

#### Voting on Proposals

```clarity
;; Approve a proposal
(contract-call? .treasury-contract approve-proposal proposal-id)
```

#### Executing Proposals

```clarity
;; Execute an approved proposal (after timelock expires)
(contract-call? .treasury-contract execute-approved-proposal proposal-id)
```

### Guardian Management

#### Adding New Guardians

```clarity
;; Propose adding a new guardian
(contract-call? .treasury-contract propose-add-guardian new-guardian-address)

;; Execute the guardian addition (after approval and timelock)
(contract-call? .treasury-contract execute-add-guardian proposal-id)
```

#### Delegation

```clarity
;; Delegate voting power to another guardian
(contract-call? .treasury-contract delegate-voting-power
  delegate-address
  u144)  ;; delegation duration in blocks

;; Revoke delegation
(contract-call? .treasury-contract revoke-delegation)
```

### Emergency Controls

```clarity
;; Activate emergency mode (emergency guardian only)
(contract-call? .treasury-contract activate-emergency-mode)

;; Deactivate emergency mode (any guardian)
(contract-call? .treasury-contract deactivate-emergency-mode)
```

### Treasury Operations

#### Depositing Funds

```clarity
;; Deposit STX into the treasury
(contract-call? .treasury-contract deposit-funds u1000000)
```

## Configuration Parameters

### Default Settings

- **Proposal Timelock**: 144 blocks (~24 hours)
- **Daily Spending Limit**: 1,000 STX
- **Guardian Spending Limit**: 1,000 STX
- **Proposal Expiration**: 1,008 blocks (~7 days)

### Updating Parameters

Governance parameters can be updated through proposals:

```clarity
;; Propose changing the approval threshold
(contract-call? .treasury-contract propose-threshold-change new-threshold)

;; Execute threshold change (after approval)
(contract-call? .treasury-contract execute-threshold-change proposal-id)
```

## Read-Only Functions

Query contract state without making transactions:

```clarity
;; Get current approval threshold
(contract-call? .treasury-contract get-approval-threshold)

;; Get treasury balance
(contract-call? .treasury-contract get-treasury-balance)

;; Check if address is a guardian
(contract-call? .treasury-contract is-authorized-guardian address)

;; Get proposal details
(contract-call? .treasury-contract get-proposal-details proposal-id)

;; Check guardian approval status
(contract-call? .treasury-contract has-guardian-approved-proposal proposal-id guardian-address)
```

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| 100 | ERR-ACCESS-DENIED | User lacks required permissions |
| 101 | ERR-INVALID-INPUT-PARAMETER | Invalid function parameter |
| 102 | ERR-PROPOSAL-NOT-FOUND | Proposal ID doesn't exist |
| 103 | ERR-PROPOSAL-ALREADY-EXECUTED | Proposal has already been executed |
| 104 | ERR-PROPOSAL-ALREADY-REJECTED | Proposal has been cancelled |
| 105 | ERR-PROPOSAL-DEADLINE-EXPIRED | Proposal voting period has ended |
| 106 | ERR-TREASURY-INSUFFICIENT-FUNDS | Not enough funds in treasury |
| 107 | ERR-APPROVAL-REQUIREMENT-TOO-HIGH | Threshold exceeds guardian count |
| 108 | ERR-GUARDIAN-ALREADY-REGISTERED | Guardian already exists |
| 109 | ERR-GUARDIAN-NOT-REGISTERED | Guardian not found |
| 110 | ERR-GUARDIAN-ALREADY-APPROVED-PROPOSAL | Guardian has already voted |
| 111 | ERR-GUARDIAN-HAS-NOT-APPROVED-PROPOSAL | Guardian hasn't approved proposal |
| 112 | ERR-MEMO-DATA-INVALID | Invalid memo data |
| 113 | ERR-TIMELOCK-NOT-EXPIRED | Timelock period hasn't passed |
| 114 | ERR-EMERGENCY-MODE-ACTIVE | Emergency mode is currently active |
| 115 | ERR-SPENDING-LIMIT-EXCEEDED | Transaction exceeds spending limits |

## Security Features

### Timelock Mechanism
All proposals have a mandatory timelock period before execution, providing time to review and potentially cancel malicious proposals.

### Spending Limits
- Individual guardian spending limits
- Daily treasury spending caps
- Automatic spending tracking and reset

### Emergency Controls
- Emergency guardian can halt all operations
- Any guardian can deactivate emergency mode
- Proposal cancellation by initiator or majority

### Access Control
- Guardian-only proposal creation and voting
- Role-based permissions
- Delegation with time limits

## Best Practices

1. **Regular Monitoring**: Monitor proposal activity and treasury balance
2. **Secure Key Management**: Use hardware wallets for guardian keys
3. **Emergency Preparedness**: Ensure emergency guardian key security
4. **Parameter Reviews**: Regularly review and update governance parameters
5. **Guardian Rotation**: Consider periodic guardian updates for security

## Development

### Testing

Test the contract thoroughly before mainnet deployment:

1. Deploy on testnet
2. Test all proposal types
3. Verify emergency controls
4. Test edge cases and error conditions

### Integration

The contract can be integrated with:
- Web interfaces for proposal management
- Notification systems for voting alerts
- Analytics dashboards for treasury tracking
- Multi-signature wallet interfaces