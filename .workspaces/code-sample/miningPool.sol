// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;


//import "@openzeppelin/contracts@4.8.0/token/ERC20/ERC20.sol";
//import "./Token.sol";
import "./UtilityFunctions.sol";


contract MudMiningPool {
    
    //mining DAPP address should be set at the contract deployment time to the correct one
    //this is the address that MUD Mining DAPP used to interact with the daily settlement function
    address constant miningDappAddress = address(0x2cf83d6aEE1eA8cF5b1263Ac0Bf2797376331CA9);   
    uint constant secPerDay = 86400;

    MetaUserDAOToken token;
    address immutable admin;
    uint lastHalvingTime;
    uint lastSettlementTime;
    uint256 dailyMiningLimit;
    uint256 settlementPeriod = 7; //7 days
    bool icoDepositDone; //default value is false
    
    uint256 _currentSettlementTimestamp;
    uint256 _totalSettlementAmount;    
    uint256 private _totalFreeAmount;
    mapping (address => uint256) private _minedToken;
    
    event icodeposit(uint256 amount, uint256 balance);
    event miningstart(uint lastHalvingTime);
    event settlementEvt(uint256 batchNumber, uint256 burntAmount, uint256 minedAmount, uint256 totalfreeamount);
    event withdrawevt(uint256 amount);

    constructor() {
        admin = address(msg.sender);
        token = UtilityFunctions.getMudToken();
        dailyMiningLimit = 100354078820; //100354.078820 MUD per day
    }
    
    function icoDeposit(uint256 amount) external returns (uint256) {
        require(msg.sender == admin, "only admin allowed!");
        require(amount == 4.5e14, "Invalid amount !"); //450000000000000. should be 45% of total coins, 450000000 MUD
        require(!icoDepositDone, "Only deposit once !");//only deposit once after ICO
        
        icoDepositDone = true;
        require(token.transferFrom(msg.sender, address(this), amount), "token transfer failed !");
        emit icodeposit(amount, token.balanceOf(address(this)));

        return token.balanceOf(address(this));
    }
    
    function miningStart() external returns (uint) {
        require(msg.sender == miningDappAddress, "only dapp admin allowed!"); //only dapp address could start miningDappAddress
        require(lastHalvingTime == 0, "only start once!");
        
        lastHalvingTime = block.timestamp;
        lastSettlementTime = block.timestamp; //mining start time should be the last settlement time
        emit miningstart(lastHalvingTime);
        return lastHalvingTime;
    }
    
    /*
        Due to the max gas limit of one block, the settlement should seperated to several batches.
        Parameters:
                 batchNumber: start from 1, for the last batch the batchNumber must be 0
                 settlementTime: should be the same each day based on miningStart() block time
                 addressArray: addresses for settlement
                 balanceArray: amount to be settled
        Return:
                for the last batch:
                  emit settlementEvt(batchNumber, amountToBurn, _totalSettlementAmount, _totalFreeAmount); 
                for other batch:
                  emit settlementEvt(batchNumber, 0, _totalSettlementAmount, _totalFreeAmount);
                  
    */

    function miningSettlement(uint256 batchNumber, uint settlementTime, address[] calldata addressArray, uint256[] calldata balanceArray) external {
        require(msg.sender == miningDappAddress, "only dapp admin allowed!");
        require(lastHalvingTime > 0, "mining not started !");
        require(addressArray.length == balanceArray.length, "Array length not match");
        require(settlementTime == lastSettlementTime + secPerDay * settlementPeriod, "Settlement time not match !");
        require(settlementTime <= block.timestamp, "settlementTime should <= block time!");
                
        //only update the timestamp once we got the last batch
        if (batchNumber == 1) {
            require(_currentSettlementTimestamp == 0, "Could not start a new settlement before last one has accomplished !");
            _currentSettlementTimestamp = settlementTime;
        } else if (batchNumber == 0) {      
                //batchNum 0 could be both first and last batch, thus donot check the timestamp     
                if (_currentSettlementTimestamp == 0){
                    _currentSettlementTimestamp = settlementTime;
                } else {
                    //all the following settlements batch should have the same time stamp as the first one
                    require(settlementTime == _currentSettlementTimestamp, "Settlement time not match !");
                }

                lastSettlementTime = settlementTime;
            
                //update mining halving dailyMiningLimit every 4 years
                if (block.timestamp > lastHalvingTime + 126144000) {
                    dailyMiningLimit = dailyMiningLimit / 2;
                    lastHalvingTime = block.timestamp;
                }             
        } else {
            //all the following settlements batch should have the same time stamp as the first one
            require(settlementTime == _currentSettlementTimestamp, "Settlement time not match !");
        }

        uint256 settlementLimit = dailyMiningLimit * settlementPeriod;
        //iterate through the array and update
        for (uint i = 0; i < addressArray.length; i++) {
            require(addressArray[i] != admin && addressArray[i] != address(0), "invalid address");
            require(balanceArray[i] > 0);
        
            _totalSettlementAmount = _totalSettlementAmount + balanceArray[i];
            
            require(_totalSettlementAmount <= settlementLimit, "TotalAmount out of settlement limit!"); // > daily limit, trasaction failed.
            
            _minedToken[addressArray[i]] = _minedToken[addressArray[i]] + balanceArray[i];
        }
        
        //batchNumber == 0 is the last batch of settlement
        if (batchNumber == 0) {
            _totalFreeAmount = _totalFreeAmount + _totalSettlementAmount;
            
            require(_totalFreeAmount <= token.balanceOf(address(this)), "Not enough tokens available !");
            
            //burn token from the pool with 2:1 ratio of totalAmount:burntAmount
            uint256 amountToBurn = _totalSettlementAmount / 2 + (settlementLimit - _totalSettlementAmount);
            uint256 leftover = token.balanceOf(address(this)) - _totalFreeAmount;

            if (leftover < amountToBurn) {
                amountToBurn = leftover; 
            }

            if (amountToBurn > 0) { //only burn if the amountToBurn > 0
                require(token.increaseAllowance(address(this), amountToBurn), "increaseAllowance failed!");
                token.burnFrom(address(this), amountToBurn);
            }

            emit settlementEvt(batchNumber, amountToBurn, _totalSettlementAmount, _totalFreeAmount); 
            _totalSettlementAmount = 0; //clear for next settlement.
            _currentSettlementTimestamp = 0; //clear time stamp
                      
        } else {
            emit settlementEvt(batchNumber, 0, _totalSettlementAmount, _totalFreeAmount); 
        }               
    }

    function checkBalance() external view returns (uint256) {
        require(msg.sender != admin && msg.sender != miningDappAddress,"admin and dapp acc not allowed!");
        require(lastHalvingTime > 0, "mining not started !");
        
        return _minedToken[msg.sender];
    }
    
    //only the customers can withdraw from wallet
    //withdraw() is banned during settlement period
    function withdraw() external returns (uint256) {
        require(msg.sender != admin && msg.sender != miningDappAddress,"admin and dapp acc not allowed!");
        require(lastHalvingTime > 0, "mining not started !");
        require(_minedToken[msg.sender] > 0, "No token available !");
        require(_currentSettlementTimestamp == 0, "Withdraw banned in settlement period!");
        
        uint256 amount = _minedToken[msg.sender];
        _minedToken[msg.sender] = 0; 
        _totalFreeAmount = _totalFreeAmount - amount;
        require(token.transfer(msg.sender, amount), "Token transfer failed !");
        
        emit withdrawevt(amount);
        return amount;
    }
}