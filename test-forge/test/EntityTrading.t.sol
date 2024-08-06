// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/EntityTrading/EntityTrading.sol";
import "../src/TraitForgeNft/TraitForgeNft.sol";
import "./Setup.t.sol";

contract EntityTradingTest is Test, SetupTest {
    address public alice;
    address public bob;

    function setUp() public {
        _setUp();
    
        // Set Entropy Generator to this contract
        vm.prank(owner);
        traitForgeNft.setEntropyGenerator(address(this));

        alice = makeAddr("alice");
        bob = makeAddr("bob");
        
        // Mint some NFTs for testing
        _helperMintToken(alice, 1, 30); // Alice has a forger
        _helperMintToken(bob, 2, 31); // Bob has a merger

    }

    function testListNFTForSale() public {
        uint256 tokenId = 1;
        uint256 price = 1 ether;

        vm.startPrank(alice);
        traitForgeNft.approve(address(entityTrading), tokenId);
        entityTrading.listNFTForSale(tokenId, price);
        vm.stopPrank();

        (address seller, uint256 listedTokenId, uint256 listedPrice, bool isListed) = entityTrading.listings(1);
        
        assertEq(seller, alice);
        assertEq(listedTokenId, tokenId);
        assertEq(listedPrice, price);
        assertTrue(isListed);
    }

    function testBuyNFT() public {
        uint256 tokenId = 1;
        uint256 price = 1 ether;

        // List NFT
        vm.startPrank(alice);
        traitForgeNft.approve(address(entityTrading), tokenId);
        entityTrading.listNFTForSale(tokenId, price);
        vm.stopPrank();

        // Buy NFT
        vm.deal(bob, price);
        vm.prank(bob);
        entityTrading.buyNFT{value: price}(tokenId);

        assertEq(traitForgeNft.ownerOf(tokenId), bob);
    }

    function testBuyNFTAfterUnapproveAll() public {
        uint256 tokenId = 1;
        uint256 price = 1 ether;

        // List NFT
        vm.startPrank(alice);
        traitForgeNft.setApprovalForAll(address(entityTrading), true);
        entityTrading.listNFTForSale(tokenId, price);
        vm.stopPrank();

        // Unapprove all before buying
        vm.prank(alice);
        traitForgeNft.setApprovalForAll(address(entityTrading), false);

        // Try to buy NFT
        vm.deal(bob, price);
        vm.prank(bob);
        entityTrading.buyNFT{value: price}(tokenId);

        // Assert that the NFT was successfully transferred despite the unapproval
        assertEq(traitForgeNft.ownerOf(tokenId), bob);

        // Verify that the listing was removed
        (,,,bool isListed) = entityTrading.listings(1);
        assertFalse(isListed);
    }



    function testListNFTForSaleWithZeroPrice() public {
        uint256 tokenId = 1;
        uint256 price = 0;

        vm.startPrank(alice);
        traitForgeNft.approve(address(entityTrading), tokenId);
        vm.expectRevert("Price must be greater than zero");
        entityTrading.listNFTForSale(tokenId, price);
        vm.stopPrank();
    }

    function testListNFTForSaleWithoutApproval() public {
        uint256 tokenId = 1;
        uint256 price = 1 ether;

        vm.startPrank(alice);
        vm.expectRevert("Contract must be approved to transfer the NFT.");
        entityTrading.listNFTForSale(tokenId, price);
        vm.stopPrank();
    }

    function testBuyNFTWithInsufficientFunds() public {
        uint256 tokenId = 1;
        uint256 price = 1 ether;

        // List NFT
        vm.startPrank(alice);
        traitForgeNft.approve(address(entityTrading), tokenId);
        entityTrading.listNFTForSale(tokenId, price);
        vm.stopPrank();

        // Try to buy NFT with insufficient funds
        vm.deal(bob, price - 0.1 ether);
        vm.prank(bob);
        vm.expectRevert("ETH sent does not match the listing price");
        entityTrading.buyNFT{value: price - 0.1 ether}(tokenId);
    }

    function testBuyNFTThatIsNotListed() public {
        uint256 tokenId = 2; // Bob's token, which is not listed

        vm.deal(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert("NFT is not listed for sale.");
        entityTrading.buyNFT{value: 0 ether}(tokenId);
    }

    function testCancelListingByNonOwner() public {
        uint256 tokenId = 1;
        uint256 price = 1 ether;

        // List NFT
        vm.startPrank(alice);
        traitForgeNft.approve(address(entityTrading), tokenId);
        entityTrading.listNFTForSale(tokenId, price);
        vm.stopPrank();

        // Try to cancel listing by non-owner
        vm.prank(bob);
        vm.expectRevert("Only the seller can canel the listing.");
        entityTrading.cancelListing(tokenId);
    }

    function testCancelListing() public {
        uint256 tokenId = 1;
        uint256 price = 1 ether;

        // List NFT
        vm.startPrank(alice);
        traitForgeNft.approve(address(entityTrading), tokenId);
        entityTrading.listNFTForSale(tokenId, price);

        // Cancel listing
        entityTrading.cancelListing(tokenId);
        vm.stopPrank();

        // Verify the listing is cancelled
        (address seller, uint256 listedTokenId, uint256 listedPrice, bool isListed) = entityTrading.listings(tokenId);
        assertFalse(isListed, "Listing should be inactive after cancellation");
        assertEq(listedPrice, 0, "Price should be reset to 0 after cancellation");
        assertEq(seller, address(0), "Seller should be reset to address(0) after cancellation");

        // Try to buy the cancelled listing
        vm.deal(bob, price);
        vm.prank(bob);
        vm.expectRevert("NFT is not listed for sale.");
        entityTrading.buyNFT{value: listedPrice}(tokenId);

        // Verify NFT ownership hasn't changed
        assertEq(traitForgeNft.ownerOf(tokenId), alice, "NFT ownership should not change after cancellation");
    }

    function testDoubleListingSameNFT() public {
        uint256 tokenId = 1;
        uint256 price = 1 ether;

        vm.startPrank(alice);
        traitForgeNft.approve(address(entityTrading), tokenId);
        entityTrading.listNFTForSale(tokenId, price);
        
        // Try to list the same NFT again
        vm.expectRevert("Sender must be the NFT owner.");
        entityTrading.listNFTForSale(tokenId, price * 2);
        vm.stopPrank();
    }

    function testSetNukeFundAddress() public {
        address payable newNukeFundAddress = payable(makeAddr("newNukeFund"));
        
        vm.prank(entityTrading.owner());
        entityTrading.setNukeFundAddress(newNukeFundAddress);

        assertEq(entityTrading.nukeFundAddress(), newNukeFundAddress);
    }

    function testSetTaxCut() public {
        uint256 newTaxCut = 20;
        
        vm.prank(entityTrading.owner());
        entityTrading.setTaxCut(newTaxCut);

        assertEq(entityTrading.taxCut(), newTaxCut);
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
}
