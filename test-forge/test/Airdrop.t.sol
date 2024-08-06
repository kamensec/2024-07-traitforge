// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Setup.t.sol";

contract AirdropTest is SetupTest {
    function setUp() public {
        _setUp();
    }

    // Test cases will be added here

    function testSetupAirdrop() public {
        setupAirdrop(100 ether);
        
        assertTrue(airdrop.airdropStarted(), "Airdrop should be started");
        assertEq(airdrop.totalTokenAmount(), 100 ether, "Total token amount should be 100 ether");
        assertEq(airdrop.totalValue(), 20 ether, "Total value should be 20 ether");
        assertEq(airdrop.userInfo(user1), 10 ether, "User1 should have 10 ether allocated");
        assertEq(airdrop.userInfo(user2), 10 ether, "User2 should have 10 ether allocated");
    }

    function testAirdropClaim() public {
        setupAirdrop(100 ether);
        
        // User1 claims their tokens
        startPrank(user1);
        airdrop.claim();
        stopPrank();

        // Check user1's balance after claim
        uint256 expectedAmount = (100 ether * 10 ether) / 20 ether; // (totalTokenAmount * userAmount) / totalValue
        assertEq(trait.balanceOf(user1), expectedAmount, "User1 should receive correct amount of tokens");
        
        // Check user1's info in airdrop contract
        assertEq(airdrop.userInfo(user1), 0, "User1's allocation should be zero after claim");
        
        // User2 claims their tokens
        startPrank(user2);
        airdrop.claim();
        stopPrank();
        
        // Check user2's balance after claim
        assertEq(trait.balanceOf(user2), expectedAmount, "User2 should receive correct amount of tokens");
        
        // Check user2's info in airdrop contract
        assertEq(airdrop.userInfo(user2), 0, "User2's allocation should be zero after claim");
    }

    function testAirdropClaimRevert() public {
        setupAirdrop(100 ether);
        
        // Try to claim with a non-eligible address
        startPrank(address(0xdead));
        vm.expectRevert("Not eligible");
        airdrop.claim();
        stopPrank();
        
        // User1 claims
        startPrank(user1);
        airdrop.claim();
        stopPrank();
        
        // Try to claim again
        startPrank(user1);
        vm.expectRevert("Not eligible");
        airdrop.claim();
        stopPrank();
    }

    function testAirdropAdminFunctions() public {
        // Test setTraitToken
        startPrank(owner);
        address newTokenAddress = address(0x1234);
        airdrop.setTraitToken(newTokenAddress);
        assertEq(address(airdrop.traitToken()), newTokenAddress, "TraitToken address should be updated");
        stopPrank();
        // Test addUserAmount and subUserAmount
        startPrank(owner);
        airdrop.addUserAmount(user1, 5 ether);
        assertEq(airdrop.userInfo(user1), 5 ether, "User1 should have 5 ether allocated");
        assertEq(airdrop.totalValue(), 5 ether, "Total value should be 5 ether");

        airdrop.subUserAmount(user1, 2 ether);
        assertEq(airdrop.userInfo(user1), 3 ether, "User1 should have 3 ether allocated after subtraction");
        assertEq(airdrop.totalValue(), 3 ether, "Total value should be 3 ether after subtraction");

        // Test allowDaoFund
        airdrop.setTraitToken(address(trait));
        airdrop.startAirdrop(100 ether);
        assertEq(airdrop.daoFundAllowed(), false, "DAO fund should not be allowed initially");
        airdrop.allowDaoFund();
        assertEq(airdrop.daoFundAllowed(), true, "DAO fund should be allowed after allowDaoFund");
        stopPrank();
    }

    function testAirdropInsufficientTokens() public {
        // Setup initial state
        startPrank(owner);
        airdrop.addUserAmount(user1, 60 ether);
        airdrop.addUserAmount(user2, 40 ether);
        stopPrank();

        uint256 totalValue = airdrop.totalValue();
        uint256 airdropAmount = totalValue / 2; // Set airdrop amount to half of totalValue

        // Start airdrop with insufficient tokens
        startPrank(owner);
        airdrop.startAirdrop(airdropAmount);

        // User1 claims
        startPrank(user1);
        airdrop.claim();

        // User2 claims
        startPrank(user2);
        airdrop.claim();
        stopPrank();

        // Check final balance of trait token in the contract
        uint256 contractBalance = trait.balanceOf(address(airdrop));
        assertEq(contractBalance, 0, "Contract should have 0 balance after all claims");

        // Additional checks
        assertEq(trait.balanceOf(user1), airdropAmount * 60 / 100, "User1 should receive 60% of airdropAmount");
        assertEq(trait.balanceOf(user2), airdropAmount * 40 / 100, "User2 should receive 40% of airdropAmount");
        assertEq(airdrop.userInfo(user1), 0, "User1's allocation should be zero after claim");
        assertEq(airdrop.userInfo(user2), 0, "User2's allocation should be zero after claim");
    }



    function testFailAirdropRoundingError() public {
        // Setup initial state
        startPrank(owner);
        airdrop.addUserAmount(user1, 2); // Minimal amount for user1
        airdrop.addUserAmount(user2, 100); // Large amount for user2
        stopPrank();

        uint256 totalValue = airdrop.totalValue();
        uint256 airdropAmount = 50; // Slightly less than user2's amount

        // Start airdrop
        startPrank(owner);
        airdrop.startAirdrop(airdropAmount);

        // User1 claims
        startPrank(user1);
        airdrop.claim();
        stopPrank();

        // Check user1's balance
        uint256 user1Balance = trait.balanceOf(user1);
        assertEq(user1Balance, 0, "User1 should receive 0 tokens due to rounding error");

        // Check that user1's allocation is now 0
        assertEq(airdrop.userInfo(user1), 0, "User1's allocation should be zero after claim");

        // User2 claims
        uint256 expectedUser2Balance = (airdropAmount * airdrop.userInfo(user2)) / airdrop.totalValue();
        startPrank(user2);
        airdrop.claim();
        stopPrank();

        // Check user2's balance
        uint256 user2Balance = trait.balanceOf(user2);
        assertEq(user2Balance, expectedUser2Balance, "User2 should receive correct proportion of airdropAmount");

        // Check final balance of trait token in the contract
        uint256 contractBalance = trait.balanceOf(address(airdrop));
        assertEq(contractBalance, 0, "Contract should have 0 balance after all claims");
    }

    function testFuzzAirdropInsufficientTokens(uint256 user1Amount, uint256 user2Amount, uint256 airdropDivisor) public {
        // Bound the input values to reasonable ranges
        user1Amount = bound(user1Amount, 1 ether, 1000 ether);
        user2Amount = bound(user2Amount, 1 ether, 1000 ether);
        airdropDivisor = bound(airdropDivisor, 1, 100);

        // Setup initial state
        startPrank(owner);
        airdrop.addUserAmount(user1, user1Amount);
        airdrop.addUserAmount(user2, user2Amount);
        stopPrank();

        uint256 totalValue = airdrop.totalValue();
        uint256 airdropAmount = totalValue / airdropDivisor;
        require(airdropAmount <= totalValue, "Airdrop amount should not exceed total value");

        // Start airdrop
        startPrank(owner);
        airdrop.startAirdrop(airdropAmount);

        // User1 claims
        startPrank(user1);
        airdrop.claim();

        // User2 claims
        startPrank(user2);
        airdrop.claim();
        stopPrank();

        // Check final balance of trait token in the contract
        uint256 contractBalance = trait.balanceOf(address(airdrop));
        assertLe(contractBalance, 1, "Contract should have at most 1 wei balance after all claims (accounting for potential rounding errors)");

        // Additional checks
        uint256 expectedUser1Balance = (airdropAmount * user1Amount) / totalValue;
        uint256 expectedUser2Balance = (airdropAmount * user2Amount) / totalValue;
        assertEq(trait.balanceOf(user1), expectedUser1Balance, "User1 should receive correct proportion of airdropAmount");
        assertEq(trait.balanceOf(user2), expectedUser2Balance, "User2 should receive correct proportion of airdropAmount");
        assertEq(airdrop.userInfo(user1), 0, "User1's allocation should be zero after claim");
        assertEq(airdrop.userInfo(user2), 0, "User2's allocation should be zero after claim");
    }

    // function testAirdropPauseFunctionality() public {
    //     setupAirdrop(100 ether);

    //     // Pause the contract
    //     vm.prank(owner);
    //     airdrop.pause();

    //     // Try to claim while paused
    //     vm.prank(user1);
    //     vm.expectRevert("Pausable: paused");
    //     airdrop.claim();

    //     // Unpause the contract
    //     vm.prank(owner);
    //     airdrop.unpause();

    //     // Claim should work now
    //     vm.prank(user1);
    //     airdrop.claim();
    //     assertEq(airdrop.userInfo(user1), 0, "User1's allocation should be zero after claim");
    // }
}
