// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface ITrait is IERC20 {
  function burn(uint256 amount) external returns (bool);
}
