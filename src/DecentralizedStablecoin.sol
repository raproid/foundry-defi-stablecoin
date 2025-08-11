// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

/*
* @title Decentralized Stablecoin
* @author Raproid
* Collateral: Exogenous (BTC and ETH)
* Minting: Algorithmic
* Relative Stability: pegged to USD
*
* This contract is meant to be governed by DSCEngine. This contract is just the ERC20 implementation of our stablecoin system.
*/

import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract DecentralizedStablecoin is ERC20Burnable, Ownable {
    /* ERRORS */
    error DecentralizedStablecoin__CannotBeZeroAddress();
    error DecentralizedStablecoin__BurnAmountExceedsBalance();
    error DecentralizedStablecoin__MustBeMoreThanZero();

    /* CONSTRUCTOR */
    constructor() ERC20("Decentralized Stablecoin", "DSC") Ownable(msg.sender){}

    /* PUBLIC FUNCTIONS */
    function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
        if(_to == address(0)) {
            revert DecentralizedStablecoin__CannotBeZeroAddress();
        }
        if( _amount <= 0 ) {
            revert DecentralizedStablecoin__MustBeMoreThanZero();
        }
        _mint(_to, _amount);
        return true;
    }

    function burn(uint256 _amount) public override onlyOwner {
        uint256 balance = balanceOf(msg.sender);
        if (_amount <= 0) {
            revert DecentralizedStablecoin__MustBeMoreThanZero();
        }
        if (balance < _amount) {
            revert DecentralizedStablecoin__BurnAmountExceedsBalance();
        }
        super.burn(_amount);
    }
}
