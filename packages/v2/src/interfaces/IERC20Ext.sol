// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IERC20Ext is IERC20 {
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}