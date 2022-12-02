// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts@4.8.0/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts@4.8.0/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts@4.8.0/security/Pausable.sol";
import "@openzeppelin/contracts@4.8.0/access/Ownable.sol";

/// @custom:security-contact metauserdao@outlook.com
contract MetaUserDAOToken is ERC20, ERC20Burnable, Pausable, Ownable {

    address immutable private creator;

    constructor() ERC20("MetaUserDAO", "MUD") {
        _frozen = false;
        creator = msg.sender;

        _mint(msg.sender, 1000000000 * (10 ** uint256(decimals())));
    }

    //freeze the token tranfer and get ready for main net mapping
    function mainNetMappingFreeze() external {
        require(msg.sender == creator, "Not token creator!");
        require(!_frozen, "Freezed for mainnet mapping !");
        
        _frozen = true;
    }

    function decimals() override public pure returns (uint8)  {
        return 6;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        whenNotPaused
        override
    {
        super._beforeTokenTransfer(from, to, amount);
    }
}
