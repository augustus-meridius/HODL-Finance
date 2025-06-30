# HODL Finance 🚀

A decentralized lending protocol on the Stacks blockchain that enables users to borrow STX tokens using Bitcoin as collateral, leveraging Stacks' unique Bitcoin connection.

## Overview

HODL Finance allows Bitcoin holders to unlock liquidity from their Bitcoin holdings without selling them. By depositing Bitcoin as collateral, users can borrow STX tokens while maintaining exposure to Bitcoin's price appreciation.

## Key Features

- **Bitcoin-Backed Lending**: Use your Bitcoin as collateral to borrow STX tokens
- **Over-Collateralized Loans**: 150% collateralization ratio ensures protocol security
- **Competitive Interest Rates**: 5% annual interest rate on borrowed STX
- **Automated Liquidation**: Protect the protocol with automated liquidation at 125% ratio
- **Multiple Loans**: Support for up to 50 active loans per user
- **Transparent Fees**: Clear protocol fee structure (1% of interest)

## Protocol Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| Collateral Ratio | 150% | Required collateralization for new loans |
| Liquidation Threshold | 125% | Loans become liquidatable below this ratio |
| Interest Rate | 5% | Annual interest rate on borrowed STX |
| Liquidation Penalty | 10% | Penalty fee for liquidated loans |
| Max Loan Duration | ~1 year | Maximum loan duration in blocks |
| Protocol Fee | 1% | Fee on interest payments |

## How It Works

### 1. Register Bitcoin Collateral
```clarity
(register-btc-collateral tx-hash amount proof)
```
Users register their Bitcoin transaction as collateral by providing:
- Bitcoin transaction hash
- Amount of Bitcoin (in satoshis)
- Transaction proof (for verification)

### 2. Create a Loan
```clarity
(create-loan btc-tx-hash stx-amount duration-blocks)
```
After registering collateral, users can create a loan by specifying:
- The Bitcoin transaction hash used as collateral
- Amount of STX to borrow
- Loan duration in blocks

### 3. Repay Loan
```clarity
(repay-loan loan-id)
```
Borrowers can repay their loans at any time, including:
- Principal amount
- Accrued interest
- Protocol fees

### 4. Liquidation
```clarity
(liquidate-loan loan-id)
```
Anyone can liquidate unhealthy loans (below 125% collateral ratio) and receive a 10% bonus.

## Contract Functions

### Read-Only Functions

- `get-loan(loan-id)` - Get loan details
- `get-user-loans(user)` - Get all loans for a user
- `get-loan-health(loan-id)` - Check loan health status
- `get-protocol-stats()` - Get protocol statistics
- `calculate-interest(principal, rate, blocks)` - Calculate interest amount

### Public Functions

#### Core Functions
- `register-btc-collateral(tx-hash, amount, proof)` - Register Bitcoin as collateral
- `create-loan(btc-tx-hash, stx-amount, duration)` - Create a new loan
- `repay-loan(loan-id)` - Repay an existing loan
- `liquidate-loan(loan-id)` - Liquidate an unhealthy loan

#### Administrative Functions
- `set-btc-price(new-price)` - Update BTC/STX price oracle
- `update-protocol-fee(new-rate)` - Update protocol fee rate
- `emergency-pause()` - Emergency protocol pause
- `withdraw-protocol-fees(amount)` - Withdraw accumulated fees

## Error Codes

| Code | Error | Description |
|------|-------|-------------|
| 100 | ERR_UNAUTHORIZED | Caller not authorized |
| 101 | ERR_INSUFFICIENT_COLLATERAL | Not enough collateral |
| 102 | ERR_LOAN_NOT_FOUND | Loan doesn't exist |
| 103 | ERR_LOAN_EXPIRED | Loan has expired |
| 104 | ERR_ALREADY_LIQUIDATED | Loan already liquidated |
| 105 | ERR_INSUFFICIENT_FUNDS | Not enough funds |
| 106 | ERR_INVALID_AMOUNT | Invalid amount specified |
| 107 | ERR_COLLATERAL_LOCKED | Collateral already in use |
| 108 | ERR_REPAYMENT_FAILED | Repayment transaction failed |

## Usage Examples

### Creating a Loan

```clarity
;; 1. First, register your Bitcoin collateral
(contract-call? .hodl-finance register-btc-collateral 
  0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
  u100000000  ;; 1 BTC in satoshis
  0x...)      ;; Transaction proof

;; 2. Create a loan against the collateral
(contract-call? .hodl-finance create-loan
  0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef
  u1000000000  ;; 1000 STX
  u26280000)   ;; ~6 months in blocks
```

### Checking Loan Health

```clarity
;; Check if your loan is healthy
(contract-call? .hodl-finance get-loan-health u1)
;; Returns: { collateral-ratio: u160, is-healthy: true, stx-debt: u1000000000, btc-collateral-value: u1600000000 }
```

### Repaying a Loan

```clarity
;; Repay loan with interest
(contract-call? .hodl-finance repay-loan u1)
;; Returns: { repaid: u1025000000, interest: u25000000, fee: u250000 }
```

## Security Considerations

- **Oracle Risk**: The contract relies on price oracles for BTC/STX exchange rates
- **Liquidation Risk**: Loans can be liquidated if collateral value drops
- **Smart Contract Risk**: Standard smart contract risks apply
- **Bitcoin Integration**: Depends on Stacks' Bitcoin integration security

## Deployment

1. Deploy the contract to Stacks blockchain
2. Set initial BTC/STX price using `set-btc-price`
3. Fund the contract with STX tokens for lending
4. Configure any additional parameters as needed

## Testing

The contract includes comprehensive error handling and parameter validation. Test scenarios should include:

- Normal loan lifecycle (create, repay)
- Liquidation scenarios
- Edge cases (insufficient collateral, expired loans)
- Administrative functions
- Error conditions

## Integration

### Frontend Integration

```javascript
// Example using @stacks/transactions
import { contractCall } from '@stacks/transactions';

const createLoan = async (btcTxHash, stxAmount, duration) => {
  const txOptions = {
    contractAddress: 'CONTRACT_ADDRESS',
    contractName: 'hodl-finance',
    functionName: 'create-loan',
    functionArgs: [
      bufferCV(btcTxHash),
      uintCV(stxAmount),
      uintCV(duration)
    ],
    senderKey: 'SENDER_PRIVATE_KEY',
    network: 'mainnet' // or 'testnet'
  };
  
  return await contractCall(txOptions);
};
```

### Price Oracle Integration

The contract requires regular price updates for accurate collateral valuation:

```clarity
;; Update BTC/STX price (admin only)
(contract-call? .hodl-finance set-btc-price u95000) ;; Price in micro-STX per satoshi
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Submit a pull request

**Built on Stacks • Secured by Bitcoin**