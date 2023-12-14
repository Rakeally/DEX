// SPDX-License-Identifier: GPL-3.0

pragma solidity =0.8.20;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract JKToken is ERC20 {
    constructor(uint initialSupply) ERC20("janeToken", "JKT") {
        _mint(msg.sender, initialSupply * 10 ** uint(decimals()));
    }

    function transfer(
        address _sender,
        address _recipient,
        uint _amount
    ) public returns (bool) {
        _transfer(_sender, _recipient, _amount);
        return true;
    }
}
