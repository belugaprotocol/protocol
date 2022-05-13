// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title Base Beluga Smart LP
/// @author Chainvisions
/// @notice Base code for a Beluga Smart LP/Market Maker.

contract BaseMarketMaker {

    /// @notice Structure for recording reserves.
    struct LastRecordedReserves {
        uint112 reserve0;   // Last recorded amount of token0.
        uint112 reserve1;   // Last recorded amount of token1.
    }

    /// @notice LP token used by the market maker.
    IERC20 public immutable LP_TOKEN;

    /// @notice Last recorded reserves amount on the LP.
    LastRecordedReserves public lastRecordedReserves;

    constructor(IERC20 _lpToken) {
        LP_TOKEN = _lpToken;
    }

}