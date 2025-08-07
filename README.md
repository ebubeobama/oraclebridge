# Oracle Bridge - Smart Contract Documentation

## Overview
Oracle Bridge is a decentralized price oracle aggregator that combines multiple data sources, implements outlier detection, and provides time-weighted average pricing for reliable on-chain data.

## Problem Solved
- **Single Point of Failure**: Multiple reporter validation
- **Price Manipulation**: Median and weighted averaging
- **Stale Data**: Freshness checks and staleness thresholds
- **Flash Loan Attacks**: Time-weighted average pricing (TWAP)

## Key Features

### Core Functionality
- Multi-source price aggregation
- Weighted reporter system
- TWAP calculation over 3 windows
- Outlier detection (5% deviation limit)
- Reputation-based weighting

### Security Features
- Minimum reporter requirements
- Staleness detection
- Deviation checks
- Emergency pause
- Round-based submissions

## Contract Functions

### Feed Management

#### `create-feed`
- **Parameters**: symbol, decimals, min-sources
- **Returns**: feed-id
- **Access**: Owner only

#### `register-reporter`
- **Parameters**: name, initial-weight
- **Returns**: reporter-id
- **Access**: Owner only

#### `authorize-reporter`
- **Parameters**: feed-id, reporter-id
- **Effect**: Adds reporter to feed whitelist

### Price Submission

#### `submit-price`
- **Parameters**: feed-id, reporter-id, price, round
- **Requirements**: Authorized reporter, active feed

#### `finalize-round`
- **Parameters**: feed-id, round
- **Returns**: final price
- **Effect**: Calculates median, weighted average, updates TWAP

### Admin Functions
- `update-reporter-weight`: Adjust reporter influence
- `pause-feed`: Temporarily disable feed
- `toggle-emergency`: System-wide pause
- `update-parameters`: Adjust thresholds

### Read Functions
- `get-price`: Current price if fresh
- `get-twap`: Time-weighted average
- `get-feed`: Feed details
- `is-price-fresh`: Check staleness
- `get-aggregation`: Round details

## Usage Examples

```clarity
;; Create price feed for STX/USD
(contract-call? .oracle-bridge create-feed "STX-USD" u8 u3)

;; Register reporter
(contract-call? .oracle-bridge register-reporter 
    u"Chainlink Node 1" u25)

;; Authorize reporter for feed
(contract-call? .oracle-bridge authorize-reporter u1 u1)

;; Submit price
(contract-call? .oracle-bridge submit-price 
    u1           ;; feed-id
    u1           ;; reporter-id
    u250000000   ;; $2.50 with 8 decimals
    u1)          ;; round

;; Finalize round after enough submissions
(contract-call? .oracle-bridge finalize-round u1 u1)

;; Read current price
(contract-call? .oracle-bridge get-price u1)
```

## Price Aggregation

### Weighted Average
```
weighted_avg = Σ(price * weight) / Σ(weight)
```

### TWAP Calculation
- 3 window periods (1 hour each)
- Rolling average across windows
- Resistant to manipulation

### Deviation Check
```
deviation = |new_price - current_price| / current_price
Must be < 5% (configurable)
```

## Security Parameters
- **Min Reporters**: 3 (default)
- **Max Deviation**: 5%
- **Staleness**: 360 blocks (~1 hour)
- **Update Interval**: 6 blocks (~1 minute)

## Deployment
1. Deploy contract
2. Create price feeds
3. Register trusted reporters
4. Authorize reporters per feed
5. Begin price submissions

## Testing Checklist
- Multi-reporter submission
- Median calculation
- Weighted averaging
- TWAP updates
- Deviation rejection
- Staleness detection
- Emergency pause

## Reporter Management
- Reputation scoring (0-1000)
- Weight adjustment (0-100)
- Performance tracking
- Automatic reputation updates

## Use Cases
- **DeFi Protocols**: Lending/borrowing rates
- **Synthetic Assets**: Price feeds
- **Derivatives**: Settlement prices
- **Insurance**: Trigger events
