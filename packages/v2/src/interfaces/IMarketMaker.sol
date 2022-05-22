// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @title IMarketMaker
/// @author Chainvisions
/// @notice Abstract interface for a market making vault.

interface IMarketMaker {
    /// @notice Adjusts the market position when there is enough IL.
    function adjust() external;

    /// @notice Adds liquidity to the Smart LP.
    /// @param _tokenIn Token to add liquidity with.
    /// @param _amountIn Amount of tokens to add liquidity with.
    /// @return Output Smart LP tokens.
    function addLiquidity(address _tokenIn, uint256 _amountIn) external returns (uint256);

    /// @notice Redeems Smart LP tokens for the LP's reserves.
    /// @param _tokensIn Smart LP tokens to redeem.
    /// @param _amountOutMin Min tokens received from the redemption.
    /// @return Output reserves from the redemption.
    function redeemLiquidity(uint256 _tokensIn, uint256 _amountOutMin) external returns (uint256);

    /// @notice Safer version of `redeemLiquidity` which involves no zapping.
    /// @param _tokensIn Smart LP tokens to redeem.
    /// @return Output reserves from the redemption.
    function safeRedeemLiquidity(uint256 _tokensIn) external returns (uint256);

    /// @notice token0 of the Smart LP.
    function token0() external view returns (address);

    /// @notice token1 of the Smart LP.
    function token1() external view returns (address);

    /// @notice Calculates if a ratio adjustment is possible.
    /// @return Whether or not the Smart LP should adjust its ratio.
    function shouldAdjust() external view returns (bool);

    /// @notice Calculates how much of the target token is supplied in the Smart LP.
    /// @return Total amount of tokens held in the Smart LP position.
    function totalSuppliedAssets() external view returns (uint256);

    /// @notice Calculates the virtual (or stored) ratio of the Smart LP.
    /// @return The amount of `TARGET_TOKEN` one Smart LP token is worth.
    function virtualRatio() external view returns (uint256);

    /// @notice Calculates the unrealized (or current/real time) ratio of the Smart LP.
    /// @return The amount of tokens one Smart LP token is worth based on current pair reserves.
    function unrealizedRatio() external view returns (uint256);
}