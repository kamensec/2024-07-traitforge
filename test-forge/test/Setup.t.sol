
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import {VmSafe} from "forge-std/Vm.sol";

import "../src/Airdrop/Airdrop.sol";
import "../src/DAOFund/DAOFund.sol";
import "../src/DevFund/DevFund.sol";
import "../src/EntityForging/EntityForging.sol";
import "../src/EntityTrading/EntityTrading.sol";
import "../src/EntropyGenerator/EntropyGenerator.sol";
import "../src/NukeFund/NukeFund.sol";
import "../src/Trait/Trait.sol";
import "../src/TraitForgeNft/TraitForgeNft.sol";

contract SetupTest is Test {
        // Internal test helper variables
    address[] lastPranks;

    Airdrop public airdrop;
    DAOFund public daoFund;
    DevFund public devFund;
    EntityForging public entityForging;
    EntityTrading public entityTrading;
    EntropyGenerator public entropyGenerator;
    NukeFund public nukeFund;
    Trait public trait;
    TraitForgeNft public traitForgeNft;

    address public owner;
    address public user1;
    address public user2;
    address public user3;

   // Mock entropy values
    uint256 private forgerEntropy = 30; // Divisible by 3, making it a forger
    uint256 private mergerEntropy = 31; // Not divisible by 3, making it a merger
        
    event Minted(
        address indexed minter,
        uint256 indexed itemId,
        uint256 indexed generation,
        uint256 entropyValue,
        uint256 mintPrice
    );

    function _setUp() public {
        owner = makeAddr("owner");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        startPrank(owner);

        // Deploy Trait token
        trait = new Trait("Trait", "TRAIT", 18, 1000000 ether);

        // Deploy other contracts
        airdrop = new Airdrop();
        daoFund = new DAOFund(address(trait), address(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D)); // Using Uniswap V2 Router address
        devFund = new DevFund();
        traitForgeNft = new TraitForgeNft();
        entityForging = new EntityForging(address(traitForgeNft)); // Assuming EntityForging needs Trait address
        entityTrading = new EntityTrading(address(traitForgeNft)); // Assuming EntityTrading needs Trait address
        entropyGenerator = new EntropyGenerator(address(trait)); // Assuming EntropyGenerator needs Trait address
        nukeFund = new NukeFund(address(trait), address(daoFund), payable(devFund), payable(address(entityForging))); // Assuming NukeFund needs these addresses

        // Set airdrop contract on the traitForgeNft
        traitForgeNft.setAirdropContract(address(airdrop));
        traitForgeNft.setEntityForgingContract(address(entityForging));

        // Set NukeFund address on EntityTrading and EntityForging
        entityTrading.setNukeFundAddress(payable(address(nukeFund)));
        entityForging.setNukeFundAddress(payable(address(nukeFund)));

        // Setup nuke fund with airdrop contract
        nukeFund.setAirdropContract(address(airdrop));

        // Setup initial states and connections between contracts
        airdrop.setTraitToken(address(trait));
        trait.approve(address(airdrop), type(uint256).max);
        trait.approve(address(daoFund), type(uint256).max);

        // Add liquidity to DAOFund (simulating Uniswap interaction)
        trait.transfer(address(daoFund), 1000 ether);
        vm.deal(address(daoFund), 100 ether);

        // Setup other contracts as needed
        // Note: You may need to adjust these setups based on the specific requirements of each contract

        stopPrank();
    }

    function testTrue() public {
        assertTrue(true);
    }

    // Helper functions for testing
    function setupAirdrop(uint256 _claimAmount) public {
        assertEq(airdrop.airdropStarted(), false, "Airdrop should not be started");
        
        startPrank(owner);
        // Add balance for user 1 and user 2
        airdrop.addUserAmount(user1, 10 ether);
        airdrop.addUserAmount(user2, 10 ether);

        airdrop.startAirdrop(_claimAmount);

        stopPrank();
    } 




    function startPrank(address sender) internal {
        startPrank(sender, sender);
    }

    ///      This is useful if you want to nest pranks.
    ///      Call `helper_stopPrank()` to go back to the previous prank.
    function startPrank(address sender, address origin) internal {
        (VmSafe.CallerMode callerMode, address currentSender, ) = vm
            .readCallers();

        if (callerMode == VmSafe.CallerMode.RecurrentPrank) {
            lastPranks.push(currentSender);
        }
        vm.stopPrank();
        vm.startPrank(sender, origin);
    }


    /// @dev Wrapper over `vm.stopPrank()`.
    ///      This is useful if you are nesting pranks with `helper_startPrank()`.
    ///      Reverts back to the previous prank.
    function stopPrank() internal {
        uint256 numLastPranks = lastPranks.length;

        if (numLastPranks > 0) {
            address lastSender = lastPranks[lastPranks.length - 1];
            lastPranks.pop();
            vm.stopPrank();
            vm.startPrank(lastSender);
        } else {
            vm.stopPrank();
        }
    }
    
    // Mock entropy generation
    function getNextEntropy() external view returns (uint256) {
        if(traitForgeNft.totalSupply() == 1) return getForgerEntropy();
        return getMergerEntropy();
    }

    // Getter for forger entropy
    function getForgerEntropy() public view returns (uint256) {
        return forgerEntropy;
    }

    // Setter for forger entropy
    function setForgerEntropy(uint256 _forgerEntropy) public {
        forgerEntropy = _forgerEntropy;
    }

    // Getter for merger entropy
    function getMergerEntropy() public view returns (uint256) {
        return mergerEntropy;
    }

    // Setter for merger entropy
    function setMergerEntropy(uint256 _mergerEntropy) public {
        mergerEntropy = _mergerEntropy;
    }


    function generateAndSetRootHash(address[] memory addresses) public {
        bytes32[] memory leaves = new bytes32[](addresses.length);
        for (uint256 i = 0; i < addresses.length; i++) {
            leaves[i] = keccak256(abi.encodePacked(addresses[i]));
        }

        bytes32[] memory tree = new bytes32[](2 * leaves.length - 1);
        uint256 treeIndex = 0;

        for (uint256 i = 0; i < leaves.length; i++) {
            tree[treeIndex] = leaves[i];
            treeIndex++;
        }

        uint256 levelSize = leaves.length;
        uint256 treeLevel = 0;

        while (levelSize > 1) {
            for (uint256 i = 0; i < levelSize - 1; i += 2) {
                uint256 leftChildIndex = treeLevel * levelSize + i;
                uint256 rightChildIndex = treeLevel * levelSize + i + 1;
                bytes32 left = tree[leftChildIndex];
                bytes32 right = tree[rightChildIndex];
                tree[treeIndex] = keccak256(abi.encodePacked(left, right));
                treeIndex++;
            }

            if (levelSize % 2 == 1) {
                uint256 lastIndex = treeLevel * levelSize + levelSize - 1;
                tree[treeIndex] = tree[lastIndex];
                treeIndex++;
            }

            levelSize = (levelSize + 1) / 2;
            treeLevel++;
        }

        bytes32 rootHash = tree[treeIndex - 1];

        vm.prank(owner);
        traitForgeNft.setRootHash(rootHash);
    }
}
