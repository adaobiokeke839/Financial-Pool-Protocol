# Financial Pool Protocol

A comprehensive DeFi exchange protocol built on Stacks blockchain with automated market maker (AMM) functionality, configurable bonding curves, time-locked staking, and multi-token liquidity pools.

## Overview

The Financial Pool Protocol is a decentralized exchange (DEX) smart contract that enables users to:
- Create and manage liquidity pools
- Swap tokens using automated market maker algorithms
- Provide liquidity and earn fees
- Stake tokens for rewards with time-locked periods
- Utilize different bonding curve mechanisms

## Features

### Core Functionality
- **Automated Market Maker (AMM)**: Constant product formula for token swaps
- **Multi-Asset Support**: Create pools with any token pair
- **Configurable Fee Structure**: Customizable trading fees per pool
- **Liquidity Mining**: Earn rewards by providing liquidity
- **Time-Locked Staking**: Stake tokens for additional rewards with lock periods
- **Bonding Curves**: Support for linear, exponential, and constant curve types
- **Slippage Protection**: Built-in slippage validation for trades
- **Protocol Governance**: Owner-controlled pause/unpause functionality

### Security Features
- Arithmetic overflow protection
- Input validation and sanitization
- Access control mechanisms
- Emergency pause functionality
- Maximum limits on amounts and pool counts

## Constants and Limits

- **Maximum Fee Rate**: 10,000 basis points (100%)
- **Minimum Liquidity**: 1,000 units
- **Maximum Pools**: 1,000 pools
- **Maximum Amount**: 1 billion STX (with 6 decimals)
- **Staking Lock Period**: 1 day to 1 year (in blocks)
- **Protocol Fee Rate**: 0.3% (configurable)

## Error Codes

| Code | Error | Description |
|------|-------|-------------|
| u1000 | ERR-UNAUTHORIZED-ACCESS | Caller lacks required permissions |
| u1001 | ERR-INSUFFICIENT-BALANCE | Insufficient token balance |
| u1002 | ERR-INVALID-AMOUNT | Invalid amount specified |
| u1003 | ERR-POOL-NOT-EXISTS | Pool does not exist |
| u1004 | ERR-POOL-ALREADY-EXISTS | Pool already exists for token pair |
| u1005 | ERR-SLIPPAGE-EXCEEDED | Slippage tolerance exceeded |
| u1006 | ERR-INSUFFICIENT-LIQUIDITY | Insufficient liquidity in pool |
| u1007 | ERR-INVALID-TOKEN-PAIR | Invalid token pair specified |
| u1008 | ERR-STAKING-PERIOD-NOT-ENDED | Staking period has not ended |
| u1009 | ERR-NO-STAKE-FOUND | No stake found for user |
| u1010 | ERR-INVALID-CURVE-PARAMETERS | Invalid bonding curve parameters |
| u1011 | ERR-ZERO-LIQUIDITY | Zero liquidity provided |
| u1012 | ERR-INVALID-FEE-RATE | Invalid fee rate specified |
| u1013 | ERR-PAUSED-PROTOCOL | Protocol is currently paused |
| u1014 | ERR-INVALID-POOL-ID | Invalid pool ID |
| u1015 | ERR-DEADLINE-EXCEEDED | Transaction deadline exceeded |
| u1016 | ERR-ARITHMETIC-OVERFLOW | Arithmetic operation overflow |
| u1017 | ERR-INVALID-CURVE-TYPE | Invalid bonding curve type |

## Public Functions

### Pool Management

#### `create-pool`
Creates a new liquidity pool with specified parameters.

**Parameters:**
- `token-a` (principal): First token in the pair
- `token-b` (principal): Second token in the pair
- `initial-a` (uint): Initial amount of token A
- `initial-b` (uint): Initial amount of token B
- `fee-rate` (uint): Trading fee rate in basis points
- `curve-type` (string-ascii 10): Bonding curve type ("linear", "exponential", "constant")
- `curve-param-a` (uint): First curve parameter
- `curve-param-b` (uint): Second curve parameter

**Returns:** Pool ID (uint)

#### `add-liquidity`
Adds liquidity to an existing pool.

**Parameters:**
- `pool-id` (uint): Target pool ID
- `amount-a` (uint): Amount of token A to add
- `amount-b` (uint): Amount of token B to add
- `min-lp-tokens` (uint): Minimum LP tokens to receive

**Returns:** LP tokens received (uint)

#### `remove-liquidity`
Removes liquidity from a pool.

**Parameters:**
- `pool-id` (uint): Target pool ID
- `lp-tokens` (uint): LP tokens to burn
- `min-amount-a` (uint): Minimum token A to receive
- `min-amount-b` (uint): Minimum token B to receive

**Returns:** Tuple with amounts received

### Trading

#### `swap-exact-tokens-for-tokens`
Swaps an exact amount of input tokens for output tokens.

**Parameters:**
- `pool-id` (uint): Pool to use for swap
- `token-in` (principal): Input token
- `amount-in` (uint): Input amount
- `min-amount-out` (uint): Minimum output amount
- `deadline` (uint): Transaction deadline block

**Returns:** Output amount (uint)

### Staking

#### `stake-tokens`
Stakes tokens for a specified lock period to earn rewards.

**Parameters:**
- `token` (principal): Token to stake
- `amount` (uint): Amount to stake
- `lock-period` (uint): Lock period in blocks

**Returns:** Stake ID (uint)

#### `unstake-tokens`
Unstakes tokens after lock period ends.

**Parameters:**
- `stake-id` (uint): Stake ID to unstake

**Returns:** Tuple with principal amount and rewards

### Protocol Management

#### `pause-protocol`
Pauses all protocol operations (owner only).

#### `unpause-protocol`
Resumes protocol operations (owner only).

#### `set-protocol-fee-rate`
Sets the protocol fee rate (owner only).

**Parameters:**
- `new-rate` (uint): New fee rate in basis points

## Read-Only Functions

### Pool Information

#### `get-pool-info`
Returns complete pool information.

**Parameters:**
- `pool-id` (uint): Pool ID

**Returns:** Pool data tuple or none

#### `get-liquidity-position`
Returns liquidity position for a provider.

**Parameters:**
- `provider` (principal): Liquidity provider address
- `pool-id` (uint): Pool ID

**Returns:** Position data or none

#### `get-swap-output`
Calculates expected output for a swap.

**Parameters:**
- `pool-id` (uint): Pool ID
- `token-in` (principal): Input token
- `amount-in` (uint): Input amount

**Returns:** Expected output amount

### Protocol State

#### `get-pool-count`
Returns total number of pools created.

#### `get-protocol-fee-rate`
Returns current protocol fee rate.

#### `is-protocol-paused`
Returns protocol pause status.

#### `get-total-fees-collected`
Returns total fees collected by protocol.

### Staking Information

#### `get-staking-position`
Returns staking position details.

**Parameters:**
- `staker` (principal): Staker address
- `stake-id` (uint): Stake ID

**Returns:** Stake data or none

## Usage Examples

### Creating a Pool

```clarity
(create-pool 
  'SP1234...TOKEN-A 
  'SP5678...TOKEN-B 
  u1000000 
  u1000000 
  u300 
  "constant" 
  u1000000 
  u0)
```

### Adding Liquidity

```clarity
(add-liquidity u1 u500000 u500000 u450000)
```

### Swapping Tokens

```clarity
(swap-exact-tokens-for-tokens 
  u1 
  'SP1234...TOKEN-A 
  u100000 
  u95000 
  (+ block-height u144))
```

### Staking Tokens

```clarity
(stake-tokens 'SP1234...TOKEN-A u1000000 u1440)
```

## Bonding Curves

The protocol supports three types of bonding curves:

### Linear
Price increases linearly with supply.
Formula: `output = (input * param-a) / precision`

### Exponential
Price increases exponentially based on current supply.
Formula: `output = (input * (current-supply * param-a / precision + param-b)) / precision`

### Constant
Fixed price regardless of supply.
Formula: `output = (input * param-a) / precision`

## Mathematical Formulas

### Constant Product AMM
The protocol uses the constant product formula for swaps:
```
x * y = k
output = (input * output-reserve) / (input-reserve + input)
```

### LP Token Calculation
LP tokens for new liquidity providers:
```
lp-tokens = sqrt(amount-a * amount-b)
```

### Staking Rewards
Staking rewards are calculated as:
```
reward = (stake-amount * reward-rate * duration) / (10000 * 144)
```

## Security Considerations

1. **Reentrancy Protection**: Functions validate state before external calls
2. **Integer Overflow**: Safe math functions prevent arithmetic overflow
3. **Access Control**: Critical functions restricted to contract owner
4. **Input Validation**: All inputs validated before processing
5. **Slippage Protection**: Built-in slippage checks for trades
6. **Emergency Pause**: Protocol can be paused in emergency situations

## Deployment

1. Deploy the contract to Stacks blockchain
2. The deployer becomes the contract owner
3. Initialize protocol parameters as needed
4. Create initial pools and provide liquidity