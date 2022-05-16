// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeTransferLib} from "./lib/SafeTransferLib.sol";

/// @title Base Beluga Smart LP
/// @author Chainvisions
/// @notice Base code for a Beluga Smart LP/Market Maker.

abstract contract BaseMarketMaker is ERC20("Beluga Smart LP", "keLP") {
    using SafeTransferLib for IERC20;

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

    /// @notice LP token used by the market maker.
    IERC20 public immutable LP_TOKEN;

    /// @notice Target token to adjust ratios for.
    IERC20 public immutable TARGET_TOKEN;

    /// @notice Last recorded reserves amount on the LP.
    LastRecordedReserves public lastRecordedReserves;

    /// @notice LP position data of the market maker.
    InternalData public internalData;

    /// @notice token0 of the Smart LP.
    IERC20 public token0;

    /// @notice token1 of the Smart LP.
    IERC20 public token1;

    constructor(IERC20 _lpToken, IERC20 _targetToken) {
        LP_TOKEN = _lpToken;
        TARGET_TOKEN = _targetToken;
        _setReserveTokens();
    }

    /// @notice Adds liquidity to the Smart LP.
    /// @param _tokenIn Token to add liquidity with.
    /// @param _amountIn Amount of tokens to add liquidity with.
    /// @return Output Smart LP tokens.
    function addLiquidity(IERC20 _tokenIn, uint256 _amountIn) external virtual returns (uint256);

    /// @notice Adds liquidity to the Smart LP with specific amounts on each side.
    /// @param _amounts Amount of each token to add liquidity with.
    /// @return Output Smart LP tokens.
    function addLiquidityWithAmounts(uint256[] memory _amounts) external virtual returns (uint256);

    /// @notice Redeems Smart LP tokens for the LP's reserves.
    /// @param _tokensIn Smart LP tokens to redeem.
    /// @return Output reserves from the redemption.
    function redeemLiquidity(uint256 _tokensIn) external virtual returns (uint256[] memory);

    function _setReserveTokens() internal virtual;
}