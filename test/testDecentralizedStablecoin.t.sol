// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {DecentralizedStablecoin} from "../src/DecentralizedStablecoin.sol";

contract DecentralizedStablecoinTest is Test {
    DecentralizedStablecoin public dsc;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

    uint256 public constant INITIAL_MINT_AMOUNT = 1000e18;
    uint256 public constant LARGE_AMOUNT = type(uint256).max / 2; // Avoid overflow in calculations

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        vm.prank(owner);
        dsc = new DecentralizedStablecoin();
    }

    /*//////////////////////////////////////////////////////////////
                            CONSTRUCTOR TESTS
    //////////////////////////////////////////////////////////////*/

    function test_ConstructorSetsCorrectTokenDetails() public view {
        assertEq(dsc.name(), "Decentralized Stablecoin");
        assertEq(dsc.symbol(), "DSC");
        assertEq(dsc.decimals(), 18);
        assertEq(dsc.totalSupply(), 0);
        assertEq(dsc.owner(), owner);
    }

    /*//////////////////////////////////////////////////////////////
                            MINT FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MintSuccess() public {
        vm.prank(owner);
        bool success = dsc.mint(user1, INITIAL_MINT_AMOUNT);

        assertTrue(success);
        assertEq(dsc.balanceOf(user1), INITIAL_MINT_AMOUNT);
        assertEq(dsc.totalSupply(), INITIAL_MINT_AMOUNT);
    }

    function test_MintEmitsTransferEvent() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(address(0), user1, INITIAL_MINT_AMOUNT);

        vm.prank(owner);
        dsc.mint(user1, INITIAL_MINT_AMOUNT);
    }

    function test_MintRevertsWhenNotOwner() public {
        vm.expectRevert();
        vm.prank(user1);
        dsc.mint(user1, INITIAL_MINT_AMOUNT);
    }

    function test_MintRevertsWithZeroAddress() public {
        vm.expectRevert(DecentralizedStablecoin.DecentralizedStablecoin__CannotBeZeroAddress.selector);

        vm.prank(owner);
        dsc.mint(address(0), INITIAL_MINT_AMOUNT);
    }

    function test_MintRevertsWithZeroAmount() public {
        vm.expectRevert(DecentralizedStablecoin.DecentralizedStablecoin__MustBeMoreThanZero.selector);

        vm.prank(owner);
        dsc.mint(user1, 0);
    }

    function test_MintMultipleUsers() public {
        vm.startPrank(owner);

        dsc.mint(user1, 100e18);
        dsc.mint(user2, 200e18);
        dsc.mint(user3, 300e18);

        vm.stopPrank();

        assertEq(dsc.balanceOf(user1), 100e18);
        assertEq(dsc.balanceOf(user2), 200e18);
        assertEq(dsc.balanceOf(user3), 300e18);
        assertEq(dsc.totalSupply(), 600e18);
    }

    function test_MintLargeAmount() public {
        vm.prank(owner);
        dsc.mint(user1, LARGE_AMOUNT);

        assertEq(dsc.balanceOf(user1), LARGE_AMOUNT);
        assertEq(dsc.totalSupply(), LARGE_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            BURN FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/

    function test_BurnSuccess() public {
        // First mint some tokens
        vm.prank(owner);
        dsc.mint(owner, INITIAL_MINT_AMOUNT);

        // Then burn them
        vm.prank(owner);
        dsc.burn(INITIAL_MINT_AMOUNT / 2);

        assertEq(dsc.balanceOf(owner), INITIAL_MINT_AMOUNT / 2);
        assertEq(dsc.totalSupply(), INITIAL_MINT_AMOUNT / 2);
    }

    function test_BurnRevertsWhenNotOwner() public {
        // Mint to user1
        vm.prank(owner);
        dsc.mint(user1, INITIAL_MINT_AMOUNT);

        // Try to burn as user1 (should fail)
        vm.expectRevert();
        vm.prank(user1);
        dsc.burn(INITIAL_MINT_AMOUNT);
    }

    function test_BurnRevertsWithZeroAmount() public {
        // Mint some tokens to owner
        vm.prank(owner);
        dsc.mint(owner, INITIAL_MINT_AMOUNT);

        vm.expectRevert(DecentralizedStablecoin.DecentralizedStablecoin__MustBeMoreThanZero.selector);

        vm.prank(owner);
        dsc.burn(0);
    }

    function test_BurnRevertsWhenAmountExceedsBalance() public {
        // Mint some tokens to owner
        vm.prank(owner);
        dsc.mint(owner, INITIAL_MINT_AMOUNT);

        vm.expectRevert(DecentralizedStablecoin.DecentralizedStablecoin__BurnAmountExceedsBalance.selector);

        vm.prank(owner);
        dsc.burn(INITIAL_MINT_AMOUNT + 1);
    }

    function test_BurnRevertsWithNoBalance() public {
        vm.expectRevert(DecentralizedStablecoin.DecentralizedStablecoin__BurnAmountExceedsBalance.selector);

        vm.prank(owner);
        dsc.burn(1);
    }

    function test_BurnEntireBalance() public {
        // Mint tokens to owner
        vm.prank(owner);
        dsc.mint(owner, INITIAL_MINT_AMOUNT);

        // Burn entire balance
        vm.prank(owner);
        dsc.burn(INITIAL_MINT_AMOUNT);

        assertEq(dsc.balanceOf(owner), 0);
        assertEq(dsc.totalSupply(), 0);
    }

    /*//////////////////////////////////////////////////////////////
                            OWNERSHIP TESTS
    //////////////////////////////////////////////////////////////*/

    function test_OwnershipTransfer() public {
        // Transfer ownership
        vm.prank(owner);
        dsc.transferOwnership(user1);

        assertEq(dsc.owner(), user1);

        // New owner can mint
        vm.prank(user1);
        bool success = dsc.mint(user2, INITIAL_MINT_AMOUNT);
        assertTrue(success);

        // Old owner cannot mint
        vm.expectRevert();
        vm.prank(owner);
        dsc.mint(user2, INITIAL_MINT_AMOUNT);
    }

    function test_RenounceOwnership() public {
        vm.prank(owner);
        dsc.renounceOwnership();

        assertEq(dsc.owner(), address(0));

        // No one can mint after renouncing ownership
        vm.expectRevert();
        vm.prank(owner);
        dsc.mint(user1, INITIAL_MINT_AMOUNT);
    }

    /*//////////////////////////////////////////////////////////////
                            ERC20 FUNCTIONALITY TESTS
    //////////////////////////////////////////////////////////////*/

    function test_Transfer() public {
        // Mint tokens to user1
        vm.prank(owner);
        dsc.mint(user1, INITIAL_MINT_AMOUNT);

        // Transfer from user1 to user2
        vm.prank(user1);
        bool success = dsc.transfer(user2, INITIAL_MINT_AMOUNT / 2);

        assertTrue(success);
        assertEq(dsc.balanceOf(user1), INITIAL_MINT_AMOUNT / 2);
        assertEq(dsc.balanceOf(user2), INITIAL_MINT_AMOUNT / 2);
    }

    function test_Approve() public {
        // Mint tokens to user1
        vm.prank(owner);
        dsc.mint(user1, INITIAL_MINT_AMOUNT);

        // Approve user2 to spend user1's tokens
        vm.prank(user1);
        bool success = dsc.approve(user2, INITIAL_MINT_AMOUNT / 2);

        assertTrue(success);
        assertEq(dsc.allowance(user1, user2), INITIAL_MINT_AMOUNT / 2);
    }

    function test_TransferFrom() public {
        // Mint tokens to user1
        vm.prank(owner);
        dsc.mint(user1, INITIAL_MINT_AMOUNT);

        // User1 approves user2
        vm.prank(user1);
        dsc.approve(user2, INITIAL_MINT_AMOUNT / 2);

        // User2 transfers from user1 to user3
        vm.prank(user2);
        bool success = dsc.transferFrom(user1, user3, INITIAL_MINT_AMOUNT / 4);

        assertTrue(success);
        assertEq(dsc.balanceOf(user1), INITIAL_MINT_AMOUNT - INITIAL_MINT_AMOUNT / 4);
        assertEq(dsc.balanceOf(user3), INITIAL_MINT_AMOUNT / 4);
        assertEq(dsc.allowance(user1, user2), INITIAL_MINT_AMOUNT / 2 - INITIAL_MINT_AMOUNT / 4);
    }

    /*//////////////////////////////////////////////////////////////
                            FUZZ TESTS
    //////////////////////////////////////////////////////////////*/

    function testFuzz_Mint(address to, uint256 amount) public {
        // Skip zero address and zero amount
        vm.assume(to != address(0));
        vm.assume(amount > 0);
        vm.assume(amount < type(uint256).max / 2); // Prevent overflow

        vm.prank(owner);
        bool success = dsc.mint(to, amount);

        assertTrue(success);
        assertEq(dsc.balanceOf(to), amount);
        assertEq(dsc.totalSupply(), amount);
    }

    function testFuzz_MintMultiple(uint256 amount1, uint256 amount2, uint256 amount3) public {
        vm.assume(amount1 > 0 && amount1 < type(uint256).max / 4);
        vm.assume(amount2 > 0 && amount2 < type(uint256).max / 4);
        vm.assume(amount3 > 0 && amount3 < type(uint256).max / 4);

        vm.startPrank(owner);
        dsc.mint(user1, amount1);
        dsc.mint(user2, amount2);
        dsc.mint(user3, amount3);
        vm.stopPrank();

        assertEq(dsc.balanceOf(user1), amount1);
        assertEq(dsc.balanceOf(user2), amount2);
        assertEq(dsc.balanceOf(user3), amount3);
        assertEq(dsc.totalSupply(), amount1 + amount2 + amount3);
    }

    function testFuzz_Burn(uint256 mintAmount, uint256 burnAmount) public {
        vm.assume(mintAmount > 0 && mintAmount < type(uint256).max / 2);
        vm.assume(burnAmount > 0 && burnAmount <= mintAmount);

        // Mint tokens to owner
        vm.prank(owner);
        dsc.mint(owner, mintAmount);

        // Burn tokens
        vm.prank(owner);
        dsc.burn(burnAmount);

        assertEq(dsc.balanceOf(owner), mintAmount - burnAmount);
        assertEq(dsc.totalSupply(), mintAmount - burnAmount);
    }

    function testFuzz_Transfer(uint256 mintAmount, uint256 transferAmount) public {
        vm.assume(mintAmount > 0 && mintAmount < type(uint256).max / 2);
        vm.assume(transferAmount <= mintAmount);

        // Mint tokens to user1
        vm.prank(owner);
        dsc.mint(user1, mintAmount);

        // Transfer from user1 to user2
        vm.prank(user1);
        bool success = dsc.transfer(user2, transferAmount);

        assertTrue(success);
        assertEq(dsc.balanceOf(user1), mintAmount - transferAmount);
        assertEq(dsc.balanceOf(user2), transferAmount);
    }

    /*//////////////////////////////////////////////////////////////
                            CORNER CASE TESTS
    //////////////////////////////////////////////////////////////*/

    function test_MintMaxUint256() public {
        // This should work as long as it doesn't overflow
        uint256 maxSafeMint = type(uint256).max - 1;

        vm.prank(owner);
        dsc.mint(user1, maxSafeMint);

        assertEq(dsc.balanceOf(user1), maxSafeMint);
    }

    function test_BurnAfterTransfer() public {
        // Mint to owner
        vm.prank(owner);
        dsc.mint(owner, INITIAL_MINT_AMOUNT);

        // Transfer some tokens away
        vm.prank(owner);
        dsc.transfer(user1, INITIAL_MINT_AMOUNT / 2);

        // Owner should only be able to burn their remaining balance
        vm.prank(owner);
        dsc.burn(INITIAL_MINT_AMOUNT / 2);

        assertEq(dsc.balanceOf(owner), 0);
        assertEq(dsc.balanceOf(user1), INITIAL_MINT_AMOUNT / 2);
    }

    function test_MintAfterBurn() public {
        // Mint tokens
        vm.prank(owner);
        dsc.mint(owner, INITIAL_MINT_AMOUNT);

        // Burn some tokens
        vm.prank(owner);
        dsc.burn(INITIAL_MINT_AMOUNT / 2);

        // Mint more tokens
        vm.prank(owner);
        dsc.mint(user1, INITIAL_MINT_AMOUNT);

        assertEq(dsc.balanceOf(owner), INITIAL_MINT_AMOUNT / 2);
        assertEq(dsc.balanceOf(user1), INITIAL_MINT_AMOUNT);
        assertEq(dsc.totalSupply(), INITIAL_MINT_AMOUNT + INITIAL_MINT_AMOUNT / 2);
    }

    function test_BurnExactBalance() public {
        // Mint tokens to owner
        vm.prank(owner);
        dsc.mint(owner, INITIAL_MINT_AMOUNT);

        uint256 balance = dsc.balanceOf(owner);

        // Burn exact balance
        vm.prank(owner);
        dsc.burn(balance);

        assertEq(dsc.balanceOf(owner), 0);
        assertEq(dsc.totalSupply(), 0);
    }

    function test_MultipleOperations() public {
        vm.startPrank(owner);

        // Series of mints and burns
        dsc.mint(owner, 1000e18);
        dsc.burn(500e18);
        dsc.mint(user1, 2000e18);
        dsc.mint(owner, 300e18);
        dsc.burn(200e18);

        vm.stopPrank();

        assertEq(dsc.balanceOf(owner), 600e18); // 1000 - 500 + 300 - 200
        assertEq(dsc.balanceOf(user1), 2000e18);
        assertEq(dsc.totalSupply(), 2600e18);
    }

    function test_OwnerCanBurnAfterOwnershipTransfer() public {
        // Mint tokens to original owner
        vm.prank(owner);
        dsc.mint(owner, INITIAL_MINT_AMOUNT);

        // Transfer ownership
        vm.prank(owner);
        dsc.transferOwnership(user1);

        // Original owner should not be able to burn (not owner anymore)
        vm.expectRevert();
        vm.prank(owner);
        dsc.burn(INITIAL_MINT_AMOUNT);

        // But new owner should be able to burn their own tokens after minting
        vm.prank(user1);
        dsc.mint(user1, INITIAL_MINT_AMOUNT);

        vm.prank(user1);
        dsc.burn(INITIAL_MINT_AMOUNT);

        assertEq(dsc.balanceOf(user1), 0);
    }

    function test_EdgeCaseAmounts() public {
        vm.startPrank(owner);

        // Test with 1 wei
        dsc.mint(user1, 1);
        assertEq(dsc.balanceOf(user1), 1);

        // Test with very small amount
        dsc.mint(user2, 100);
        assertEq(dsc.balanceOf(user2), 100);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                            INVARIANT TESTS
    //////////////////////////////////////////////////////////////*/

    function invariant_TotalSupplyEqualsAllBalances() public view {
        uint256 totalBalance = dsc.balanceOf(owner) +
                              dsc.balanceOf(user1) +
                              dsc.balanceOf(user2) +
                              dsc.balanceOf(user3);

        // This should always hold true
        assertEq(dsc.totalSupply(), totalBalance);
    }

    function invariant_OwnerCanAlwaysMint() public {
        address currentOwner = dsc.owner();
        if (currentOwner != address(0)) {
            vm.prank(currentOwner);
            bool success = dsc.mint(user1, 1);
            assertTrue(success);
        }
    }
}