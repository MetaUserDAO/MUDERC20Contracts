// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;


import "@openzeppelin/contracts@4.8.0/token/ERC20/ERC20.sol";
import "./Token.sol";
import "./UtilityFunctions.sol";


contract MudMiningPool {
    
    //mining DAPP address should be set at the contract deployment time to the correct one
    //this is the address that MUD Mining DAPP used to interact with the daily settlement function
    address constant miningDappAddress = address(0x2cf83d6aEE1eA8cF5b1263Ac0Bf2797376331CA9);   
       
    MetaUserDAOToken token;
    address immutable admin;
    uint lastHalvingTime;
    uint lastDailySettlementTime;
    uint256 dailyMiningLimit;
    bool icoDepositDone; //default value is false
    
    uint256 private _totalFreeAmount;
    mapping (address => uint256) private _minedToken;
    
    event icodeposit(uint256 amount, uint256 balance);
    event miningstart(uint lastHalvingTime);
    event dailysettlement(address indexed dappaddr, uint256 burntAmount, uint256 minedAmount, uint256 totalfreeamount);

    constructor() {
        admin = address(msg.sender);
        token = UtilityFunctions.getMudToken();
        dailyMiningLimit = 104166660000; //104166.66 MUD per day
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
        
        emit miningstart(lastHalvingTime);
        return lastHalvingTime;
    }
    
    //dapp will call this once a day for settlement
    //settlement logic:
    //   The DAPP should trigger the call and set settlement time stamp exactly the same time each day.
    //   For the first time settlement, the lastDailySettlementTime is 0 and will be set to settlementTime,
    //   Because settlementTime is binded to within 1 hour prior to time now by the following validation,
    //       require(settlementTime <= now && settlementTime.add(3600) >= now, "Settment time expired!");
    //   the settlementTime is meaningful in reality and will be treated at the start point of the future settlement.
    //   For all the following dailySettlement calls, the settlement time will be the exact time each day based on
    //   the first successful settlement.
    //   In reality, the daily settlement could be failed due to various reasons like lack of transaction fees, tron
    //   mainnet congestion or downtime. Thus, the dapp has 1 hour to retry each day, which is validated by the 
    //      require(settlementTime <= now && settlementTime.add(3600) >= now, "Settment time expired!"); 
    //   If the dapp could not settle successfully witin 1 hour, it should combin the days together in next day with the
    //   same time stamp spot. That is the dailyMiningLimit will times the dayToSettle and the settlement balance should be
    //   the combined days as well.
    function dailySettlement(uint settlementTime, address[] calldata addressArray, uint256[] calldata balanceArray) external returns (uint256, uint256, uint256){
        require(msg.sender == miningDappAddress, "only dapp admin allowed!");
        require(lastHalvingTime > 0, "mining not started !");
        require(addressArray.length == balanceArray.length, "Array length not match");
        //settlementTime shoule be within 1 hour prior to time now    
        require(settlementTime <= block.timestamp && settlementTime + 3600 >= block.timestamp, "Settlement time expired!"); //86400
     
        uint256 daysToSettle;

        if (lastDailySettlementTime == 0) { //first time of dailySettlement()            
            daysToSettle = 1;
        } else { //after first settlement
            uint256 timeSpan = settlementTime - lastDailySettlementTime;

            require(timeSpan % 86400 == 0, "Settlement time should be the same every day!");
            daysToSettle = timeSpan / 86400;
            // daysToSettle == 0 means less than 24 hours
            // this check is useful if the dapp tries to settle again after the each successful settlement
            // and within 1 hours of the lastDailySettlementTime, cause the settlementTime could be set to
            // the same as lastDailySettlementTime. Thus the daysToSettle will be 0
            // After the 1 hour of the successful settlement, the settlementTime will bind to the 1 hour rule and 
            // the exact time spot of each day, this will be fine.
            require(daysToSettle > 0, "Only settle once per day");
        }    
                
        lastDailySettlementTime = settlementTime;
        
        //update mining halving dailyMiningLimit every 4 years
        if (block.timestamp > lastHalvingTime + 126144000) {
            dailyMiningLimit = dailyMiningLimit / 2;
            lastHalvingTime = block.timestamp;
        }
        
        //iterate through the array and update
        uint256 totalAmount; //default 0
        uint256 combinedDailyLimit = dailyMiningLimit * daysToSettle;

        for (uint i = 0; i < addressArray.length; i++) {
            require(balanceArray[i] > 0);
        
            totalAmount = totalAmount + balanceArray[i];
            
            require(totalAmount <= combinedDailyLimit, "TotalAmount out of daily limit!"); // > daily limit, trasaction failed.
            
            _minedToken[addressArray[i]] = _minedToken[addressArray[i]] + balanceArray[i];
        }
        
        _totalFreeAmount = _totalFreeAmount + totalAmount;
        
        require(_totalFreeAmount <= token.balanceOf(address(this)), "Not enough tokens available !");
        
        //burn token from the pool with 2:1 ratio of totalAmount:burntAmount
        uint256 amountToBurn = totalAmount / 2;
        uint256 leftover = token.balanceOf(address(this)) - _totalFreeAmount;

        if (leftover < amountToBurn) {
            amountToBurn = leftover; 
        }

        if (amountToBurn > 0) { //only burn if the amountToBurn > 0
            require(token.increaseAllowance(address(this), amountToBurn), "increaseAllowance failed!");
            token.burnFrom(address(this), amountToBurn);
        }

        emit dailysettlement(msg.sender, amountToBurn, totalAmount, _totalFreeAmount);
        return (amountToBurn, totalAmount, _totalFreeAmount);
    }

    function checkBalance() external view returns (uint256) {
        require(msg.sender != admin && msg.sender != miningDappAddress,"admin and dapp acc not allowed!");
        require(lastHalvingTime > 0, "mining not started !");
        
        return _minedToken[msg.sender];
    }
    
    //only the customers can withdraw from wallet
    function withdraw() external returns (uint256) {
        require(msg.sender != admin && msg.sender != miningDappAddress,"admin and dapp acc not allowed!");
        require(lastHalvingTime > 0, "mining not started !");
        require(_minedToken[msg.sender] > 0, "No token available !");
        
        uint256 amount = _minedToken[msg.sender];
        _minedToken[msg.sender] = 0; 
        _totalFreeAmount = _totalFreeAmount - amount;
        require(token.transfer(msg.sender, amount), "Token transfer failed !");
        
        return amount;
    }
}