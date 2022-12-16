// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "./Token_flat.sol";

library UtilityFunctions {

    address constant mudtTokenContractAddr = address(0x6624Be5Cb052620DA417509Dec120E1BABbB7A87);//contrct address of the MUD token, should deploy the token contract first and set the contract address here
    
    function getMudToken() internal pure returns(MetaUserDAOToken){
        MetaUserDAOToken token = MetaUserDAOToken(mudtTokenContractAddr);
        
        return token;
    }
}