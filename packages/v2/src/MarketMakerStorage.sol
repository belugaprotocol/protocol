// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title Market Maker Storage
/// @author Chainvisions
/// @notice Diamond storage for Beluga's market makers.

library MarketMakerStorage {

    /// @notice Structure for recording reserves.
    struct LastRecordedReserves {
        uint112 reserve0;   // Last recorded amount of token0.
        uint112 reserve1;   // Last recorded amount of token1.
    }

    /// @notice Structure for data on our LP position.
    struct InternalData {
        uint8 targetReserve;
        uint112 lpBalanceOf;
        uint112 targetBalanceOf;
    }

    /// @notice Storage layout for Diamond.
    struct Layout {
        /// @notice Last recorded reserves amount on the LP.
        LastRecordedReserves lastRecordedReserves;

        /// @notice LP position data of the market maker.
        InternalData internalData;

        /// @notice token0 of the Smart LP.
        IERC20 token0;

        /// @notice token1 of the Smart LP.
        IERC20 token1;
    }

    bytes32 internal constant STORAGE_SLOT = keccak256('beluga.contracts.storage.Kelp');

    function layout() internal pure returns (Layout storage l) {
        bytes32 slot = STORAGE_SLOT;
        assembly {
            l.slot := slot
        }
    }
}