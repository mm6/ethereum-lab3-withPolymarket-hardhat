##  Developing Blockchain Use Cases  Spring 2026
### Carnegie Mellon University
### Due to Canvas: Friday, April 24, 2026
### Assigned: Monday, April 6, 2026
### 10 Points
### Deliverable: A single .pdf file named Lab3.pdf with clearly labelled answers.

### Students may choose to do this lab or the less challenging lab
### (Traditional) titled ethereum-lab3-hardhat.

Authors: Justin Grose and Michael McCarthy

# Prediction Market Lab — Hardhat & Polymarket

This lab walks you through the core mechanics of an on-chain prediction market: deploying a Conditional Token Framework, signing off-chain orders, matching them on-chain, and resolving a market. In Part 2 you connect to the live Polymarket order book to observe real data.

---

## Prerequisites

### Node.js

You must be on Node 18 or 20 LTS. Node 23+ is not supported by Hardhat. The recommended way to manage Node versions on Windows is [nvm-windows](https://github.com/coreybutler/nvm-windows/releases).

```powershell
nvm install 20
nvm use 20
node --version   # should print v20.x.x
```

On macOS/Linux use [nvm](https://github.com/nvm-sh/nvm):

```bash
nvm install 20
nvm use 20
```

---

## Part 1 — Local Hardhat Simulation

### 1. Initialize the project

Create a new directory somewhere.

```powershell
mkdir C:\dev\lab3
cd C:\dev\lab3
npm init -y
```

### 2. Install dependencies

The Conditional Tokens contracts will be installed under node_modules/@gnosis.pm/conditional-tokens-contracts. The core contract is ConditionalTokens.sol, which implements the ERC‑1155 multi‑token standard. Polymarket uses this Gnosis Conditional Tokens implementation to represent YES and NO outcome positions on‑chain.

Polymarket does not deploy a new ConditionalTokens contract for each market.
Instead, there is a single, shared ConditionalTokens contract on a given blockchain. All Polymarket markets live inside that one contract, and
each market/outcome is represented by different token IDs, not different contracts.

The core idea in ERC-1155 is many token types may be stored in one contract.
It is a general purpose token container. A token ID represents a token type and balances look like balances[address][tokenId] → amount.

In Polymarket, this model is used so that Alice may hold 15 YES outcome tokens for a particular market, tracked as balances[Alice][yesTokenId] = 15, while Bob may hold 20 NO outcome tokens for that market (or another), tracked as balances[Bob][noTokenId] = 20. These ERC‑1155 tokens are collateralized by USDC and redeemable for USDC when the market resolves.

When you buy YES shares on Polymarket, your balance of an ERC‑1155 token increases. Your YES position is identified by the address of the ConditionalTokens contract and a specific token ID (the YES position ID).
Internally, the contract maps your address and that token ID to a balance, which represents the number of YES outcome tokens you control.

In summary, here is the ERC-1155 accounting model:
For a given user address: Their YES position in some market is just
balances[user][tokenID_X] and their NO position in some market is balances[user][tokenID_Y], where tokenID_X != tokenID_Y. Note that tokenID (or positionID) is actually a unique hash of the following: The collateral token (e.g., USDC) along with the condition ID (the market), and the outcome set (YES or NO).


```powershell
npm install --save-dev "@nomicfoundation/hardhat-toolbox@hh2"
npm install @gnosis.pm/conditional-tokens-contracts
npm install @openzeppelin/contracts
```

`hardhat-toolbox` bundles ethers v6, Chai, Mocha, and the Hardhat network helpers in one package. The Gnosis and OpenZeppelin packages provide the `ConditionalTokens` contract and standard token primitives respectively.

### 3. Initialize Hardhat

```powershell
npx hardhat init
```

Select **Create a JavaScript project** when prompted. Accept the defaults.

### 4. Configure Hardhat

Replace the contents of `hardhat.config.js` with the following:

```javascript
require("@nomicfoundation/hardhat-toolbox");

module.exports = {
  defaultNetwork: "localhost",
  networks: {
    hardhat: {
      initialBaseFeePerGas: 0,
      chainId: 31337
    },
    localhost: {
      url: "http://127.0.0.1:8545"
    }
  },
  solidity: "0.5.14",
};
```

The Solidity version must be `0.5.14` to match the `ConditionalTokens` contract from Gnosis. Setting `defaultNetwork` to `localhost` means you do not need to pass `--network localhost` explicitly on every command, though doing so is harmless.

### 5. Project structure

Your project should look like this before you begin:

```
lab3/
├── contracts/
│   ├── Imports.sol          ← provided
│   ├── SimpleExchange.sol   ← provided
│   └── MyAdvancedToken.sol  ← provided
├── scripts/
│   └── run-exchange-hw.js   ← your homework file (copy it here)
├── hardhat.config.js        ← configured above
└── package.json
```

### 6. Compile

```powershell
npx hardhat compile
```

You should see `Compiled N Solidity files successfully`. If you see `HH411: library not installed`, re-check that the npm installs in Step 2 completed without errors.

### 7. Run the local node

Open a dedicated terminal and leave it running for the duration of the lab:

```powershell
npx hardhat node
```

This starts a local Ethereum network at `http://127.0.0.1:8545` and prints 20 funded test accounts. The first account is `Alice`, the second is `Bob`, and so on — matching the order in which `ethers.getSigners()` returns them.

### 8. Run the script

In a second terminal:

```powershell
npx hardhat run scripts/run-exchange-hw.js
```

Observe the output. Read the file thoroughly before making changes to understand what is going on.

---

## Exercises

Complete exercises E1–E8 marked in `run-exchange-hw.js`.

| Exercise | Task |
|----------|------|
| E1 | Declare additional signers |
| E2 | Transfer oracle authority from Alice to Gertrude |
| E3 | Fund Diane, Eden, and Frank with collateral and approvals |
| E4 | Create and sign orders, with one matchable pair and one orphan |
| E5 | Submit the match; attempt and catch the failed match |
| E6 | Verify balances confirm the unmatched buyer's collateral was untouched |
| E7 | Attempt resolution from unauthorized and authorized accounts; observe behavior before and after E2 |
| E8 | Redeem all position holders and verify the market is zero-sum |

**For each exercise, include a screenshot of your terminal output as part of your submission.** The screenshot should show the relevant console output that demonstrates the exercise is working — a successful match, a caught revert, a balance check, etc. Screenshots of blank or erroring terminals will not receive credit.

---

## Part 2 — Live Polymarket Order Book

In this section you connect to the real Polymarket CLOB (Central Limit Order Book) API and retrieve live order book data for four active markets. You are not expected to have prior experience with this API — figuring out how to authenticate, find relevant markets, and parse the response is part of the exercise.

**You are encouraged to use an LLM to help you with this section.** The Polymarket CLOB API is well-documented and LLMs are generally familiar with it. Treat the LLM as a collaborator: ask it to help you understand the API structure, debug your requests, or explain concepts you are uncertain about. That said, the written analysis at the end must reflect your own thinking — an LLM can help you understand the data, but the interpretation should be yours.

A useful starting point: `https://docs.polymarket.com`

### Task

Write a python or javascript program that retrieves the current order book for four active Polymarket markets of your choosing and computes the **spread** on each — the gap between the best available ask and the best available bid on the YES outcome token. Pick markets that are meaningfully different from each other in terms of topic and time horizon.

Your script should produce a formatted summary showing, at minimum, the market question, best bid, best ask, and spread for each of the four markets.

### Written analysis

In a short written section accompanying your script, address the following:

1. Which market had the tightest spread, and what does that imply about how much consensus or liquidity exists in that market?
2. Which had the widest spread, and what are plausible explanations?
3. How does the spread relate to the implied probability of the YES outcome? Is there a pattern across your four markets?


---

## Submission

Submit the following on the single pdf file:

- `run-exchange-hw.js` with all exercises completed
- A screenshot for each of E1–E8 showing the relevant terminal output
- `polymarket-spreads.js` or `polymarket-spreads.py` with working output
- Written responses to the three analysis questions in Part 2
