// Conditional tokens require collateral.
// In the real Polymarket, the collateral token is USDC.
// Here, we use MyAdvancedToken as collateral.



// =========================== MyAdvancedToken.sol Contract =================

/* MyAdvancedToken.sol

   Modified from https://ethereum.org/token.

   This contract has instructional documentation.

   To run the Hardhat console, use:
   npx hardhat console

   On startup, get access to ethers library:
   const { ethers } = require("hardhat");

   Suppose that we want to
   deploy MyAdvancedToken.sol and call the constructor
   with 1300 tokens for Alice. The name is "Alice Coin" and the symbol
   is "AC".

   const Token  = await ethers.getContractFactory("MyAdvancedToken");
   const token = await Token.deploy(1300,"Alice Coin","AC");

   To access accounts from within the Hardhat console:
   const [Alice, Bob, Charlie, Donna] = await ethers.getSigners();

   Get the account address of Alice within a convenient variable:
   const aliceAddr = Alice.address;

   Get the address of the contract within a convenient variable:
   const contractAddr = token.target;

   To send a transaction on behalf of the first account (Alice),
   we just use token.someFunction(). Alice is the default account.
   To send a transaction on behalf of another account, say Bob,
   we use token.connect(Bob).someFunction().

   Get the ether balance (in wei) of an account:
   const AliceWeiBalance = await ethers.provider.getBalance(aliceAddr);
   AliceWeiBalance

   Parse a string holding eth to wei. The 'n' signifies a Javascript BigInt.
   wei = ethers.parseEther("1.0")
   1000000000000000000n

   Create a string holding eth given wei as a BigInt.
   ethString = ethers.formatEther(wei)

   Note on transactions:
   When we execute a transaction, we get back a transaction object that
   contains a transaction hash and other details. But, the transaction is not
   yet confirmed. It has simply been seen by the network. If we are interested
   in the transaction receipt (after it has been confirmed), we would execute:
   receipt = await tx.wait(). For an example, see the documentation around the
   burn() function below.


*/

pragma solidity >=0.4.22 <0.6.0;

contract owned {
    // This state variable holds the address of the owner
    // In a Hardhat script, if token refers to the contract instance,
    // use:
    // let owner = await token.owner();

    address public owner;
    // The original creator is the first owner.

    // The constructor is called once on first deployment.
    constructor() public {
        owner = msg.sender;
    }


    // Add this modifier to restrict function execution
    // to only the current owner.

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }


    // Establish a new owner.
    // The owner calls with the address of the new owner.
    // Suppose deployer Alice gives ownership to Bob.
    // In a Hardhat script, do this:
    // await token.transferOwnership(bobAddr);
    // Of course, now only Bob may transfer ownership back to Alice:
    // await token.connect(Bob).transferOwnership(aliceAddr);
    function transferOwnership(address newOwner) onlyOwner public {
        owner = newOwner;
    }
}


// This interface may be implemented by another contract on the blockchain.
// We can call this function in the other contract.
// We are telling the other contract that it has been approved to
// withdraw from a particular address up to a particular value.
// We include the address of this token contract.

interface tokenRecipient { function receiveApproval(address _from, uint256 _value, address _token, bytes calldata _extraData) external; }

contract TokenERC20 {

    // Public variables of the token
    string public name;
    string public symbol;
    uint8 public decimals = 18;

    /* We can read these data from a Hardhat script with a command such as:
       await token.name()

    */

    // totalSupply established by constructor and increased
    // by mintToken calls

    uint256 public totalSupply;

    /* To access totalSupply in Hardhat do the following:
       await token.totalSupply()

    */

    // This creates an array with all balances.
    // Users (Alice, Bob, Charlie) may have balances.
    // So may the contract itself have a balance.
    // 0 or more addresses and each has a balance.

    mapping (address => uint256) public balanceOf;

    // The token balances are kept with 10^decimal units.
    // If the number of tokens is 1 and we are using 2 decimals
    // then 100 is stored.

    /* To access balanceOf in Hardhat (and display as string) do the following:
       val = await token.balanceOf(aliceAddr);
       val.toString()

    */

    // 0 or more addresses and each has 0 or more addresses each with
    // an allowance.
    // The allowance balances are kept with 10^decimal units.

    mapping (address => mapping (address => uint256)) public allowance;

    // access with Hardhat. How much has Alice allowed Bob to use?
    /*
       val = await token.allowance(aliceAddr,bobAddr);

       Bob might also want to know:
       val = await token.connect(Bob).allowance(aliceAddr,bobAddr);
    */

    // This generates a public event on the blockchain that can be
    // used to notify clients.
    // In Hardhat, we need access to the receipt:
    /*
    let tx = await token.someFunction();   // some function that generates an event
    let receipt = await tx.wait();
    console.log(receipt.events);

    */

    event Transfer(address indexed from, address indexed to, uint256 value);

    // This generates a public event on the blockchain that can be
    // used to notify clients.

    event Approval(address indexed _owner, address indexed _spender, uint256 _value);

    // This can be used to notify clients of the amount of tokens burned.

    event Burn(address indexed from, uint256 value);

    /**
     * Constructor function executes once upon deployment.
     *
     * Initializes the contract with an initial supply of
     * tokens and gives them all to the creator of the
     * contract.
     */

    constructor(
        uint256 initialSupply,
        string memory tokenName,
        string memory tokenSymbol
    ) public {
        // In traditional money, if the initialSupply is 1 dollar then
        // the value stored would be 1 x 10 ^ 2 = 100 cents.
        totalSupply = initialSupply * 10 ** uint256(decimals);
        balanceOf[msg.sender] = totalSupply;
        name = tokenName;
        symbol = tokenSymbol;
    }



    /**
     * Internal transfer, only can be called by this contract.
     * Move tokens from one account to another.
     * Preconditions are specified in the require statements.
     */

    function _transfer(address _from, address _to, uint _value) internal {
        // Prevent transfer to 0x0 address. Use burn() instead
        require(_to != address(0x0));

        // Check if from has enough
        require(balanceOf[_from] >= _value);

        // Check for overflows
        require(balanceOf[_to] + _value > balanceOf[_to]);

        // Save this for an assertion in the future
        uint previousBalances = balanceOf[_from] + balanceOf[_to];

        // Subtract from the from address
        balanceOf[_from] -= _value;

        // Add the same to the recipient
        balanceOf[_to] += _value;

        // Make notification of the transfer
        emit Transfer(_from, _to, _value);

        // Asserts are used to use static analysis to find bugs in your code.
        // They should never fail
        assert(balanceOf[_from] + balanceOf[_to] == previousBalances);
    }



     /* Public transfer of tokens.
        Calls the internal transfer with the message sender as 'from'.
        The caller transfers its own tokens to the specified address.
        precondition: The caller has enough tokens to transfer.
        postcondition: The caller's token count is lowered by the passed value.
                       The specified address gains tokens.

        Suppose Alice wants to transfer 50 tokens to Bob. Using Hardhat we write:
        tx = await token.transfer(bobAddr,'50000000000000000000');
        receipt = await tx.wait();
        receipt.logs[0] is often interesting.

        If we want another player (other than Alice) to do a transfer, use this
        syntax in Hardhat (note: Bob is not a simple address but a signer. See above.)

        tx = await token.connect(Bob).transfer(charlieAddr, '50000000000000000000');
        receipt = await tx.wait();
        receipt.logs[0] is often interesting.

    */

    function transfer(address _to, uint256 _value) public returns (bool success) {
        _transfer(msg.sender, _to, _value);
        return true;
    }



     /* This is a public approve function.
        The message sender approves the included address to
        spend tokens from the sender's account. The upper limit of this approval
        is also specified.
        It only modifies the allowance mapping.
        sender --> spender ---> amount.
        This generates an Approval event in the receipt log.
        The approve call occurs prior to a transferFrom.

        Hardhat: Charlie approves Bob to spend 25 tokens.
        tx = await token.connect(Charlie).approve(bobAddr,'25000000000000000000');
     */

    function approve(address _spender, uint256 _value) public
        returns (bool success) {

        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);

        return true;
    }


     /* This is a public transferFrom function.
        It allows an approved sender to spend from another account.
        Preconditions: The message sender has been approved by the specified
        from address. The approval is of enough value.

        Postcondition: Reduce how much more may be spent by this sender.
        Perform the actual transfer from the 'from' account to the 'to' account.
        Bob pays Donna from Alice's account. Alice issued a prior approval
        for Bob to spend. Bob initiates the transfer request.

        In Hardhat:
            Bob sends 10 of Alice's tokens to Donna.

            await token.connect(Bob).transferFrom(aliceAddr,donnaAddr, '10000000000000000000');

    */

    function transferFrom(address _from, address _to, uint256 _value) public returns (bool success) {
        require(_value <= allowance[_from][msg.sender]);     // Check allowance
        allowance[_from][msg.sender] -= _value;
        _transfer(_from, _to, _value);
        return true;
    }



     /* This is a public approve and call function.
        It provides an allowance for another contract and informs
        that contract of the allowance.
        The message sender approves the included address (a contract) to
        spend from the sender's account. The upper limit of this approval
        is also specified.

        It only modifies the allowance mapping.
        sender --> contract spender ---> amount.
        Because of the approve call, this generates an Approval event in
        the receipt log.

        The approve and call call occurs prior to a transferFrom.

        Hardhat: Requires another deployed contract and the second deployed
        contract must have a receiveApproval function.

        Suppose Bob approves a contract to spend 25 tokens.
        await token.connect(Bob).approveAndCall(contractAddr,'25000000000000000000',"0x00");

     */

    function approveAndCall(address _spender, uint256 _value, bytes memory _extraData)
        public
        returns (bool success) {

        tokenRecipient spender = tokenRecipient(_spender);
        if (approve(_spender, _value)) {
            spender.receiveApproval(msg.sender, _value, address(this), _extraData);
            return true;
        }
    }



     /* This is a public burn function.
        The sender loses tokens and the totalSupply is reduced.

        precondition: The sender must have enough tokens to burn.

        postcondition: The sender loses tokens and so does totalSupply.
                       A burn event is published.

        Hardhat: Suppose Alice wants to burn 1 token and view the event.

        // Send a burn request to the network and get a response when submitted.
        tx = await token.burn('1000000000000000000');
        // Wait for the transaction to be confirmed and get back a receipt.
        const receipt = await tx.wait()
        // Display the logs array and view events that may have been triggered.
        console.log(receipt.logs) or console.log(receipt.logs[0])

    */

    function burn(uint256 _value) public returns (bool success) {
        require(balanceOf[msg.sender] >= _value);
        balanceOf[msg.sender] -= _value;
        totalSupply -= _value;
        emit Burn(msg.sender, _value);
        return true;
    }


     /* This is a public function to burn some tokens that the sender (Bob)
        has been approved to spend from the approver's (Alice) account.

        Suppose Alice has allowed Bob to spend her tokens.
        Bob is allowed to burn them if he wants.

        Precondition:
                      Alice must have the required number of tokens.
                      Alice must have approved Bob to use at least that number.

        Postcondition: Deduct tokens from Alice.
                       Decrease the number of tokens Bob has been approved to spend.
                       Decrease the totalSuppy of tokens.
                       Publish a Burn event.

        Suppose Bob wants to burn 3 of the tokens that he may spend
        from Alice's account.

        Hardhat:
        await token.connect(Bob).burnFrom(aliceAddr,'3000000000000000000');
     */

    function burnFrom(address _from, uint256 _value) public returns (bool success) {
        require(balanceOf[_from] >= _value);
        require(_value <= allowance[_from][msg.sender]);
        balanceOf[_from] -= _value;
        allowance[_from][msg.sender] -= _value;
        totalSupply -= _value;
        emit Burn(_from, _value);
        return true;
    }

}



// MyAdvancedToken inherits from owned and TokenERC20

contract MyAdvancedToken is owned, TokenERC20 {

    // This contract will buy and sell tokens at these prices
    uint256 public sellPrice;
    uint256 public buyPrice;

    /* In Hardhat we can view these prices:
        sellPrice = await token.connect(Bob).sellPrice();
    */



    // We can freeze and unfreeze accounts
    mapping (address => bool) public frozenAccount;

    /* Suppose we want to view the mapping. Is Donna frozen?
    val = await token.frozenAccount(donnaAddr);

    */


    /* The function freezeAccounts publishes an event on the blockchain
       that will notify clients of frozen accounts.
    */

    event FrozenFunds(address target, bool frozen);


    // This is a public constructor.
    // It initializes the contract with an initial supply of tokens
    // and assigns those tokens to the deployer of the contract.
    // It also assigns a name and a symbol.
    // This constructor calls the parent constructor (TokenERC20).
    // It does nothing else after the call to the TokenERC20 constructor.

    constructor(
        uint256 initialSupply,
        string memory tokenName,
        string memory tokenSymbol
    ) TokenERC20(initialSupply, tokenName, tokenSymbol) public {}

    /* This is an internal function. It can only be called by this contract.
       It does not use an implied sender. It simply transfers tokens from
       one account to another and both accounts are supplied as arguments.

       Preconditions: The recipient may not be the zero address. Use burn instead.
                      The source must have sufficient funds.
                      No overflow is permited.
                      Neither account may be frozen.

       Postconditions: Tokens are transferred.
                       An event is published.
    */

    function _transfer(address _from, address _to, uint _value) internal {
        require (_to != address(0x0));
        require (balanceOf[_from] >= _value);
        require (balanceOf[_to] + _value >= balanceOf[_to]);
        require(!frozenAccount[_from]);
        require(!frozenAccount[_to]);

        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
        emit Transfer(_from, _to, _value);
    }


    // This function is public but may only be called by the owner
    // of the contract.
    // It adds tokens to the supplied address.

    /* Suppose Alice wants to add 5 tokens to Bob's account.

       In Hardhat:

       c = await token.mintToken(bobAddr,'5000000000000000000');

       And, she want to view the transfer events:
       const mint_receipt = await c.wait()
       console.log(mint_receipt.logs)


    */

    function mintToken(address target, uint256 mintedAmount) onlyOwner public {

        balanceOf[target] += mintedAmount;
        totalSupply += mintedAmount;

        emit Transfer(address(0), address(this), mintedAmount);
        emit Transfer(address(this), target, mintedAmount);
    }

    // This function is public but may only be called by the owner
    // of the contract.
    // The owner may freeze or unfreeze the specified address.
    // Precondition: Only the owner may call.
    // Postcondition: The specified account is frozen or unfrozen.
    //                A FrozenFunds event is published.

    /* Suppose Alice wants to freeze the account of Donna.
       In Hardhat:
       val = await token.freezeAccount(donnaAddr,true);

    */

    function freezeAccount(address target, bool freeze) onlyOwner public {
        frozenAccount[target] = freeze;
        emit FrozenFunds(target, freeze);
    }


    // This function is public but may only be called by the owner
    // of the contract.
    // It allows the owner to set a sell price and a buy price in eth.

    /* Suppose Alice wants to set the sell price at 1 eth and the buy price at 2 eth.
       In Hardhat:
        tx = await token.setPrices('1','2');
        receipt = await tx.wait();
    */

    function setPrices(uint256 newSellPrice, uint256 newBuyPrice) onlyOwner public {
        sellPrice = newSellPrice;
        buyPrice = newBuyPrice;
    }



    // Function buy is public and since it is 'payable' it may be passed ether.
    // The idea is to send ether to the contract's ether account in
    // exchange for tokens going into the sender's token account.
    // The contract will need to have some tokens in its token account
    // before any buys can succeed.
    // The ether account (the contract's balance) is maintained by
    // Ethereum and is not the same as the contract's token account.
    // The buyPrice is expressed in ether and was established by the owner.
    // The buyer sends along a value that is expressed in wei.
    // If Donna has eth and wants tokens, she will call buy and pay the buy price in eth.
    // The contract needs tokens to sell. So, lets assume that prior
    // to a buy call by Charlie, Alice performed the following two steps.
    // First, she assigns the variable 'contract' to the address
    // of the contract.
    // contractAddr = token.target;
    // Second, she might mint 5 tokens for the contract.
    // In Hardhat:
    // await token.mintToken(contractAddr,'5000000000000000000');

    // Precondition: The contract must have tokens in its token account.
    //               The caller must have an account with sufficient funds to
    //               cover the cost of gas and the cost of tokens.
    // Postcondition: Tokens are transferred to the caller's token account.
    //                Ether is placed into the contract's Ether account.
    //                Miners take some ether based on gas used and the
    //                price of gas.
    //                A transfer event is published.
    //

    /* Suppose Charlie would like to buy 2 ether worth of tokens from the
     * contract. Suppose the buy price is 4 eth per token.
     * In Hardhat:
     * await token.connect(Charlie).buy({ value: ethers.parseEther("2.0") });
     *
     * The function will compute amount = 2000000000000000000 / 4 producing the
     * correct amount in the correct format. 2000000000000000000 / 4 = 500000000000000000.
    */

    function buy() payable public {
        uint amount = msg.value / buyPrice;
        _transfer(address(this), msg.sender, amount);
    }

    // Called when eth is transferred from MetaMask.
    function() external payable {
        buy();
    }

    // This is a public function but does not take in ether.
    // It is not marked as 'payable'. There needs to be ether
    // in the contract's account for it to be able to buy these
    // tokens from the caller.
    // If Donna has tokens and wants eth, she will call sell and, in return for her tokens, receive eth
    // at the sell price.
    // Suppose the caller wants to sell 1 token and the sell price is 2 eth per token.
    // The token's ether balance must be >= 1 * 2 = 2.
    // How do we check the contract's ether balance?
    //
    // In Hardhat:
    // const contractBalance = await ethers.provider.getBalance(contractAddr);
    // contractBalance.toString()
    //
    // Precondition:  The contract has enough ether to buy these tokens
    //                at the sell price.
    // Postconditions:The tokens are added to the contract's account.
    //                Tokens are deducted from sender's account.
    //                Ether is transferred from contract's ether account
    //                to sender's ether account.
    //
    function sell(uint256 amount) public {
        address myAddress = address(this);
        require(myAddress.balance >= amount * sellPrice);
        _transfer(msg.sender, address(this), amount);

        // It's important to do this transfer last to avoid recursion attacks.
        msg.sender.transfer(amount * sellPrice);
    }
}
