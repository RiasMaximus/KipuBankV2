# KipuBankV2

This project is an improved version of the original KipuBank smart contract developed in class.  
The objective was to upgrade the first version, adding more features, security, and support for multiple assets.

---

## What was improved

- Support for **ETH and ERC-20 tokens**
- **Nested mappings** to manage user balances per token
- Internal value conversion to a **USD-based unit** (6 decimals)
- **Chainlink ETH/USD** price feed to check ETH value
- **Bank limit** (cap in USD) to control deposits
- **Access control** with roles for admin and risk manager
- **Pause** function for emergency situations
- **Reentrancy protection** and safe withdrawal pattern

---

## Contract main features

| Feature | Description |
|--------|-------------|
| Deposit | ETH and tokens can be deposited |
| Withdraw | Users can withdraw what they deposited |
| Price Feed | Converts ETH to USD (internal accounting) |
| Token config | Admin can enable/disable ERC-20 tokens |
| Bank cap | ETH deposits cannot exceed the limit |
| Security | Checks-effects-interactions + ReentrancyGuard |

---

## Technologies Used

- Solidity ^0.8.24
- OpenZeppelin (AccessControl, ReentrancyGuard, ERC-20)
- Chainlink Oracle (ETH/USD)

---

## Deployment Instructions (Remix + Sepolia)

1. Open https://remix.ethereum.org
2. Create the file `src/KipuBankV2.sol` and paste the contract
3. Compile with Solidity version 0.8.24
4. Select “Injected Provider — MetaMask”
5. Deploy using:
   - `admin`: wallet address
   - `priceFeed`: Sepolia ETH/USD feed  
     `0x694AA1769357215DE4FAC081bf1f309aDC325306`
   - `initialBankCapUsd`: example → `1000000e6`

---

## How to interact

Example functions to test in Remix UI:

- `depositNative()` (with value in ETH)
- `depositToken(token, amount)`
- `withdrawNative(amount)`
- `withdrawToken(token, amount)`
- `balanceOf(token, user)`
- `internalUsdBalanceOf(user)`

---

## Deployment Information

> To update after deployment

- Network: Sepolia
- Contract address: `<fill_here>`
