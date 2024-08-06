// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./Setup.t.sol";
import "../src/EntityForging/EntityForging.sol";
import "../src/EntityForging/IEntityForging.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract EntityForgingTest is SetupTest {
 
    address[] public whitelistedUsers;

    function setUp() public {
        _setUp();
        // Create 6 additional whitelisted users
        address user4 = address(0x4);
        address user5 = address(0x5);
        address user6 = address(0x6);
        address user7 = address(0x7);
        address user8 = address(0x8);

        // Add these users to the whitelist
        whitelistedUsers = new address[](8);
        whitelistedUsers[0] = user1;
        whitelistedUsers[1] = user2;
        whitelistedUsers[2] = user3;
        whitelistedUsers[3] = user4;
        whitelistedUsers[4] = user5;
        whitelistedUsers[5] = user6;
        whitelistedUsers[6] = user7;
        whitelistedUsers[7] = user8;

        // Update the generateAndSetRootHash call to include all users
        generateAndSetRootHash(whitelistedUsers);

        address dummyNukeFund = makeAddr("dummyNukeFund");

        // Set nuke fund
        vm.prank(owner);
        entityForging.setNukeFundAddress(payable(address(dummyNukeFund)));


    }

    function testSetNukeFundAddress() public {
        address payable newNukeFundAddress = payable(address(0x123));
        vm.prank(owner);
        entityForging.setNukeFundAddress(newNukeFundAddress);
        assertEq(entityForging.nukeFundAddress(), newNukeFundAddress);
    }

    function testSetTaxCut() public {
        uint256 newTaxCut = 15;
        vm.prank(owner);
        entityForging.setTaxCut(newTaxCut);
        assertEq(entityForging.taxCut(), newTaxCut);
    }

    function testSetOneYearInDays() public {
        uint256 newOneYearInDays = 366 days;
        vm.prank(owner);
        entityForging.setOneYearInDays(newOneYearInDays);
        assertEq(entityForging.oneYearInDays(), newOneYearInDays);
    }

    function testSetMinimumListingFee() public {
        uint256 newMinimumListFee = 0.02 ether;
        vm.prank(owner);
        entityForging.setMinimumListingFee(newMinimumListFee);
        assertEq(entityForging.minimumListFee(), newMinimumListFee);
    }



    function testListForForging() public {
        // Setup: Create two NFTs with specific generations and entropies
        uint256 forgerTokenId = 1;
        uint256 mergerTokenId = 2;
        uint256 generation = 1;
        uint256 forgingFee = 0.1 ether;

        // Mint forger NFT to user1
        vm.startPrank(owner);
        traitForgeNft.setEntropyGenerator(address(this)); // Set this contract as entropy generator
        traitForgeNft.setEntityForgingContract(address(entityForging));
        vm.stopPrank();


        // Mint forger NFT
        setupAirdrop(10 ether);
        uint256 mintPrice = traitForgeNft.calculateMintPrice();
        vm.deal(user1, mintPrice);
        vm.prank(user1);
        traitForgeNft.mintToken{value: mintPrice}(new bytes32[](0));

        assertEq(traitForgeNft.ownerOf(forgerTokenId), user1, "owner not usr 1");

        // Mint merger NFT to user2

        mintPrice = traitForgeNft.calculateMintPrice();
        vm.deal(user2, mintPrice);
        vm.prank(user2);
        traitForgeNft.mintToken{value: mintPrice}(new bytes32[](0));
        assertEq(traitForgeNft.ownerOf(mergerTokenId), user2, "owner not usr 2");



        // List forger NFT for forging
        vm.startPrank(user1);
        traitForgeNft.approve(address(entityForging), forgerTokenId);
        entityForging.listForForging(forgerTokenId, forgingFee);
        vm.stopPrank();

        // Forge
        vm.prank(user2);
        vm.deal(user2, forgingFee);
        uint256 newTokenId = entityForging.forgeWithListed{value: forgingFee}(forgerTokenId, mergerTokenId);

        // Assertions
        assertEq(traitForgeNft.ownerOf(newTokenId), user2);
        assertEq(traitForgeNft.getTokenGeneration(newTokenId), generation + 1);
        
        // Check that the forger NFT is no longer listed
        IEntityForging.Listing memory listing = entityForging.getListings(entityForging.getListedTokenIds(forgerTokenId));
        assertFalse(listing.isListed);
    }

    function testForgeWithListed() public {
        // Setup
        // Set traitForgeNFT entropy generator and entityForging contract
        vm.startPrank(owner);
        traitForgeNft.setEntropyGenerator(address(this));
        traitForgeNft.setEntityForgingContract(address(entityForging));
        vm.stopPrank();

        // Mint tokens
        uint256 forgerTokenId = _helperMintToken(user1, 1, 30);
        uint256 mergerTokenId = _helperMintToken(user2, 2, 31);
        uint256 forgingFee = 0.1 ether;

        uint256 initialDevFundBalance = address(entityForging.nukeFundAddress()).balance;

        // List forger NFT for forging
        _helperListForForging(user1, forgerTokenId, forgingFee);

        // Prepare user2 for forging
        vm.deal(user2, forgingFee);

        // Forge
        vm.prank(user2);
        uint256 newTokenId = entityForging.forgeWithListed{value: forgingFee}(forgerTokenId, mergerTokenId);

        // Assertions
        assertEq(traitForgeNft.ownerOf(newTokenId), user2, "New token should be owned by user2");
        assertEq(traitForgeNft.getTokenGeneration(newTokenId), traitForgeNft.getTokenGeneration(forgerTokenId) + 1, "New token should be next generation");
        
        // Check that the forger NFT is no longer listed
        IEntityForging.Listing memory listing = entityForging.getListings(entityForging.getListedTokenIds(forgerTokenId));
        assertFalse(listing.isListed, "Forger NFT should no longer be listed");

        // Check forging counts
        assertEq(entityForging.forgingCounts(forgerTokenId), 1, "Forger's forging count should be incremented");
        assertEq(entityForging.forgingCounts(mergerTokenId), 1, "Merger's forging count should be incremented");

        // Check balances
        uint256 taxCut = entityForging.taxCut();
        uint256 devFee = forgingFee / taxCut;
        uint256 forgerShare = forgingFee - devFee;
        assertEq(address(entityForging.nukeFundAddress()).balance, initialDevFundBalance + devFee, "NukeFund should receive the correct fee");
        assertEq(user1.balance, forgerShare, "Forger should receive the correct share");
    }

    // @audit - POC: front running a users forge attempt can strip users of entire balance amount.
    function testCancelAndRelistForForging() public {
        // Setup
        vm.startPrank(owner);
        traitForgeNft.setEntropyGenerator(address(this));
        traitForgeNft.setEntityForgingContract(address(entityForging));
        vm.stopPrank();


        // Mint tokens
        uint256 forgerTokenId = _helperMintToken(user1, 1, 30);
        uint256 mergerTokenId = _helperMintToken(user2, 2, 31);
        uint256 initialForgingFee = 0.1 ether;
        uint256 higherForgingFee = 0.5 ether;
        uint256 finalForgeValue = 0.5 ether; // Shows how the user might send extra eth and that will be captured by MEV based forgers who cancel and relist at higher fees.

        vm.deal(user2, 100 ether);

        // List forger NFT for forging
        _helperListForForging(user1, forgerTokenId, initialForgingFee);

        // Cancel listing
        vm.prank(user1);
        entityForging.cancelListingForForging(forgerTokenId);

        // Check if the listing was cancelled
        IEntityForging.Listing memory cancelledListing = entityForging.getListings(entityForging.getListedTokenIds(forgerTokenId));
        assertFalse(cancelledListing.isListed, "Token should not be listed after cancellation");

        // Relist with higher fee
        _helperListForForging(user1, forgerTokenId, higherForgingFee);

        // Check if the new listing was created correctly
        IEntityForging.Listing memory newListing = entityForging.getListings(entityForging.getListedTokenIds(forgerTokenId));
        assertTrue(newListing.isListed, "Token should be listed");
        assertEq(newListing.fee, higherForgingFee, "New listing should have the higher fee");



        uint256 initialDevFundBalance = address(entityForging.nukeFundAddress()).balance;

        // Forge with the new higher fee
        {
            uint256 initialEntityForgingBalance = address(entityForging).balance;

            vm.prank(user2);
            entityForging.forgeWithListed{value: finalForgeValue}(forgerTokenId, mergerTokenId);

            uint256 finalEntityForgingBalance = address(entityForging).balance;
            assertEq(finalEntityForgingBalance, initialEntityForgingBalance, "EntityForging shouldn't hold eth");
        }

        // Check that the forger NFT is no longer listed
        IEntityForging.Listing memory finalListing = entityForging.getListings(entityForging.getListedTokenIds(forgerTokenId));
        assertFalse(finalListing.isListed, "Forger NFT should no longer be listed after forging");

        // Check balances
        uint256 taxCut = entityForging.taxCut();
        uint256 devFee = higherForgingFee / taxCut;
        uint256 forgerShare = higherForgingFee - devFee;
        assertEq(address(entityForging.nukeFundAddress()).balance, initialDevFundBalance + devFee, "NukeFund should receive the correct fee");
        assertEq(user1.balance, forgerShare, "Forger should receive the correct share");
    }


    // @audit - POC: rounding during forgeWithListed can lead to loss of funds for the user and protocol
    function testFailRoundingDuringForgeWithListedLosesEth() public {
        // Setup
        vm.startPrank(owner);
        traitForgeNft.setEntropyGenerator(address(this));
        traitForgeNft.setEntityForgingContract(address(entityForging));
        vm.stopPrank();

        uint256 initialDevFundBalance = address(entityForging.nukeFundAddress()).balance;

        // Mint tokens
        uint256 forgerTokenId = _helperMintToken(user1, 1, 30);
        uint256 mergerTokenId = _helperMintToken(user2, 2, 31);
        uint256 initialForgingFee = 0.1 ether;
        uint256 finalForgeMsgValue = 0.5 ether;

        vm.deal(user2, 100 ether);

        // List forger NFT for forging
        _helperListForForging(user1, forgerTokenId, initialForgingFee);

        // Forge with the new higher fee
        
        uint256 initialEntityForgingBalance = address(entityForging).balance;
        vm.prank(user2);
        entityForging.forgeWithListed{value: finalForgeMsgValue}(forgerTokenId, mergerTokenId);
        uint256 finalEntityForgingBalance = address(entityForging).balance;

        // @audit - There is no way to recover eth from the EntityForging contract, therefore it shouldn't have balances remaining.
        // @audit - This is a loss of funds for the users and the protocol.
        assertEq(finalEntityForgingBalance, initialEntityForgingBalance, "EntityForging shouldn't hold eth");    
    }


    // @audit - POC: multiple resets in the same block can be exploited to reset the forging count in the same transaction block.
    function testFailMultipleResetsForgingCountInSameBlock() public {
        // Setup
        vm.startPrank(owner);
        traitForgeNft.setEntropyGenerator(address(this));
        traitForgeNft.setEntityForgingContract(address(entityForging));
        entityForging.setOneYearInDays(0); // Set to 0 to allow immediate resets
        vm.stopPrank();

        // Mint tokens
        uint256 forgerTokenId = _helperMintToken(user1, 1, 30);
        uint256 mergerTokenId = _helperMintToken(user2, 2, 31);

        uint256 forgingFee = 0.1 ether;
        vm.deal(user2, 100 ether);

        // First forge
        _helperListForForging(user1, forgerTokenId, forgingFee);
        vm.prank(user2);
        entityForging.forgeWithListed{value: forgingFee}(forgerTokenId, mergerTokenId);

        uint8 forgingCountAfterFirstForge = _getForgingCount(forgerTokenId);

        // Second forge
        _helperListForForging(user1, forgerTokenId, forgingFee);
        vm.prank(user2);
        entityForging.forgeWithListed{value: forgingFee}(forgerTokenId, mergerTokenId);

        uint8 forgingCountAfterSecondForge = _getForgingCount(forgerTokenId);

        // Third forge
        _helperListForForging(user1, forgerTokenId, forgingFee);
        vm.prank(user2);
        entityForging.forgeWithListed{value: forgingFee}(forgerTokenId, mergerTokenId);

        uint8 forgingCountAfterThirdForge = _getForgingCount(forgerTokenId);

        // Check that forgingCounts for forgerTokenId hasn't increased
        assertEq(forgingCountAfterFirstForge, 1, "Forging count should be 1 after 1 forge");
        assertEq(forgingCountAfterSecondForge, 2, "Forging count should be 2 after 2 forges");
        assertEq(forgingCountAfterThirdForge, 3, "Forging count should be 3 after 3 forges");
    }

    function _getForgingCount(uint256 tokenId) internal view returns (uint8) {
        (bool success, bytes memory data) = address(entityForging).staticcall(
            abi.encodeWithSignature("forgingCounts(uint256)", tokenId)
        );
        require(success, "Call to forgingCounts failed");
        return abi.decode(data, (uint8));
    }

    function _helperMintToken(address user, uint256 expectedTokenId, uint256 _entropy) internal returns (uint256) {
        // Setup airdrop if not already done
        if (!airdrop.airdropStarted()) {
            setupAirdrop(10 ether);
        }

        // Calculate mint price
        uint256 mintPrice = traitForgeNft.calculateMintPrice();

        // Ensure user has enough ETH to mint
        vm.deal(user, mintPrice);

        // Mint token
        startPrank(user);
        // vm.expectEmit(true, true, true, true);
        emit Minted(user, expectedTokenId, traitForgeNft.getGeneration(), _entropy, mintPrice);
        traitForgeNft.mintToken{value: mintPrice}(new bytes32[](0));
        stopPrank();

        return expectedTokenId;
    }

    function _helperListForForging(address user, uint256 tokenId, uint256 fee) internal {
        // Ensure the user owns the token
        assertEq(traitForgeNft.ownerOf(tokenId), user, "User does not own the token");

        // Approve EntityForging contract to transfer the NFT
        vm.prank(user);
        traitForgeNft.approve(address(entityForging), tokenId);
        
        // List the NFT for forging
        vm.prank(user);
        entityForging.listForForging(tokenId, fee);
        
        // Check if the listing was created correctly
        IEntityForging.Listing memory listing = entityForging.getListings(entityForging.getListedTokenIds(tokenId));
        assertTrue(listing.isListed, "Token not listed");
    }
}

