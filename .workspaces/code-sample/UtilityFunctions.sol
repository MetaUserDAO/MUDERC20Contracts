// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Token.sol";

library UtilityFunctions {

    address constant mudtTokenContractAddr = address(0x8535346D05AE12dEDBbe7ddaBc8Ad6531821a201);//contrct address of the MUD token, should deploy the token contract first and set the contract address here
    
    function getMudToken() internal pure returns(MetaUserDAOToken){
        MetaUserDAOToken token = MetaUserDAOToken(mudtTokenContractAddr);
        
        return token;
    }
}