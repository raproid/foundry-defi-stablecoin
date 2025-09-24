// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DecentralizedStablecoin} from "./DecentralizedStablecoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

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
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;

    mapping(address token => address priceFeed) private s_PriceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_CollateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DscMinted;

    address[] private _collateralTokens;

    DecentralizedStablecoin private immutable i_dsc;

    /* EVENTS */
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed token, uint256 amount);
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
            s_collateralTokens.push(tokenAddresses[i]);
        }
        i_dsc = DecentralizedStablecoin(dscAddress);
    }

    /* EXTERNAL FUNCTIONS */
    function depositCollateralAndMintDsc() external {}

    /*
    * @notice follows CEI
    * @param tokenCollateralAddress The address of the token to deposit as collateral
    * @param amountCollateral The amount of collateral to deposit
    */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral) external moreThanZero(amountCollateral) isAllowedToken(tokenCollateralAddress) nonReentrant{
        s_CollateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);
        IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if(!success) {
            revert DSCEngine__NotEnoughCollateral();
        }
    }

    /*
    * @notice follows CEI
    * @param amountDscToMint The amount of decentralized stablecoin (DSC) to mint
    * @notice they must have more collateral value than the min threshold to mint DSC
    */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_DscMinted[msg.sender] += amountDscToMint;
        revertIfHealthFactorIsBroken(msg.sender);

    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    // Allows users to quickly burn some DSC and redeem part of their collateral so they can provide it back to the system to maintain their collateralization ratio and avoid being liquidated.
    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    /* PRIVATE AND INTERNAL VIEW FUNCTIONS */


    function _getAccountInformation(address user) private view returns(uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = s_DscMinted[user];
        collateralValueInUsd =

}
    /*
    * Returns how close the user is to liquidation
    * If the user goes below 1, they can get liquidated
    */
    function _healthFactor(address user) internal view returns (uint256){
        (uint256 totalDscMinted, uint256 collaterValueInUsd) = _getAccountInformation(user);

    }
    function _revertIfHealthFactorIsBroken(address user) internal view {
    }

    /* PUBLIC AND EXTERNAL VIEW FUNCTIONS */
    function getAccountCollateralValue(address user) public view returns(uint256) {
        for(uint256 i = 0; i < _collateralTokens.length; i++) {
            address token = _collateralTokens[i];
            uint256 amount = s_CollateralDeposited[user][token];
            totalCollateralInUsd += amount *
        }
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_PriceFeeds[token]);
        (, uint256 price,,,) = priceFeed.latestRoundData();
        return (price * amount / 1e18)
    }
}