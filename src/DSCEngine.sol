// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
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

contract DSCEngine is ReentrancyGuard {

    /* ERRORS */
    error DSCEngine__CollateralNotAllowed();
    error DSCEngine__MustBeMoreThanZero();
    error DSCEngine__NotEnoughCollateral();
    error DSCEngine__NotEnoughDscMinted();
    error DSCEngine__NotEnoughDscBurned();
    error DSCEngine__NotEnoughCollateralToCoverDsc();
    error DSCEngine__TokenAddressesAndPriceFeedsMustBeEqualLength();
    error DSCEngine__HealthFactorTooLow();
    error DSCEngine__MintFailed();
    error DSCEngine__TransferFailed();
    error DSCEngine__HealthFactorOk();
    error DSCEngine__HealthFactorNotImproved();

    /* STATE VARIABLES */
    // Price feeds typically have 8 decimals. ERC20 amounts are typically 18.
    // To normalize an 8-decimal price to 18-decimal USD value, we multiply by 1e10 (18 - 8 = 10).
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10; 
    uint256 private constant PRECISION = 1e18; // Standard 18-decimal precision for calculations
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 50% liquidation threshold (200% overcollateralized required)
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant MIN_HEALTH_FACTOR = 1e18; // Represents 1.0 (the minimum acceptable health factor)
    uint256 private constant LIQUIDATION_BONUS = 10 ; // 10% bonus to liquidators

    mapping(address token => address priceFeed) private s_PriceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private s_CollateralDeposited;
    mapping(address user => uint256 amountDscMinted) private s_DSCMinted;

    address[] private s_collateralTokens;

    DecentralizedStableCoin private immutable i_dsc;

  

    /* EVENTS */
    event CollateralDeposited(address indexed user, address indexed token, uint256 amount);
    event CollateralWithdrawn(address indexed user, address indexed token, uint256 amount);
    event DscMinted(address indexed user, uint256 amount);
    event DscBurned(address indexed user, uint256 amount);
    event CollateralRedeemed(address indexed redeemedFrom, address redeemedTo, address indexed token, uint256 amount);

    /* MODIFIERS */
    modifier moreThanZero(uint256 amount) {
        if (amount == 0) {
           revert DSCEngine__MustBeMoreThanZero();
        }
        _;
    }

    modifier isAllowedToken(address token) {
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
        i_dsc = DecentralizedStableCoin(dscAddress);
    }

    /* VIEW FUNCTIONS (defined first to satisfy compiler for internal calls) */

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_PriceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        if (price <= 0) {
            return 0; // Safely handle non-positive prices
        }

        uint256 priceUsd = uint256(price);

        // Calculation: (price * amount * ADDITIONAL_FEED_PRECISION) / PRECISION
        // (8 decimals * 18 decimals * 1e10) / 1e18 = 18 decimals (USD value)
        return ((priceUsd * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }

    function getAccountCollateralValue(address user) public view returns(uint256) {
        uint256 totalCollateralValueInUsd = 0;
        for(uint256 i = 0; i < s_collateralTokens.length; i++) {
            address token = s_collateralTokens[i];
            uint256 amount = s_CollateralDeposited[user][token];
            totalCollateralValueInUsd += getUsdValue(token, amount);
        }
        return totalCollateralValueInUsd;
    }

    function getTokenAmountFromUsd(address token, uint256 usdAmountInWei) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_PriceFeeds[token]);
        (, int256 price,,,) = priceFeed.latestRoundData();
        return (usdAmountInWei * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }    
    
    function _getAccountInformation(address user) private view returns(uint256 totalDscMinted, uint256 collateralValueInUsd) {
        totalDscMinted = s_DSCMinted[user];
        collateralValueInUsd = getAccountCollateralValue(user);
    }

    function _healthFactor(address user) private view returns (uint256){
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
        
        if (totalDscMinted == 0) {
            return type(uint256).max; // Effectively infinite health factor
        }
        
        // healthFactor = (collateralValue * LIQUIDATION_THRESHOLD / LIQUIDATION_PRECISION) / totalDscMinted * PRECISION
        uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        return (collateralAdjustedForThreshold * PRECISION) / totalDscMinted;
    }

    // Check health factor and revert if it's broken
    function _revertIfHealthFactorIsBroken(address user) internal view {
        // Only check if user has minted DSC
        if (s_DSCMinted[user] == 0) {
            return; 
        }

        uint256 healthFactor = _healthFactor(user);
        if(healthFactor < MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorTooLow();
        }
    }
    
    /*
    * @dev Low-level internal function. Don't call unless this function calling it is checking for health factor being broken.
    */
    function _burnDsc(uint256 amountDscToBurn, address onBehalfOf, address dscFrom) private {
        s_DSCMinted[onBehalfOf] -= amountDscToBurn;
        
        bool success = i_dsc.transferFrom(dscFrom, address(this), amountDscToBurn);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }
        i_dsc.burn(amountDscToBurn);
        _revertIfHealthFactorIsBroken(msg.sender); // safeguard, probably never needed
    }

    function _redeemCollateral(address from, address to, address tokenCollateralAddress, uint256 amountCollateral) private {
        s_CollateralDeposited[msg.sender][tokenCollateralAddress] -= amountCollateral;
        emit CollateralRedeemed(from, to, tokenCollateralAddress, amountCollateral);
        bool success = IERC20(tokenCollateralAddress).transfer(to, amountCollateral);
        if(!success) {
            revert DSCEngine__TransferFailed();
        }        
    }

    /* EXTERNAL/PUBLIC CORE MUTATING FUNCTIONS */

    /*
    * @notice follows CEI (Checks-Effects-Interactions)
    * @param tokenCollateralAddress The address of the token to deposit as collateral
    * @param amountCollateral The amount of collateral to deposit
    */
    function depositCollateral(
        address tokenCollateralAddress, 
        uint256 amountCollateral
    ) 
        public 
        moreThanZero(amountCollateral) 
        isAllowedToken(tokenCollateralAddress) 
        nonReentrant
    {
        // 1. CHECKS (done in modifiers)
        
        // 2. EFFECTS
        s_CollateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        // 3. INTERACTIONS
        // SECURITY FIX: Removed the duplicate transferFrom call which caused the ERC20InsufficientAllowance error.
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
    function mintDsc(uint256 amountDscToMint) public moreThanZero(amountDscToMint) nonReentrant {
        
        // 1. CHECKS
        // Check current health factor before taking on new debt
        _revertIfHealthFactorIsBroken(msg.sender); 

        // 2. EFFECTS
        s_DSCMinted[msg.sender] += amountDscToMint;
        
        // Check new health factor after state update but before interaction
        _revertIfHealthFactorIsBroken(msg.sender);

        // 3. INTERACTIONS
        bool minted = i_dsc.mint(msg.sender, amountDscToMint);
        if(!minted) {
            revert DSCEngine__MintFailed();
        }
        emit DscMinted(msg.sender, amountDscToMint);
    }

    // To redeem collateral, health factor must be >1 after the collateral is redeemed
    function redeemCollateral(address tokenCollateralAddress, uint256 amountCollateral) public moreThanZero(amountCollateral) nonReentrant {
        _redeemCollateral(msg.sender, msg.sender, tokenCollateralAddress, amountCollateral);
        _revertIfHealthFactorIsBroken(msg.sender);

    }

    // Allows users to quickly burn some DSC and redeem part of their collateral so they can provide it back to the system to maintain their collateralization ratio and avoid being liquidated.
    function burnDsc(uint256 amount) public moreThanZero(amount) {
        _burnDsc(amount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender); // safeguard, probably never needed

    }    

    /* EXTERNAL/PUBLIC WRAPPER/CONVENIENCE FUNCTIONS */

    /*
    * @param tokenCollateralAddress The address of the token to deposit as collateral
    * @param amountCollateral The amount of collateral to deposit
    * @param amountDscToMint The amount of decentralized stablecoin (DSC) to mint
    * @notice this function depostits your collateral and mints DSC in one transaction
    * @notice follows CEI (Checks-Effects-Interactions)
    */
    function depositCollateralAndMintDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToMint) external {
        depositCollateral(tokenCollateralAddress, amountCollateral);
        mintDsc(amountDscToMint);
    }

    /*
    * @param tokenCollateralAddress The address of the token to redeem as collateral
    * @param amountCollateral The amount of collateral to redeem
    * @param amountDscToBurn The amount of decentralized stablecoin (DSC) to burn
    * @notice this function burns DSC and redeems underlying collateral in one transaction
    */
    function redeemCollateralForDsc(address tokenCollateralAddress, uint256 amountCollateral, uint256 amountDscToBurn) public {
        burnDsc(amountDscToBurn);
        redeemCollateral(tokenCollateralAddress, amountCollateral);
        // redeemCollateral will revert if the health factor is broken

    }

    /* LIQUIDATION FUNCTION */

    // If someone is almost undercollateralized, the system will pay anybody who liquidates them a bonus for doing so.
    // The liquidator will pay (burn) DSC to the system and in exchange, they will receive the collateral.
    /*
    * @param collateral The address of the collateral to liquidate.
    * @param user The address of the user who has broken the health factor. 
    * @param debtToCover The amount of DSC to burn (cover) to improve the user's health factor.
    * @notice This function is used to liquidate undercollateralized positions.
    * @notice The liquidator pays DSC to the system and receives a portion of the user's collateral at a discount (liquidation bonus).
    * @notice The user's health should be below MIN_HEALTH_FACTOR.
    * @notice The liquidator can choose to partially liquidate a user.
    * @notice The system will transfer the collateral to the liquidator and burn the DSC.
    * @notice This function working assumes the protocol will be roughly 200% overcollateralized for this function to work.
    * @notice This function follows the Checks-Effects-Interactions pattern to ensure security.
    */
    function liquidate(address collateral, address user, uint256 debtToCover) external moreThanZero(debtToCover) nonReentrant {
        uint256 startingUserHealthFactor = _healthFactor(user);
        if (startingUserHealthFactor >= MIN_HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk();
        }
        // Burn the DSC debt, take the collateral at a discount
        uint256 tokenAmountFromDebtCovered = getTokenAmountFromUsd(collateral, debtToCover);
        uint256 bonusCollateral = (tokenAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;
        uint256 totalCollateralToRedeem = tokenAmountFromDebtCovered + bonusCollateral;
        _redeemCollateral(user, msg.sender, collateral, totalCollateralToRedeem);
        _burnDsc(debtToCover, user, msg.sender);

        uint256 endingUserHealthFactor = _healthFactor(user);
        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    function getHealthFactor() external view {} // Empty placeholder for now
}