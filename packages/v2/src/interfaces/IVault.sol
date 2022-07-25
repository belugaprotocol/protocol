// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IVault is IERC20 {
    function deposit(uint256) external;
    function withdraw(uint256) external;
    function doHardWork() external;
    function getReward() external;
    function initializeVault(
        address,
        address,
        uint256,
        bool,
        uint256
    ) external;
    function setStrategy(address) external;
    function addRewardDistribution(address) external;
    function addRewardToken(address, uint256) external;
    function strategy() external view returns (address);
    function getPricePerFullShare() external view returns (uint256);
}