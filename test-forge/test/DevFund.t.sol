// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/DevFund/DevFund.sol";
import "../src/DevFund/IDevFund.sol";

contract DevFundTest is Test {
    DevFund public devFund;
    address public owner;
    address public dev1;
    address public dev2;
    uint256 public totalDeposits;

    function setUp() public {
        owner = address(this);
        devFund = new DevFund();
        dev1 = address(0x1);
        dev2 = makeAddr("dev2");
    }

    function testAddDev() public {
        devFund.addDev(dev1, 100);
        (uint256 weight, , ) = devFund.devInfo(dev1);
        assertEq(weight, 100);
        assertEq(devFund.totalDevWeight(), 100);
    }

    function testUpdateDev() public {
        devFund.addDev(dev1, 100);
        devFund.updateDev(dev1, 200);
        (uint256 weight, , ) = devFund.devInfo(dev1);
        assertEq(weight, 200);
        assertEq(devFund.totalDevWeight(), 200);
    }

    function testRemoveDev() public {
        devFund.addDev(dev1, 100);
        devFund.removeDev(dev1);
        (uint256 weight, , ) = devFund.devInfo(dev1);
        assertEq(weight, 0);
        assertEq(devFund.totalDevWeight(), 0);
    }

    function testReceiveEther() public {
        devFund.addDev(dev1, 100);
        devFund.addDev(dev2, 200);
        
        uint256 initialBalance = address(devFund).balance;
        uint256 initialRewardDebt = devFund.totalRewardDebt();
        uint256 depositAmount = 1 ether;
        payable(address(devFund)).call{value: depositAmount}("");
        
        assertEq(address(devFund).balance, initialBalance + (depositAmount - getRemainingAmount(depositAmount)), "invalid devFund balance");
        assertEq(uint256(devFund.totalRewardDebt()), getTotalRewardDebt(initialRewardDebt, depositAmount), "invalid totalRewardDebt");
    }

    function testClaim() public {
        addDevAndFund(dev1,100, 1 ether);

        uint256 initialBalance = dev1.balance;
        vm.prank(dev1);
        devFund.claim();

        assertEq(dev1.balance, initialBalance + 1 ether);
    }

    function testClaimTwoDevs() public {
        uint256 totalDevFund = 100 ether;
        uint256 devDeposit = 1 ether;
        // Add Devs
        devFund.addDev(dev1, devDeposit);
        devFund.addDev(dev2, devDeposit);
        // Fund contract
        payable(address(devFund)).call{value: totalDevFund}("");
        assertEq(devFund.totalDevWeight(), 2 * devDeposit, "DevFund should have 2 ether totalDevWeight");
        assertEq(devFund.totalRewardDebt(), totalDevFund / (2 * devDeposit), "DevFund has invalid totalRewardDebt");

        // Record initial balances
        uint256 initialBalance1 = dev1.balance;
        uint256 initialBalance2 = dev2.balance;
        
        // First dev claims
        vm.prank(dev1);
        devFund.claim();
        uint256 claimedAmount = address(dev1).balance - initialBalance1;
        assertEq(claimedAmount, totalDevFund / 2, "Dev1 should have 0.5 of ether claimed");
        
        // Second dev claims
        vm.prank(dev2);
        devFund.claim();
        claimedAmount = address(dev2).balance - initialBalance2;
        assertEq(claimedAmount, totalDevFund / 2, "Dev2 should have 0.5 of ether claimed");
        
        // Check that the contract balance is now 0
        assertEq(address(devFund).balance, 0, "DevFund should have 0 balance after claims");
    }

    function testMultipleUpdatesDoesntChangePendingRewards() public {
        uint256 totalDevFund = 100 ether;
        uint256 initialWeight = 1 ether;
        
        // Add Devs
        devFund.addDev(dev1, initialWeight);
        devFund.addDev(dev2, initialWeight);
        
        // Fund contract
        payable(address(devFund)).call{value: totalDevFund}("");
        
        // Check initial state
        assertEq(devFund.totalDevWeight(), 2 * initialWeight, "DevFund should have 2 ether totalDevWeight");
        assertEq(devFund.totalRewardDebt(), totalDevFund / (2 * initialWeight), "DevFund has invalid totalRewardDebt");

        // Record initial pending rewards
        uint256 initialPendingRewards1 = devFund.pendingRewards(dev1);
        uint256 initialPendingRewards2 = devFund.pendingRewards(dev2);

        // Update dev1 weight multiple times
        devFund.updateDev(dev1, 3 ether);
        uint256 pendingRewardsAfterFirstUpdate = devFund.pendingRewards(dev1);
        assertEq(pendingRewardsAfterFirstUpdate, initialPendingRewards1, "Dev1 pending rewards should not change after first update");

        devFund.updateDev(dev1, 3 ether);
        uint256 pendingRewardsAfterSecondUpdate = devFund.pendingRewards(dev1);
        assertEq(pendingRewardsAfterSecondUpdate, initialPendingRewards1, "Dev1 pending rewards should not change after second update");
    }

    // @audit - POC: rounding down returns 0 balnce to the devFund and owner rugs entire balance.
    function testFailOwnerReceivesRemainingWhenTotalDevWeightLessThanFunding() public {
        uint256 devWeight = 100 ether;
        uint256 fundingAmount = 10 ether;
        
        // Add a dev with weight less than funding amount
        devFund.addDev(dev1, devWeight);
        
        // Record initial balances
        uint256 initialOwnerBalance = owner.balance;
        uint256 initialContractBalance = address(devFund).balance;
        
        // Fund the contract
        payable(address(devFund)).call{value: fundingAmount}("");
      
        // Check that the contract balance is equal to the funding amount
        assertLt(owner.balance, initialOwnerBalance + fundingAmount, "Owner should not receive the full funding amount");   
        assertTrue(address(devFund).balance != 0, "DevFund balance should not be 0");
    }



    function addDevAndFund(address _dev, uint256 devWeight, uint256 depositAmount) public {
        devFund.addDev(_dev, devWeight);
        payable(address(devFund)).call{value: depositAmount}("");
    }


    function getRemainingAmount(uint256 amount) public view returns (uint256) {
        return amount - (amount / devFund.totalDevWeight())*devFund.totalDevWeight();
    }

    function getTotalRewardDebt(uint256 initialRewardDebt, uint256 amount) public view returns (uint256) {
        return initialRewardDebt + (amount / devFund.totalDevWeight());
    }

    receive() external payable {
        totalDeposits += msg.value;
    }
}
