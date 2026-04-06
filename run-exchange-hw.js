// run-exchange-hw.js
// This is a demo of a Polymarket‑style hybrid exchange.
// Created by Justin Grose 

const { ethers } = require("hardhat");

async function main() {
  // E1: Add Diane, Eden, Frank as buyers and Gertrude as a separate oracle.
  // Set up signers. Alice is the deployer and exchange operator
  const [Alice, Bob, Charlie] = await ethers.getSigners();
  console.log("Alice (operator):", Alice.address);
  console.log("Bob   (buyer):      ", Bob.address);
  console.log("Charlie (buyer):     ", Charlie.address);

  // ─────────────────────────────────────────────
  //  Step 1: Deploy three contracts: MyAdvancedToken, ConditionalTokens,
  //  and Exchange (ConditionalTokens is in a subdirectory of node_modules)
  // ─────────────────────────────────────────────
  console.log("\n=== DEPLOYING CONTRACTS ===");

  // MyAdvancedToken will act as a USDC substitute - Both are ERC-20
  const Token = await ethers.getContractFactory("MyAdvancedToken");
  const token = await Token.deploy(1000000, "Alice Coin", "AC");
  await token.waitForDeployment();
  const tokenAddress = await token.getAddress();
  console.log("Token:", tokenAddress);

  // This is the canonical Gnosis ConditionalTokens contract
  // It is deployed once, not per market.
  // This was downloaded into node_modules and is not in the contracts
  // directory.
  const CTF = await ethers.getContractFactory("ConditionalTokens");
  const ctf = await CTF.deploy();
  await ctf.waitForDeployment();
  const ctfAddress = await ctf.getAddress();
  console.log("CTF:  ", ctfAddress);

  // The questionId is the hash of the question
  const questionId = ethers.keccak256(
    ethers.toUtf8Bytes("Will North Dakota and South Dakota unify into one Dakota before 1 May 2026?")
  );

  // E2: Transfer oracle authority to Gertrude.
  // Polymarket calls prepareCondition when it creates a new market.
  // This happens before any trading occurs.
  // prepareCondition registers a prediction question in the
  // Conditional Tokens contract by specifying its oracle, unique
  // identifier, and number of possible outcomes, enabling outcome
  // tokens to be minted and later resolved.
  // prepareCondition is the on‑chain declaration of
  // “this question exists and this oracle will decide it,” and
  // everything else in the market depends on that declaration.
  // Currently, we use Alice as our oracle.
  await ctf.prepareCondition(Alice.address, questionId, 2);
  const conditionId = await ctf.getConditionId(Alice.address, questionId, 2);
  console.log("Condition ID:", conditionId);

  // This code deploys a new instance of the SimpleExchange
  // contract, initializes it with the addresses it depends on
  // (ConditionalTokens, collateral token, and market condition),
  // waits for the deployment to be mined, and prints the exchange’s
  // on‑chain address.
  const Exchange = await ethers.getContractFactory("SimpleExchange");
  const exchange = await Exchange.deploy(ctfAddress, tokenAddress, conditionId);
  await exchange.waitForDeployment();
  const exchangeAddress = await exchange.getAddress();
  console.log("Exchange:", exchangeAddress);

  // yesPositionId uniquely identifies the YES outcome token
  // noPositionId uniquely identifies the NO outcome token
  // These IDs are what the exchange (and the Conditional Tokens contract)
  // use to track balances and transfer outcome tokens.
  const yesPositionId = await exchange.yesPositionId();
  const noPositionId = await exchange.noPositionId();

  // ─────────────────────────────────────────────
  //  Step 2: Fund Buyers with collateral
  // ─────────────────────────────────────────────
  console.log("\n=== FUNDING ACCOUNTS ===");
  // The constant ONE = 10^18 base units (ERC-20 smallest unit)
  // This is one full token expressed in base units.
  const ONE = ethers.parseEther("1");

  // E3: Fund Diane, Eden, and Frank.
  // This code gives Bob and Charlie large balances of the ERC‑20
  // collateral token and authorizes the SimpleExchange contract
  // to spend those tokens on their behalf.
  // Bob and Charlie get 10,000 * 10^18 base units of Alice Coin
  await token.mintToken(Bob.address, ONE * 10000n);
  await token.mintToken(Charlie.address, ONE * 10000n);
  console.log("Bob balance:    ", ethers.formatEther(await token.balanceOf(Bob.address)));
  console.log("Charlie balance:", ethers.formatEther(await token.balanceOf(Charlie.address)));

  // Approve the exchange to spend these ERC-20 tokens
  await token.connect(Bob).approve(exchangeAddress, ONE * 10000n);
  await token.connect(Charlie).approve(exchangeAddress, ONE * 10000n);

  // ─────────────────────────────────────────────
  //  Step 3: Sign orders OFF-CHAIN
  // ─────────────────────────────────────────────

  // When Bob signs a request (order) and sends it to Polymarket,
  // Polymarket verifies the signature off‑chain to confirm that
  // Bob controls the corresponding private key. Later, the
  // exchange contract independently verifies the same signature
  // on‑chain before executing any trade.

  console.log("\n=== SIGNING ORDERS OFF-CHAIN ===");

  const network = await ethers.provider.getNetwork();
  const domain = {
    name: "SimpleExchange",
    version: "1",
    chainId: Number(network.chainId),
    verifyingContract: exchangeAddress,
  };

  // This snippet defines the EIP‑712 typed data schema for an order.
  // It tells wallets exactly what fields are being signed, in what
  // order, and with what Solidity types, so both the off‑chain
  // signer and the on‑chain verifier compute the same hash.
  const orderTypes = {
    Order: [
      { name: "maker",      type: "address" },
      { name: "tokenId",    type: "uint256" },
      { name: "isBuy",      type: "bool"    },
      { name: "price",      type: "uint256" },
      { name: "amount",     type: "uint256" },
      { name: "nonce",      type: "uint256" },
      { name: "expiration", type: "uint256" },
    ],
  };
  // This object represents Bob’s intent to buy a specific
  // number of YES outcome tokens at a fixed price, expressed
  // as an EIP‑712–signable order.
  // Bob will sign this object off‑chain. That signature authorizes
  // the exchange to execute exactly this trade, under these exact
  // terms, if a matching order exists.
  // No funds move yet. No transaction occurs yet. This is authorization,
  // not execution.

  const bobOrder = {
    maker:      Bob.address,
    tokenId:    yesPositionId,
    isBuy:      true,
    price:      ethers.parseEther("0.60"),
    amount:     ethers.parseEther("100"),
    nonce:      1,
    expiration: 0,
  };

  const charlieOrder = {
    maker:      Charlie.address,
    tokenId:    noPositionId,
    isBuy:      true,
    price:      ethers.parseEther("0.40"),
    amount:     ethers.parseEther("100"),
    nonce:      1,
    expiration: 0,
  };

  // E4: Create and sign orders for Diane, Eden, and Frank. Structure them
  // so that exactly one pair matches and one order is left without
  // a valid counterparty.
  // The signatures include the domain, order types, and particular order
  // details.
  const bobSig     = await Bob.signTypedData(domain, orderTypes, bobOrder);
  const charlieSig = await Charlie.signTypedData(domain, orderTypes, charlieOrder);

  console.log("Bob signed:     BUY 100 YES @ $0.60");
  console.log("Charlie signed: BUY 100 NO  @ $0.40");
  console.log("Prices sum to:  $1.00 ✓");
  // Display parts of long signatures
  console.log("\nBob's signature:    ", bobSig.slice(0, 20) + "...");
  console.log("Charlie's signature:", charlieSig.slice(0, 20) + "...");

  // ─────────────────────────────────────────────
  //  Step 4: Operator matches & submits on-chain
  // ─────────────────────────────────────────────

  // Code like this runs on the exchange’s off‑chain computers (servers),
  // and those computers submit transactions to the on‑chain exchange
  // contract to settle matched orders.

  // This code packages Bob’s and Charlie’s signed off‑chain orders
  // into Solidity‑compatible structs and submits them to the exchange
  // contract, which validates the signatures, matches the orders, pulls
  // collateral, and mints new outcome tokens atomically.

  console.log("\n=== OPERATOR MATCHES ORDERS ON-CHAIN ===");

  // Prepare structs to match what is needed by Solidity code on-chain.
  const bobOrderStruct = [
    bobOrder.maker, bobOrder.tokenId, bobOrder.isBuy,
    bobOrder.price, bobOrder.amount, bobOrder.nonce, bobOrder.expiration,
  ];
  const charlieOrderStruct = [
    charlieOrder.maker, charlieOrder.tokenId, charlieOrder.isBuy,
    charlieOrder.price, charlieOrder.amount, charlieOrder.nonce, charlieOrder.expiration,
  ];

  // Send a transaction from an operator account to the exchange
  // contract on the current blockchain network (e.g., Hardhat, testnet,
  // or Polygon). We are invoking matchAndMint.
  const tx = await exchange.matchAndMint(
    bobOrderStruct, bobSig,
    charlieOrderStruct, charlieSig
  );
  const receipt = await tx.wait();
  console.log("Transaction hash:", receipt.hash);
  console.log("Gas used:", receipt.gasUsed.toString());

  //E5: Submit your matched pair from E4. Then attempt to submit your
  //    unmatched order paired with an incompatible counterparty.
  //    Catch the revert and log the reason.

  // ─────────────────────────────────────────────
  //  Step 5: Check results
  // ─────────────────────────────────────────────
  console.log("\n=== RESULTS AFTER MATCH ===");

  const bobYes     = await ctf.balanceOf(Bob.address, yesPositionId);
  const bobNo      = await ctf.balanceOf(Bob.address, noPositionId);
  const charlieYes = await ctf.balanceOf(Charlie.address, yesPositionId);
  const charlieNo  = await ctf.balanceOf(Charlie.address, noPositionId);

  console.log("Bob's YES tokens:    ", ethers.formatEther(bobYes));
  console.log("Bob's NO tokens:     ", ethers.formatEther(bobNo));
  console.log("Charlie's YES tokens:", ethers.formatEther(charlieYes));
  console.log("Charlie's NO tokens: ", ethers.formatEther(charlieNo));

  console.log("\nBob's AC balance:    ", ethers.formatEther(await token.balanceOf(Bob.address)), "(paid 60)");
  console.log("Charlie's AC balance:", ethers.formatEther(await token.balanceOf(Charlie.address)), "(paid 40)");

  //E6: Print balances for Diane, Eden, and Frank. Verify that the unmatched
  //    buyer's collateral was never moved.
  // ─────────────────────────────────────────────
  //  Step 6: Second trade — Bob sells YES to Charlie
  // ─────────────────────────────────────────────
  console.log("\n=== SECOND TRADE: BOB SELLS, CHARLIE BUYS ===");

  const bobSellOrder = {
    maker:      Bob.address,
    tokenId:    yesPositionId,
    isBuy:      false,
    price:      ethers.parseEther("0.70"),
    amount:     ethers.parseEther("50"),
    nonce:      2,
    expiration: 0,
  };

  const charlieBuyOrder = {
    maker:      Charlie.address,
    tokenId:    yesPositionId,
    isBuy:      true,
    price:      ethers.parseEther("0.75"),
    amount:     ethers.parseEther("50"),
    nonce:      2,
    expiration: 0,
  };

  const bobSellSig    = await Bob.signTypedData(domain, orderTypes, bobSellOrder);
  const charlieBuySig = await Charlie.signTypedData(domain, orderTypes, charlieBuyOrder);

  await ctf.connect(Bob).setApprovalForAll(exchangeAddress, true);

  const bobSellStruct = [
    bobSellOrder.maker, bobSellOrder.tokenId, bobSellOrder.isBuy,
    bobSellOrder.price, bobSellOrder.amount, bobSellOrder.nonce, bobSellOrder.expiration,
  ];
  const charlieBuyStruct = [
    charlieBuyOrder.maker, charlieBuyOrder.tokenId, charlieBuyOrder.isBuy,
    charlieBuyOrder.price, charlieBuyOrder.amount, charlieBuyOrder.nonce, charlieBuyOrder.expiration,
  ];

  // Use fillOrder rather than matchAndMint
  await exchange.fillOrder(
    charlieBuyStruct, charlieBuySig,
    bobSellStruct, bobSellSig
  );

  console.log("Bob sold 50 YES to Charlie at $0.75");

  const bobYes2     = await ctf.balanceOf(Bob.address, yesPositionId);
  const charlieYes2 = await ctf.balanceOf(Charlie.address, yesPositionId);
  console.log("Bob's YES tokens:    ", ethers.formatEther(bobYes2));
  console.log("Charlie's YES tokens:", ethers.formatEther(charlieYes2));

  // ─────────────────────────────────────────────
  //  Step 7: Resolve and redeem
  // ─────────────────────────────────────────────
  console.log("\n=== RESOLVING: YES WINS ===");

  //E7: Before resolving, attempt reportPayouts from two accounts: one that
  //    should be rejected and one that should succeed. After completing E2,
  //    re-run and observe whether the outcome changes.

  // An oracle (as established in prepareCondition), makes this call.
  // For a binary market:
  // [1, 0] → YES wins
  // [0, 1] → NO wins

  await ctf.reportPayouts(questionId, [1, 0]);
  console.log("Market resolved: YES wins!");

  const bobYesFinal = await ctf.balanceOf(Bob.address, yesPositionId);
  if (bobYesFinal > 0n) {
    await ctf.connect(Bob).redeemPositions(
      tokenAddress, ethers.ZeroHash, conditionId, [1]
    );
  }

  const charlieYesFinal = await ctf.balanceOf(Charlie.address, yesPositionId);
  if (charlieYesFinal > 0n) {
    await ctf.connect(Charlie).redeemPositions(
      tokenAddress, ethers.ZeroHash, conditionId, [1]
    );
  }

  console.log("\nFinal balances:");
  console.log("Bob's AC:    ", ethers.formatEther(await token.balanceOf(Bob.address)));
  console.log("Charlie's AC:", ethers.formatEther(await token.balanceOf(Charlie.address)));

  //E8: Redeem for all remaining position holders and print final balances for everyone.
  //    Confirm that total AC across all buyers is unchanged from the starting amount.

  console.log("\n✓ Full hybrid order book lifecycle complete!");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
