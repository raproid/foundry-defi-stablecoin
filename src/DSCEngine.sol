// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DecentralizedStablecoin} from "./DecentralizedStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/*
* @title DSCEngine
* @author Raproid
*
* The system is designed to be as minimal as possible, and have the tokens maintain a 1 token = 1 USD peg.
*
* The stablecoin is:
* — Exogenous Collateralized
* — Algorithmically Stable
* — USD pegged
*
* It is similar to DAI if DAI had no governance, no fees, and was only backed by wBTC and wETH.
*
* The system should always be overcollateralized, and at no point should total_deposited_collateral_value be <= total_minted_dsc_value.
*
* @notice This contract is the core of the DSC System. It handles all the logic minting and redeeming DSC, as well as depositing and withdrawing collateral.
* @notice: This contract is loosely based on the MakerDAO DSS (DAI) system.
*/

contract DSCEngine is ReentrancyGuard{
    /* ERRORS */
    error DSCEngine__CollateralNotAllowed();
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__NotEnoughCollateral();
    error DSCEngine__NotEnoughDscMinted();
    error DSCEngine__NotEnoughDscBurned();
    error DSCEngine__NotEnoughCollateralToCoverDsc();
    error DSCEngine__TokenAddressesAndPriceFeedsMustBeEqualLength();

    /* STATE VARIABLES */
    mapping(address token => address priceFeed) private s_PriceFeeds;

    DecentralizedStablecoin private immutable i_dsc;

    /* EVENTS */
    event CollateralDeposited(address indexed user, address indexed collateral, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed collateral, uint256 amount);
    event DscMinted(address indexed user, uint256 amount);
    event DscBurned(address indexed user, uint256 amount);

    /* MODIFIERS */
    modifier moreThanZero(uint256 amount) {
        if (amount <= 0) {
           revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
        // This modifier would check if the token is allowed as collateral
        if (s_PriceFeeds[token] == address(0)) {
            revert DSCEngine__CollateralNotAllowed();
        }
        _;
    }

    /* FUNCTIONS */
    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address dscAddress) {
        if(tokenAddresses.length != priceFeedAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedsMustBeEqualLength();
        }
        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            s_PriceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
        }
        i_dsc = DecentralizedStablecoin(dscAddress);
    }

    /* EXTERNAL FUNCTIONS */
    function depositCollateralAndMintDsc() external {}

    /*
    * @param tokenCollateralAddress The address of the token to deposit as collateral.
    */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant{}

    function mintDsc() external {}

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    // Allows users to quickly burn some DSC and redeem part of their collateral so they can provide it back to the system to maintain their collateralization ratio and avoid being liquidated.
    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}


}