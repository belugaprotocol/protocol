// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Base mAMM Storage
/// @author Chainvisions
/// @notice State shared between mAMM

contract BaseStorage {

    /// @notice Structure for mAMM reserves.
    struct Reserves {
        uint128 reserve0;
        uint128 reserve1;
    }

    /// @notice Storage layout for the mAMM.
    struct Layout {
        /// TODO: Implement overrides.
        /// @notice Whether or not a module overrides reserves.
        bool overrideReserves;

        /// @notice token0 of the pair.
        IERC20 token0;

        /// @notice token1 of the pair.
        IERC20 token1;

        /// @notice Recorded reserves for the mAMM.
        Reserves reserves;
    }

    function layout() internal pure returns (Layout storage l) {
        assembly {
            l.slot := 0x85420114e2e7eac69299fd7d95b288263b31aafc8baa0533cb8f16126101faf3
        }
    }
}