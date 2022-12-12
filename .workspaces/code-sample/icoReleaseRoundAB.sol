// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;


import "@openzeppelin/contracts@4.8.0/token/ERC20/ERC20.sol";
import "./Token.sol";
import "./UtilityFunctions.sol";


contract MudABRoundReleaseBank {
     
    address immutable admin; //contract creator
    uint256 constant ABRoundLimit = 3e14;//300000000000000;//rouna A and B total limit 250000000 MUD
    uint256 constant dailyRate = 92590; //0.0009259 daily release rate 0.09259%
    uint constant secPerDay = 86400;
    uint256 private _icoDepositTotal;
    bool private _icoFinished;
    MetaUserDAOToken token;

    event icodeposit(address indexed investorAddress, uint256 amount, uint256 balance);
    event releasetoken(uint256 freeAmount, uint256 balance);
                                               
    struct Transaction {
        bool locked;
        uint lastTime;
        uint256 balance;
        uint256 dailyReleaseAmount;
    }
    
    mapping(address => Transaction) bank;   
   
    constructor() {
        admin = msg.sender;//set contract owner, which is the MetaUserDAO team administrator account with multisig transaction setup.

        token = UtilityFunctions.getMudToken();//MudTestToken(mudtTokenContractAddr);
    }
    
    
    /*only the contractor creator could deposit ico to investor
    * lock the ico coins to the angelround daily release contract 
    * parameters:
    *     investorAddress: AB round investor address 
    *     amount: amount of MUD coin received from AB round 
    * return:  total coins deposited in the contract    
    */
    function icoDeposit(address investorAddress, uint256 amount) external returns (uint256) {
        require(msg.sender == admin, "Only admin can deposit.");
        require(!_icoFinished, "ICO finished!");
        require(bank[investorAddress].balance == 0, "balance is not 0.");
        require(amount > 0, "amount should > 0");
        address contractorAddr = address(this);
        require(amount + _icoDepositTotal <= ABRoundLimit, "amount overflow!");
        require(!bank[investorAddress].locked, "already locked.");
         
        bank[investorAddress].lastTime = block.timestamp;
        bank[investorAddress].balance = amount;
        bank[investorAddress].dailyReleaseAmount = amount * dailyRate / 1e8; //amount * dailyRate / 100000000;
        bank[investorAddress].locked = true;
        _icoDepositTotal = _icoDepositTotal + amount;

        require(token.transferFrom(msg.sender, contractorAddr, amount), "transferFrom faied!"); //check the return value, it should be true
       
        emit icodeposit(investorAddress, amount, _icoDepositTotal);
        return _icoDepositTotal;
    }
    
    /* investor call this function from the dapp to check the amount of their coins in the AB round locked contract
     * parameters: adressIn: for admin account it can be any investor address, for investor the adressIn is not used
     * returns: 
     *         (free MUD coins ready for withdraw, total MUD coins of the investor in the contract)
     */
    function checkBalance(address addressIn) external view returns  (uint256 , uint256 ) {
        require(addressIn != address(0), "Blackhole address not allowed!");
        
        address addressToCheck = msg.sender;
        
        if (msg.sender == admin) {
            addressToCheck = addressIn;
        }

        require(block.timestamp > bank[addressToCheck].lastTime, "now time < lastTime");
        
        if (bank[addressToCheck].balance <= 0) {
            return (0, 0);
        }
        
        //The freeAmount should be matured based on exact times of the 24 hours.
        //Thus we should calculate the matured days. The leftover time which is not a whole 24 hours
        //should wait for the next mature time spot.
        uint256 maturedDays = (block.timestamp - bank[addressToCheck].lastTime) / secPerDay;
        uint256 freeAmount = bank[addressToCheck].dailyReleaseAmount * maturedDays;//even 0 matured days will work
        
        if (freeAmount > bank[addressToCheck].balance) {
            freeAmount = bank[addressToCheck].balance;
        }

        return (freeAmount, bank[addressToCheck].balance);
    }
    
     /* release the free tokens to the investor's wallet address
     * parameters: NONE 
     * returns:  (released amount, amount still locked in the contract)
     */
    function releaseToken() external returns  (uint256, uint256) {
        require(msg.sender != admin, "msg.send == admin");
        require(bank[msg.sender].balance > 0, "balance <= 0");
        require(block.timestamp > bank[msg.sender].lastTime + secPerDay, "now < lastTime + secPerDay");
        
        //The freeAmount should be matured based on exact times of the 24 hours.
        //Thus we should calculate the matured days. The leftover time which is not a whole 24 hours
        //should wait for the next mature time spot.
        uint256 maturedDays = (block.timestamp - bank[msg.sender].lastTime) / secPerDay;
        uint256 freeAmount = bank[msg.sender].dailyReleaseAmount * maturedDays;
        
        if (freeAmount > bank[msg.sender].balance) {
            freeAmount = bank[msg.sender].balance;
        }
        
        bank[msg.sender].lastTime = bank[msg.sender].lastTime + maturedDays * secPerDay;//should set to the exact spot based on 24 hours
        bank[msg.sender].balance = bank[msg.sender].balance - freeAmount;
        require(token.transfer(msg.sender, freeAmount), "token transfer failed !");

        emit releasetoken(freeAmount, bank[msg.sender].balance);        
        return (freeAmount, bank[msg.sender].balance);
    }
    
    //mark the ICO finished flag, stop icoDeposit any more and return the icoDepositTotal.
    //The leftover amount will be bunt by team admininstrators by owner account with multisig setup.
    function icoFinalised() external returns (uint256) {
        require(msg.sender == admin, "Not contractor owner!");
        require(!_icoFinished, "ICO finished already!");
        
        _icoFinished = true;
        return _icoDepositTotal;
    }
}
