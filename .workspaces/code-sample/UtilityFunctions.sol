// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Token.sol";

library UtilityFunctions {

    address constant mudtTokenContractAddr = address(0x9DC7e4dC7F3F22A897D00DFe5B55f10C174019D5);//contrct address of the MUD token, should deploy the token contract first and set the contract address here
    
    function getMudToken() internal pure returns(MetaUserDAOToken){
        MetaUserDAOToken token = MetaUserDAOToken(mudtTokenContractAddr);
        
        return token;
    }
}