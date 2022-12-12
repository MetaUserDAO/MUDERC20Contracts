// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;


import "@openzeppelin/contracts@4.8.0/token/ERC20/ERC20.sol";
import "./Token.sol";
import "./UtilityFunctions.sol";

contract MudMiningEscrow {

     uint constant secPerMonth = 2592000;
     struct Transaction {
        uint startTime;
        uint endTime;
        uint256 amount;
     }
     
     struct Cursor {
         uint256 start;
         uint256 end;
     }

    mapping (address => mapping (uint256 => Transaction)) private _logbook;
    mapping (address => Cursor) private _cursors;
        
    MetaUserDAOToken token;
    address immutable admin;

    event depositEvt(uint256 depositId);
    event breakContractEvt(uint256 burnAmount, uint256 amountLeft);
    event withdrawEvt(uint256 freeAmount, uint256 lockedAmount);
    
    constructor()  {
        admin = address(msg.sender);
        token = UtilityFunctions.getMudToken();
    }
    

    function deposit(uint256 amount, uint8 duration) external returns (uint256) {
        require(msg.sender != admin, "Not admin !");
        require(duration == 3 || duration == 6 || duration == 12, "Only 3,6,9 allowed !");
        require(amount > 0, "amount should > 0 !");
        
        if (_cursors[msg.sender].start == 0) {
            _cursors[msg.sender].start = 1;
            _cursors[msg.sender].end = 1;
        } else {
            _cursors[msg.sender].end = ++_cursors[msg.sender].end;
        }
        
        uint256 end = _cursors[msg.sender].end;
        
        //_logbook[msg.sender][end].duration = duration;
        _logbook[msg.sender][end].startTime = block.timestamp;
        _logbook[msg.sender][end].endTime = block.timestamp + secPerMonth * duration;
        _logbook[msg.sender][end].amount = amount;
        
        require(token.transferFrom(msg.sender, address(this), amount), "Token transferFrom failed !");
        
        //emit deposit id
        emit depositEvt(end);
        return end;
    }
    
    function breakContract(uint256 contractId) external returns(uint256, uint256) {
        require(msg.sender != admin, "Not admin !");
        require(contractId > 0, "contractId should > 0 !");
        require(contractId >= _cursors[msg.sender].start && contractId <= _cursors[msg.sender].end, "Invalid contractId!");
        require(_logbook[msg.sender][contractId].amount > 0, "No token in contract !");
        require(block.timestamp > _logbook[msg.sender][contractId].startTime, "time should > contract startTime");
        
        if (block.timestamp > _logbook[msg.sender][contractId].endTime) {
            emit breakContractEvt(0, _logbook[msg.sender][contractId].amount);
            return (0, _logbook[msg.sender][contractId].amount); //0 burnt, all amount free for withdraw
        } else if (block.timestamp + 86400 >= _logbook[msg.sender][contractId].endTime) { //the contract will end sooner than 24 hours so no need to break earlier. burnAmount == contract amount means no break needed
            emit breakContractEvt(_logbook[msg.sender][contractId].amount, _logbook[msg.sender][contractId].amount);
            return (_logbook[msg.sender][contractId].amount, _logbook[msg.sender][contractId].amount); //all amount still waiting for mature within 24 hrs        
        } else { //if (now + 86400 < _logbook[msg.sender][contractId].endTime), burn 20% tokens immediately and end the contract after 24 hours from now before the end time
            //burn 20%
            uint256 burnAmount = _logbook[msg.sender][contractId].amount / 5;
            _logbook[msg.sender][contractId].amount = _logbook[msg.sender][contractId].amount - burnAmount;
            _logbook[msg.sender][contractId].endTime = block.timestamp + 86400; //86400

            require(token.increaseAllowance(address(this), burnAmount), "increaseAllowance failed!");
            token.burnFrom(address(this), burnAmount);

            emit breakContractEvt(burnAmount, _logbook[msg.sender][contractId].amount);   
            return (burnAmount, _logbook[msg.sender][contractId].amount);
        }
    }
    
    
    function checkBalance(address addressIn) external view returns (uint256, uint256) {
        require(addressIn != address(0), "Blackhole address not allowed!");
        
        address addressToCheck = msg.sender;
        
        if (msg.sender == admin) {
            addressToCheck = addressIn;
        }
        
        require(_cursors[addressToCheck].start <= _cursors[addressToCheck].end, "Nothing in the mining logbook!");

        if (_cursors[addressToCheck].start == 0) {
            return (0, 0);
        }
        
        uint256 freeAmount = 0;
        uint256 lockedAmount = 0;
        
        for (uint256 i = _cursors[addressToCheck].start; i <= _cursors[addressToCheck].end; i++) {
            if (_logbook[addressToCheck][i].amount > 0) {
                if (block.timestamp >= _logbook[addressToCheck][i].startTime) {
                    if (block.timestamp <= _logbook[addressToCheck][i].endTime) {
                        lockedAmount = lockedAmount + _logbook[addressToCheck][i].amount;
                    } else {
                        freeAmount = freeAmount + _logbook[addressToCheck][i].amount;
                    }
                }
            }//of amount > 0
        }
        
        return (freeAmount, lockedAmount);
    }
    
    function Withdraw() external returns (uint256, uint256) {
        require(msg.sender != admin, "Not admin !");
        require(_cursors[msg.sender].start > 0, "No mining contracts.");
        require(_cursors[msg.sender].start <= _cursors[msg.sender].end, "Invalid mining start,end pointers!");
        
        uint256 freeAmount = 0;
        uint256 lockedAmount = 0;
        bool foundNextStart = false;
        
        for (uint256 i = _cursors[msg.sender].start; i <= _cursors[msg.sender].end; i++) {
            if (_logbook[msg.sender][i].amount > 0) {
                if (block.timestamp >= _logbook[msg.sender][i].startTime) {
                    if (block.timestamp <= _logbook[msg.sender][i].endTime) {
                        lockedAmount = lockedAmount + _logbook[msg.sender][i].amount;
                        
                        if (!foundNextStart) {
                            foundNextStart = true;
                            _cursors[msg.sender].start = i;
                        }
                    } else {
                        freeAmount = freeAmount + _logbook[msg.sender][i].amount;
                        _logbook[msg.sender][i].amount = 0;
                    }
                }
            }//of amount > 0
        }// of for
        
        if (!foundNextStart) {
            _cursors[msg.sender].start = _cursors[msg.sender].end;
        }
        
        if (freeAmount > 0) {
            require(token.transfer(msg.sender, freeAmount), "Token transfer failed !");           
        }
        
        emit withdrawEvt(freeAmount, lockedAmount);
        return (freeAmount, lockedAmount);
    }
   
}
