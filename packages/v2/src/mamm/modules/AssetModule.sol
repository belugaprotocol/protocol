// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {Cast} from "../../lib/Cast.sol";
import {ReentrancyGuard} from "../../lib/ReentrancyGuard.sol";
import {BaseStorage, IERC20} from "../BaseStorage.sol";

contract AssetModule is BaseStorage, ReentrancyGuard {
    using Cast for uint256;

    /// @notice Updates the reserves of the AMM.
    function sync() external nonReentrant {
        BaseStorage.Reserves memory reserves = layout().reserves;
        reserves.reserve0 = layout().token0.balanceOf(address(this)).u128();
        reserves.reserve1 = layout().token1.balanceOf(address(this)).u128();
        layout().reserves = reserves;
    }
}