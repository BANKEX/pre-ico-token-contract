//
// A contract for selling pre-sale tokens
//
// Supports the "standardized token API" as described in https://github.com/ethereum/wiki/wiki/Standardized_Contract_APIs
//
// To approve an escrow request call the approve() method
//
// The recipient can make a simple Ether transfer to get the tokens released to his address.
//
// The buyer pays all the fees (including gas).
//

pragma solidity ^0.4.0;

import "github.com/oraclize/ethereum-api/oraclizeAPI.sol";

/**
 * @title Interface to communicate with ICO token contract
 */
contract IToken {
  function balanceOf(address _address) constant returns (uint balance);
  function transferFromOwner(address _to, uint256 _value) returns (bool success);
}

/**
 * @title Presale token contract
 */
contract TokenEscrow is usingOraclize {
	// Token-related properties/description to display in Wallet client / UI
	string public standard = 'PBKXToken 0.3';
	string public name = 'PBKXToken';
	string public symbol = 'PBKX';
	
	event Burn(address indexed from, uint256 value); // Event to inform about the fact of token burning/destroying
	event newOraclizeQuery(string description); // Oraclize-related notifications
	
	mapping (address => uint) balanceFor; // Presale token balance for each of holders
	address[] addressByIndex; // Array to keep track of keys/addresses which contain Presale tokens
	
	address owner;  // Contract owner
	
	uint public ETH_TO_USD_CENT_EXCHANGE_RATE; // Ether -> USD cents exchange rate

	// Token supply and discount policy structure
	struct TokenSupply {
		uint limit;                 // Total amount of tokens
		uint totalSupply;           // Current amount of sold tokens
		uint priceInCentsPerToken;  // Price per token
	}
	
	TokenSupply[3] public tokenSupplies;

	// Modifiers
	modifier owneronly { if (msg.sender == owner) _; }

	/**
	 * @dev Set/change contract owner
	 * @param _owner owner address
	 */
	function setOwner(address _owner) owneronly {
		owner = _owner;
	}
	
	/**
	 * @dev Returns balance/token quanity owned by address
	 * @param _address Account address to get balance for
	 * @return balance value / token quantity
	 */
	function balanceOf(address _address) constant returns (uint balance) {
		return balanceFor[_address];
	}
	
	/**
	 * @dev Converts/exchanges sold Presale tokens to ICO ones according to provided exchange rate
	 * @param _icoToken ICO token contract address
	 * @param exchangeRate Exchange rate of conversion. For example exchangeRate = 2 stands for converting N Presale tokens for N * 2 ICO tokens 
	 */
	function exchangeToIco(address _icoToken, uint exchangeRate) owneronly {
		IToken icoToken = IToken(_icoToken);
		for (uint ai = 0; ai < addressByIndex.length; ai++) {
			address currentAddress = addressByIndex[ai];
			icoToken.transferFromOwner(currentAddress, balanceFor[currentAddress] * exchangeRate);
			balanceFor[currentAddress] = 0;
		}
	}
	
	/**
	 * @dev Transfers tokens from caller/method invoker/message sender to specified recipient
	 * @param _to Recipient address
	 * @param _value Token quantity to transfer
	 * @return success/failure of transfer
	 */	
	function transfer(address _to, uint _value) returns (bool success) {
		if (balanceFor[msg.sender] < _value) throw;           // Check if the sender has enough
		if (balanceFor[_to] + _value < balanceFor[_to]) throw; // Check for overflows
		balanceFor[msg.sender] -= _value;                     // Subtract from the sender
		if (balanceFor[_to] == 0) {
			addressByIndex.length++;
			addressByIndex[addressByIndex.length-1] = _to;
		}
		balanceFor[_to] += _value;                            // Add the same to the recipient
		return true;
	}
	
	/**
	 * @dev Burns/destroys specified amount of Presale tokens for caller/method invoker/message sender
	 * @param _value Token quantity to burn/destroy
	 * @return success/failure of transfer
	 */	
	function burn(uint256 _value) returns (bool success) {
		if (balanceFor[msg.sender] < _value) throw;            // Check if the sender has enough
		balanceFor[msg.sender] -= _value;                      // Subtract from the sender
		Burn(msg.sender, _value);
		return true;
	}  

	/**
	 * @dev Presale contract constructor
	 */
	function TokenEscrow() {
		owner = msg.sender;
		
		balanceFor[msg.sender] = 3000000; // Give the creator all initial tokens
		
		// Discount policy
		tokenSupplies[0] = TokenSupply(1000000, 0, 28); // First million of tokens will go for price of 20 cents each
		tokenSupplies[1] = TokenSupply(1000000, 0, 30); // Second million of tokens will go for price of 30 cents each
		tokenSupplies[2] = TokenSupply(1000000, 0, 33); // Third million of tokens will go for price of 33 cents each
		
		// Enable oraclize_setProof is production
		oraclize_setProof(proofType_TLSNotary | proofStorage_IPFS);
		// Kickoff obtaining of ETH -> USD exchange rate
		update(0);
	}

	/**
	 * @dev Allows to transfer ether to contract's account for Oraclize consumption
	 */
	function payMoneyForOraclize() payable {
		// Cause anonymous function below is used for token sale
	}
  
	// Incoming transfer from the Presale token buyer
	function() payable {
		// Do not allow payments until first exchange rate is get known
		if (ETH_TO_USD_CENT_EXCHANGE_RATE == 0)
			throw;
		
		uint tokenAmount = 0; // Amount of tokens which is possible to buy for incoming transfer/payment
		uint amountOfCentsToBePaid = 0; // Total cost/price of tokens which is possible to buy for incoming transfer/payment
		uint amountOfCentsTransfered = msg.value * ETH_TO_USD_CENT_EXCHANGE_RATE / 1 ether; // Cost/price in USD cents of incoming transfer/payment
		
		// Determine amount of tokens can be bought according to available supply and discount policy
		for (uint discountIndex = 0; discountIndex < tokenSupplies.length; discountIndex++) {
			// If it's not possible to buy any tokens at all skip the rest of discount policy
			if (amountOfCentsTransfered <= 0) {
			  break;
			}
			
			TokenSupply tokenSupply = tokenSupplies[discountIndex];
			
			uint moneyForTokensPossibleToBuy = min((tokenSupply.limit - tokenSupply.totalSupply) * tokenSupply.priceInCentsPerToken,  amountOfCentsTransfered);
			uint tokensPossibleToBuy = min(moneyForTokensPossibleToBuy / tokenSupply.priceInCentsPerToken, balanceFor[owner] - tokenAmount);
			
			tokenSupply.totalSupply += tokensPossibleToBuy;
			tokenAmount += tokensPossibleToBuy;
			
			uint delta = tokensPossibleToBuy * tokenSupply.priceInCentsPerToken;
			
			amountOfCentsToBePaid += delta;
			amountOfCentsTransfered -= delta;
		}
		
		// Do not waste gas if there is no tokens to buy
		if (tokenAmount == 0)
			throw;
		
		// Transfer tokens to buyer
		transferFromOwner(msg.sender, tokenAmount);
		
		// Convert total cost/price of tokens which is possible to buy for incoming transfer/payment back to ether
		uint amountOfEthToBePaid = amountOfCentsToBePaid * 1 ether / ETH_TO_USD_CENT_EXCHANGE_RATE;
		
		// Transfer money to seller
		owner.transfer(amountOfEthToBePaid);
		
		// Refund buyer if overpaid / no tokens to sell
		msg.sender.transfer(msg.value - amountOfEthToBePaid);
	}
  
	  /**
	 * @dev Oraclize's callback for parsing/processing response which contains ETH -> USD exchange rate
	 * @param myid Unique identifier of corresponding request
	 * @param result Response payload excerpt
	 * @param proof TLSNotary proof
	 */	
	function __callback(bytes32 myid, string result, bytes proof) {
		if (msg.sender != oraclize_cbAddress()) throw;
		
		ETH_TO_USD_CENT_EXCHANGE_RATE = parseInt(result, 2); // save it in storage as $ cents
		update(60 * 60); // Enable recursive price updates once in every hour
	}

	/**
	 * @dev Send request of getting ETH -> USD exchange rate to Oraclize
	 * @param delay Delay (in seconds) when the next request will happen
	 */	
	function update(uint delay) payable {
		if (oraclize_getPrice("URL") > this.balance) {
			newOraclizeQuery("Oraclize query was NOT sent, please add some ETH to cover for the query fee");
		} else {
			newOraclizeQuery("Oraclize query was sent, standing by for the answer..");
			oraclize_query(delay, "URL", "json(https://api.kraken.com/0/public/Ticker?pair=ETHUSD).result.XETHZUSD.c.0");
		}
	}

	/**
	 * @dev Removes/deletes contract
	 */
	function kill() owneronly {
		suicide(msg.sender);
	}
  
	/**
	 * @dev Transfers tokens from owner to specified recipient
	 * @param _to Recipient address
	 * @param _value Token quantity to transfer
	 * @return success/failure of transfer
	 */
	function transferFromOwner(address _to, uint256 _value) private returns (bool success) {
		if (balanceFor[owner] < _value) throw;                 // Check if the owner has enough
		if (balanceFor[_to] + _value < balanceFor[_to]) throw;  // Check for overflows
		balanceFor[owner] -= _value;                          // Subtract from the owner
		if (balanceFor[_to] == 0) {
			addressByIndex.length++;
			addressByIndex[addressByIndex.length-1] = _to;
		}
		balanceFor[_to] += _value;                            // Add the same to the recipient
		return true;
	}
  
	/**
	 * @dev Find minimal value among two values/parameters
	 * @param a First value
	 * @param b Second value
	 * @return Minimal value
	 */
	function min(uint a, uint b) private returns (uint) {
		if (a < b) return a;
		else return b;
	}
}