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
    error DSCEngine__HealthFactorTooLow();

    /* STATE VARIABLES */
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    mapping(address token => address priceFeed) private s_PriceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_CollateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens;

    DecentralizedStablecoin private immutable i_dsc;

    uint256 private constant MIN_HEALTH_FACTOR = 1e18;

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
        bool success = IERC20(tokenCollateralAddress).transferFrom(
        msg.sender,
        address(this),
        amountCollateral
        );
        if(!success) {
            revert DSCEngine__NotEnoughCollateral();
        }
    }

    /*
    * @notice follows CEI
    * @param amountDscToMint The amount of decentralized stablecoin (DSC) to mint
    * @notice users must have more collateral value than the min threshold to mint DSC
    */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
        s_DSCMinted[msg.sender] += amountDscToMint;
        // if the user doesn't have enough collateral to cover the minting, revert
        _revertIfHealthFactorIsBroken(msg.sender);

    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    // Allows users to quickly burn some DSC and redeem part of their collateral so they can provide it back to the system to maintain their collateralization ratio and avoid being liquidated.
    function burnDsc() external {}

    function liquidate() external {}

    function getHealthFactor() external view {}

    
    /* PRIVATE AND INTERNAL VIEW FUNCTIONS */

    // Returns how close the user is to liquidation
    // If the user goes below 1, they can get liquidated

    
    // Check health factor and revert if it's broken
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 healthFactor = _healthFactor(user);
        if(healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorTooLow();
        }
    }

    function _getAccountInformation(address user) private view returns(uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);

}
    /*
    * Returns how close the user is to liquidation
    * If the user goes below 1, they can get liquidated
    */
    function _healthFactor(address user) private view returns (uint256){
        // Total DSC minted
        // Total collateral value
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
    }

    /* PUBLIC AND EXTERNAL VIEW FUNCTIONS */
    function getAccountCollateralValue(address user) public view returns(uint256) {
        // loop through each collateral token, get the amount they have deposited, and map it to the price, to the USD value
        uint256 totalCollateralValueInUsd = 0;
        for(uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_CollateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_PriceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}