// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

/// @title IMarketMaker
/// @author Chainvisions
/// @notice Abstract interface for a market making vault.

interface IMarketMaker {
    /// @notice Adds liquidity to the Smart LP.
    /// @param _tokenIn Token to add liquidity with.
    /// @param _amountIn Amount of tokens to add liquidity with.
    /// @return Output Smart LP tokens.
    function addLiquidity(address _tokenIn, uint256 _amountIn) external view returns (uint256);

    /// @notice Adds liquidity to the Smart LP with specific amounts on each side.
    /// @param _amounts Amount of each token to add liquidity with.
    /// @return Output Smart LP tokens.
    function addLiquidityWithAmounts(uint256[] memory _amounts) external view returns (uint256);

    /// @notice Redeems Smart LP tokens for the LP's reserves.
    /// @param _tokensIn Smart LP tokens to redeem.
    /// @return Output reserves from the redemption.
    function redeemLiquidity(uint256 _tokensIn) external view returns (uint256[] memory);

    /// @notice Redeems Smart LP tokens and zaps them out to a specific token.
    /// @param _tokensIn Smart LP tokens to redeem.
    /// @param _targetToken Target token to redeem the LPs for. Must be one of the reserves.
    /// @return Output `_targetToken` received from the redemption.
    function redeemAndZapOut(uint256 _tokensIn, address _targetToken) external view returns (uint256);

    /// @notice Ratio of tokens per Smart LP redeemed.
    /// @return The amount of tokens on each reserve per Smart LP token.
    function getRedemptionRatios() external view returns (uint256[] memory);
}