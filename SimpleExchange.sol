// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.6.0;
pragma experimental ABIEncoderV2;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";

/// @notice Minimal IERC20 interface
//  An external ERC-20 contract (e.g., MyAdvancedToken or USDC) implements
//  these functions.
interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);
    function balanceOf(address who) external view returns (uint256);
}

/// @notice Minimal CTF interface
//  This interface exposes just enough of the Conditional Tokens Framework
//  for our exchange to work. Here, we only declare the functions that we
//  need.
interface IConditionalTokens {

    // splitPosition locks ERC‑20 collateral. Before splitPosition is
    // invoked, a match between complementary orders (for example,
    // a YES buy order and a NO buy order) must occur, ensuring that
    // the collateral supplied by both sides fully backs the newly
    // created outcome tokens. The matching would occur off-chain. The
    // minting occurs on-chain.
    // Suppose the question is "Smith will win the election in 2032".
    // Alice would like to buy  5 "yes" bets for .2 USDC and Bob
    // would like to buy  5 "no" for .8 USDC. This is a match. After
    // the call to splitPosition, both players will receive 5 tokens.
    // Each token will be associated with a different outcome.
    // collateralToken is the ERC20 contract address
    // parentCollectionId is 0, not used by Polymarket
    // conditionId conditionId is a bytes32 hash that uniquely
    // identifies a specific prediction question together with
    // its oracle and the number of possible outcomes.
    // partition partition defines how a market’s possible outcomes
    // are grouped into separate outcome tokens, such as YES and NO,
    // when collateral is split.
    // amount specifies how much ERC‑20 collateral is locked in the
    // Conditional Tokens contract and therefore how many outcome tokens
    // are minted.
    function splitPosition(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    // mergePositions burns complementary outcome tokens
    // and unlocks the underlying ERC-20 collateral,
    // reversing a previous splitPosition.
    // This functionality is not used by SimpleExchange. Instead,
    // it may be called by a single user or contract that holds all
    // complementary outcome tokens in order to reclaim the locked
    // collateral.
    function mergePositions(
        address collateralToken,
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256[] calldata partition,
        uint256 amount
    ) external;

    // getPositionId hashes to compute the ERC‑1155
    // token ID that represents a specific outcome position,
    // given a collateral token and an outcome collection.
    // Used to compute yesPositionId and noPositionId.
    function getPositionId(
        address collateralToken,
        bytes32 collectionId
    ) external pure returns (uint256);

    // getCollectionId deterministically computes a collection
    // identifier that represents a specific subset of outcomes
    // for a given question. The collectionId encodes the parent
    // collection, the prediction
    // question (conditionId), and the chosen outcome index
    // set (e.g. YES or NO). It is an intermediate identifier used
    // to derive ERC-1155 position IDs.
    // Conceptually:
    //    collectionId = hash(parentCollectionId, conditionId, indexSet)
    // This is not used by SimpleExchange
    function getCollectionId(
        bytes32 parentCollectionId,
        bytes32 conditionId,
        uint256 indexSet
    ) external view returns (bytes32);

    // balanceOf returns the number of outcome tokens (ERC-1155 tokens)
    // owned by a given address for a specific outcome position.
    // The positionId uniquely identifies the market outcome (e.g. YES or NO),
    // and the returned value represents how many such outcome tokens
    // the owner currently controls.

    function balanceOf(
        address owner,
        uint256 positionId
    ) external view returns (uint256);

    // safeTransferFrom moves ERC‑1155 outcome tokens (such as YES or NO)
    // between addresses while enforcing safety checks required by the
    // ERC‑1155 standard.
    // Alice sells NO tokens by approving the exchange, after which
    // the exchange—not Alice—calls safeTransferFrom to move the
    // tokens atomically with payment.
    // id is the ERC‑1155 token ID, and in Conditional Tokens that
    // ID is the positionId for a specific market outcome (YES or NO).
    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external;
}

/// @notice ERC1155 receiver hooks
//  These functions are callbacks that a contract must implement
//  if it wants to receive ERC‑1155 tokens.
interface IERC1155TokenReceiver {
    function onERC1155Received(address, address, uint256, uint256, bytes calldata) external returns (bytes4);
    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata) external returns (bytes4);
}

/// @title SimpleExchange
/// @notice A hybrid-decentralized exchange for binary prediction markets.
///         It is hybrid-decentralized because the matching is done off chain.
///         Users sign orders off-chain using EIP-712. An operator matches
///         compatible orders off-chain, then submits them to this contract
///         for atomic on-chain settlement via the CTF.
///
///         Two settlement modes:
///         1. fillOrder — settle between two users who already hold outcome tokens
///         2. matchAndMint — two complementary orders (YES buyer + NO buyer) whose
///            prices sum to >= 1.00. The contract mints new tokens via splitPosition.
// This contract:
// does not run an on‑chain order book,
// relies on off‑chain order creation and matching,
// but settles trades trustlessly on‑chain.
// Alice and Bob never “send USDC directly.” They authorize the
// exchange, and the exchange pulls USDC from them via the USDC
// contract.

// Notes on fillOrder not matchAndMint:
// fillOrder is secondary trading not minting.
// If Alice already owns Yes or No tokens she can simply
// sell some to Bob. No new outcome tokens need to be minted.
// Bob has already approved the exchange to take his USDC.
// The exchange can move some of his USDC to Alice. The
// exchange is an authorized mover and not a custodian.
// When trading already‑minted outcome tokens, the exchange
// simply moves USDC from buyer to seller and ERC‑1155 tokens
// from seller to buyer, without minting or holding assets.

// matchAndMint handles the case where no outcome tokens yet exist.
// A match between complementary buy orders (e.g., YES and NO) has
// occurred off-chain, and each side supplies collateral via USDC.
// The exchange pulls collateral from both parties (transfers USDC to itself)
// and calls splitPosition
// to mint new ERC-1155 outcome tokens, and distributes YES tokens to
// the YES buyer and NO tokens to the NO buyer. The exchange temporarily
// holds collateral for minting purposes but is not a long-term custodian.

// The collateral is temporarily held by the exchange but is then
// locked inside the Conditional Tokens contract and stays there until:
// the market is resolved, and the winning outcome tokens are redeemed.

// When the oracle resolves the question and settles the market,
// the winning outcome tokens can be redeemed. Redemption causes
// the Conditional Tokens contract to release the locked USDC,
// which is sent to whoever currently holds the winning tokens.
// At no point does SimpleExchange have custody of funds after minting.

// All long‑term escrow and payout logic lives in:
// the Conditional Tokens contract, and
// the oracle resolution mechanism.

// In Polymarket, the oracle’s decision—right or wrong—is the final
// authority, and the blockchain will faithfully enforce it without
// the ability to appeal after settlement.

contract SimpleExchange is IERC1155TokenReceiver {
    using SafeMath for uint256;

    // ──────────────────────────────────────────────
    //  EIP-712 Domain
    // ──────────────────────────────────────────────

    bytes32 public DOMAIN_SEPARATOR;

    // keccak256("Order(address maker,uint256 tokenId,bool isBuy,uint256 price,uint256 amount,uint256 nonce,uint256 expiration)")
    bytes32 public constant ORDER_TYPEHASH = keccak256(
        "Order(address maker,uint256 tokenId,bool isBuy,uint256 price,uint256 amount,uint256 nonce,uint256 expiration)"
    );

    // ──────────────────────────────────────────────
    //  State
    // ──────────────────────────────────────────────

    struct Order {
        address maker;      // who signed the order
        uint256 tokenId;    // CTF position ID (YES or NO)
        bool isBuy;         // true = buying outcome tokens, false = selling
        uint256 price;      // price per token in collateral (scaled by 1e18, so 0.60 = 6e17)
        uint256 amount;     // number of outcome tokens to buy/sell
        uint256 nonce;      // unique per maker, prevents replay
        uint256 expiration; // block.timestamp after which order is invalid (0 = no expiry)
    }

    IConditionalTokens public ctf;
    IERC20 public collateral;
    bytes32 public conditionId;

    uint256 public yesPositionId;
    uint256 public noPositionId;
    uint256[] private _partition;

    address public operator;

    // nonce => filled flag (prevents replay)
    mapping(bytes32 => bool) public orderFilled;

    // ──────────────────────────────────────────────
    //  Events
    // ──────────────────────────────────────────────

    event OrdersMatched(
        address indexed makerA,
        address indexed makerB,
        uint256 tokenId,
        uint256 amount,
        uint256 priceA,
        uint256 priceB
    );

    event OrdersMintMatched(
        address indexed yesBuyer,
        address indexed noBuyer,
        uint256 amount,
        uint256 yesPrice,
        uint256 noPrice
    );

    // ──────────────────────────────────────────────
    //  Constructor
    // ──────────────────────────────────────────────

    constructor(
        address _ctf,
        address _collateral,
        bytes32 _conditionId
    ) public {
        ctf = IConditionalTokens(_ctf);
        collateral = IERC20(_collateral);
        conditionId = _conditionId;
        operator = msg.sender;

        _partition = new uint256[](2);
        _partition[0] = 1; // YES
        _partition[1] = 2; // NO

        bytes32 yesCollectionId = ctf.getCollectionId(bytes32(0), _conditionId, 1);
        bytes32 noCollectionId  = ctf.getCollectionId(bytes32(0), _conditionId, 2);
        yesPositionId = ctf.getPositionId(_collateral, yesCollectionId);
        noPositionId  = ctf.getPositionId(_collateral, noCollectionId);

        // EIP-712 domain separator
        DOMAIN_SEPARATOR = keccak256(abi.encode(
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
            keccak256("SimpleExchange"),
            keccak256("1"),
            _getChainId(),
            address(this)
        ));
    }

    // ──────────────────────────────────────────────
    //  ERC1155 Receiver
    // ──────────────────────────────────────────────

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external returns (bytes4) {
        return this.onERC1155Received.selector;
    }

    function onERC1155BatchReceived(address, address, uint256[] calldata, uint256[] calldata, bytes calldata)
        external returns (bytes4) {
        return this.onERC1155BatchReceived.selector;
    }

    // ──────────────────────────────────────────────
    //  Order hashing & verification
    // ──────────────────────────────────────────────

    /// @notice Compute the EIP-712 hash of an order
    function hashOrder(Order memory order) public view returns (bytes32) {
        return keccak256(abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR,
            keccak256(abi.encode(
                ORDER_TYPEHASH,
                order.maker,
                order.tokenId,
                order.isBuy,
                order.price,
                order.amount,
                order.nonce,
                order.expiration
            ))
        ));
    }

    /// @notice Recover signer from an order + signature
    function recoverSigner(Order memory order, bytes memory signature) public view returns (address) {
        bytes32 digest = hashOrder(order);
        require(signature.length == 65, "invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        if (v < 27) v += 27;
        require(v == 27 || v == 28, "invalid v");

        return ecrecover(digest, v, r, s);
    }

    // ──────────────────────────────────────────────
    //  Settlement: fillOrder
    //  Settles a buy order against a sell order for
    //  the SAME token. Seller must already hold tokens.
    // ──────────────────────────────────────────────

    /// @notice Match a buy order with a sell order for the same tokenId.
    ///         The buyer pays collateral, the seller delivers outcome tokens.
    ///         Only callable by the operator.
    function fillOrder(
        Order memory buyOrder,
        bytes memory buySig,
        Order memory sellOrder,
        bytes memory sellSig
    ) public {
        require(msg.sender == operator, "only operator");

        // Validate orders
        require(buyOrder.isBuy, "first order must be buy");
        require(!sellOrder.isBuy, "second order must be sell");
        require(buyOrder.tokenId == sellOrder.tokenId, "token mismatch");
        require(buyOrder.price >= sellOrder.price, "price mismatch: buy < sell");

        // Check expiration
        if (buyOrder.expiration > 0) require(now <= buyOrder.expiration, "buy order expired");
        if (sellOrder.expiration > 0) require(now <= sellOrder.expiration, "sell order expired");

        // Verify signatures
        require(recoverSigner(buyOrder, buySig) == buyOrder.maker, "invalid buy signature");
        require(recoverSigner(sellOrder, sellSig) == sellOrder.maker, "invalid sell signature");

        // Check not already filled
        bytes32 buyHash = hashOrder(buyOrder);
        bytes32 sellHash = hashOrder(sellOrder);
        require(!orderFilled[buyHash], "buy order already filled");
        require(!orderFilled[sellHash], "sell order already filled");

        // Fill at the buy price (taker-friendly)
        uint256 fillAmount = buyOrder.amount < sellOrder.amount ? buyOrder.amount : sellOrder.amount;
        uint256 fillPrice = buyOrder.price;

        // cost = fillAmount * fillPrice / 1e18
        uint256 cost = fillAmount.mul(fillPrice).div(1e18);

        // Mark as filled
        orderFilled[buyHash] = true;
        orderFilled[sellHash] = true;

        // Transfer collateral: buyer -> seller
        require(
            collateral.transferFrom(buyOrder.maker, sellOrder.maker, cost),
            "collateral transfer failed"
        );

        // Transfer tokens: seller -> buyer
        ctf.safeTransferFrom(sellOrder.maker, buyOrder.maker, buyOrder.tokenId, fillAmount, "");

        emit OrdersMatched(
            buyOrder.maker,
            sellOrder.maker,
            buyOrder.tokenId,
            fillAmount,
            buyOrder.price,
            sellOrder.price
        );
    }

    // ──────────────────────────────────────────────
    //  Settlement: matchAndMint
    //  Matches a YES buyer with a NO buyer whose prices
    //  sum to >= 1.00. Mints new tokens via splitPosition.
    //  This is how Polymarket creates new token supply.
    // ──────────────────────────────────────────────

    /// @notice Match a YES buyer with a NO buyer. Their collateral
    ///         is combined, split into YES+NO via the CTF, and each
    ///         buyer receives their desired tokens.
    ///         Only callable by the operator.
    function matchAndMint(
        Order memory yesBuyOrder,
        bytes memory yesBuySig,
        Order memory noBuyOrder,
        bytes memory noBuySig
    ) public {
        require(msg.sender == operator, "only operator");

        // Validate: both must be buy orders for opposite outcomes
        require(yesBuyOrder.isBuy, "first order must be buy");
        require(noBuyOrder.isBuy, "second order must be buy");
        require(yesBuyOrder.tokenId == yesPositionId, "first must be YES");
        require(noBuyOrder.tokenId == noPositionId, "second must be NO");

        // Prices must sum to >= 1e18 (i.e. $1.00)
        require(yesBuyOrder.price.add(noBuyOrder.price) >= 1e18, "prices don't cover full token");

        // Check expiration
        if (yesBuyOrder.expiration > 0) require(now <= yesBuyOrder.expiration, "yes order expired");
        if (noBuyOrder.expiration > 0) require(now <= noBuyOrder.expiration, "no order expired");

        // Verify signatures
        require(recoverSigner(yesBuyOrder, yesBuySig) == yesBuyOrder.maker, "invalid yes signature");
        require(recoverSigner(noBuyOrder, noBuySig) == noBuyOrder.maker, "invalid no signature");

        // Check not already filled
        bytes32 yesHash = hashOrder(yesBuyOrder);
        bytes32 noHash = hashOrder(noBuyOrder);
        require(!orderFilled[yesHash], "yes order already filled");
        require(!orderFilled[noHash], "no order already filled");

        // Fill the minimum of both amounts
        uint256 fillAmount = yesBuyOrder.amount < noBuyOrder.amount
            ? yesBuyOrder.amount
            : noBuyOrder.amount;

        // Each buyer pays their price * fillAmount
        uint256 yesCost = fillAmount.mul(yesBuyOrder.price).div(1e18);
        uint256 noCost  = fillAmount.mul(noBuyOrder.price).div(1e18);

        // Mark as filled
        orderFilled[yesHash] = true;
        orderFilled[noHash] = true;

        // Pull collateral from both buyers to this contract
        require(
            collateral.transferFrom(yesBuyOrder.maker, address(this), yesCost),
            "yes buyer collateral transfer failed"
        );
        require(
            collateral.transferFrom(noBuyOrder.maker, address(this), noCost),
            "no buyer collateral transfer failed"
        );

        // Split `fillAmount` collateral into YES + NO tokens
        // (requires exactly fillAmount of collateral)
        require(collateral.approve(address(ctf), fillAmount), "approve failed");
        ctf.splitPosition(address(collateral), bytes32(0), conditionId, _partition, fillAmount);

        // Send YES tokens to the YES buyer
        ctf.safeTransferFrom(address(this), yesBuyOrder.maker, yesPositionId, fillAmount, "");

        // Send NO tokens to the NO buyer
        ctf.safeTransferFrom(address(this), noBuyOrder.maker, noPositionId, fillAmount, "");

        // Any surplus collateral (if prices summed to > 1.00) stays in the
        // contract as operator revenue. In production you'd handle this more
        // carefully.

        emit OrdersMintMatched(
            yesBuyOrder.maker,
            noBuyOrder.maker,
            fillAmount,
            yesBuyOrder.price,
            noBuyOrder.price
        );
    }

    // ──────────────────────────────────────────────
    //  Helpers
    // ──────────────────────────────────────────────

    function _getChainId() internal pure returns (uint256 chainId) {
        assembly { chainId := chainid() }
    }
}
