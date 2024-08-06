// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/security/ReentrancyGuard.sol';
import '@openzeppelin/contracts/security/Pausable.sol';
import './IDevFund.sol';

contract DevFund is IDevFund, Ownable, ReentrancyGuard, Pausable {
  uint256 public totalDevWeight;
  uint256 public totalRewardDebt;
  mapping(address => DevInfo) public devInfo;

  receive() external payable { // @audit - HIGH: if totalDevWeight is increased substantially more than expected, it will round down the the amountPerWeight causing the funds 
    if (totalDevWeight > 0) {
      uint256 amountPerWeight = msg.value / totalDevWeight; // @audit if msg.value < totalDevWeight, then amountPerWeight will be 0
      uint256 remaining = msg.value - (amountPerWeight * totalDevWeight); // @audit if msg.value < totalDevWeight, then remaining will be msg.value
      totalRewardDebt += amountPerWeight;
      if (remaining > 0) {
        (bool success, ) = payable(owner()).call{ value: remaining }('');
        require(success, 'Failed to send Ether to owner');
      }
    } else {
      (bool success, ) = payable(owner()).call{ value: msg.value }('');
      require(success, 'Failed to send Ether to owner');
    }
    emit FundReceived(msg.sender, msg.value);
  }

  function addDev(address user, uint256 weight) external onlyOwner { // @audit - Commnet, what happens when we update dev weight from one value to another and claiming is done in between that process
    DevInfo storage info = devInfo[user];
    require(weight > 0, 'Invalid weight');
    require(info.weight == 0, 'Already registered');
    info.rewardDebt = totalRewardDebt;
    info.weight = weight;
    totalDevWeight += weight;
    emit AddDev(user, weight);
  }

  function updateDev(address user, uint256 weight) external onlyOwner { // @audit - LOW: Multiple updates with the same weight will increment pending rewards since it doesn't decrement totalRewardDebt
    DevInfo storage info = devInfo[user];
    require(weight > 0, 'Invalid weight');
    require(info.weight > 0, 'Not dev address');
    totalDevWeight = totalDevWeight - info.weight + weight;
    info.pendingRewards += (totalRewardDebt - info.rewardDebt) * info.weight;
    info.rewardDebt = totalRewardDebt;
    info.weight = weight;
    emit UpdateDev(user, weight);
  }

  function removeDev(address user) external onlyOwner { 
    DevInfo storage info = devInfo[user];
    require(info.weight > 0, 'Not dev address');
    totalDevWeight -= info.weight;
    info.pendingRewards += (totalRewardDebt - info.rewardDebt) * info.weight;
    info.rewardDebt = totalRewardDebt;
    info.weight = 0;
    emit RemoveDev(user);
  }

  function claim() external whenNotPaused nonReentrant {
    DevInfo storage info = devInfo[msg.sender];

    uint256 pending = info.pendingRewards +
      (totalRewardDebt - info.rewardDebt) *
      info.weight;

    if (pending > 0) {
      uint256 claimedAmount = safeRewardTransfer(msg.sender, pending);
      info.pendingRewards = pending - claimedAmount;
      emit Claim(msg.sender, claimedAmount);
    }

    info.rewardDebt = totalRewardDebt;
  }

  function pendingRewards(address user) external view returns (uint256) {
    DevInfo storage info = devInfo[user];
    return
      info.pendingRewards + (totalRewardDebt - info.rewardDebt) * info.weight;
  }

  function safeRewardTransfer(
    address to,
    uint256 amount
  ) internal returns (uint256) {
    uint256 _rewardBalance = payable(address(this)).balance;
    if (amount > _rewardBalance) amount = _rewardBalance;
    (bool success, ) = payable(to).call{ value: amount }('');
    require(success, 'Failed to send Reward');
    return amount;
  }
}
