// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IERC20Ext} from "../interfaces/IERC20Ext.sol";
import {ReentrancyGuard} from "../lib/ReentrancyGuard.sol";
import {SafeTransferLib} from "../lib/SafeTransferLib.sol";
import {BaseMarketMaker} from "../BaseMarketMaker.sol";

/// @title Uniswap Market Maker
/// @author Chainvisions
/// @notice Market maker for Uniswap-based pools.

contract UniswapMarketMaker is BaseMarketMaker, ReentrancyGuard {
    using SafeTransferLib for IERC20;

    constructor(
        IERC20 _lpToken,
        IERC20 _targetToken
    ) BaseMarketMaker(_lpToken, _targetToken) {
        
    }

    /// @notice Adds liquidity to the Smart LP.
    /// @param _tokenIn Token to add liquidity with.
    /// @param _amountIn Amount of tokens to add liquidity with.
    /// @return Output Smart LP tokens.
    function addLiquidity(
        IERC20 _tokenIn,
        uint256 _amountIn
    ) external override nonReentrant returns (uint256) {
        require(_amountIn > 0, "Cannot mint 0");
        IERC20 _token0 = token0;
        IERC20 _token1 = token1;
        require(_tokenIn == _token0 || _tokenIn == _token1, "Must be one of the reserves");

        // Zap into the LP.
        uint8 tokenSide = _tokenIn == _token0 ? 0 : 1;
        InternalData memory _internalData = internalData;
        LastRecordedReserves memory _lastRecordedReserves = lastRecordedReserves;

        // We have to swap the token if it is not our target reserve.
        uint256 targetTokens = _amountIn;
        if(tokenSide != _internalData.targetReserve) {
            // It is cheaper for us to do a low-level swap.
            uint256 _balanceOf = TARGET_TOKEN.balanceOf(address(this));
            _tokenIn.safeTransferFrom(msg.sender, address(LP_TOKEN), _amountIn);
            (uint256 amount0Out, uint256 amount1Out) = tokenSide == 0 ? (_amountIn, uint256(0)) : (uint256(0), _amountIn);
            IUniswapV2Pair(address(LP_TOKEN)).swap(amount0Out, amount1Out, address(this), new bytes(0));
            targetTokens = TARGET_TOKEN.balanceOf(address(this)) - _balanceOf;
        }

        // Calculate and mint shares.
        // TODO: Implement math and logic for this.
        uint256 __totalSupply = totalSupply();
        uint256 totalTargetTokens = _internalData.targetBalanceOf + ((_internalData.targetReserve == 0 ? _lastRecordedReserves.reserve0 : _lastRecordedReserves.reserve1) * 2);
        uint256 toMint = __totalSupply == 0
            ? targetTokens
            : (targetTokens * __totalSupply) / (totalTargetTokens);
        _mint(msg.sender, toMint);

        // Create LP position.
        if(tokenSide == _internalData.targetReserve) _tokenIn.safeTransferFrom(msg.sender, address(this), _amountIn);
        _internalData.targetBalanceOf += uint112(targetTokens / 2);

        // We need to swap half of half to the other side for the LP.
        uint256 targetIn = (targetTokens / 2) / 2;
        TARGET_TOKEN.safeTransfer(address(LP_TOKEN), targetIn);
        (uint256 amount0Out, uint256 amount1Out) = _internalData.targetReserve == 0 ? (targetIn, uint256(0)) : (uint256(0), targetIn);
        IUniswapV2Pair(address(LP_TOKEN)).swap(amount0Out, amount1Out, address(LP_TOKEN), new bytes(0));

        // Mint liquidity.
        TARGET_TOKEN.safeTransfer(address(LP_TOKEN), targetIn);
        uint256 mint = IUniswapV2Pair(address(LP_TOKEN)).mint(address(this));
        require(mint > 0, "Insufficient mint");

        // Write to our position.
        _internalData.lpBalanceOf += uint112(mint);
        uint256 liquiditySupply = LP_TOKEN.totalSupply();
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(address(LP_TOKEN)).getReserves();
        
        _lastRecordedReserves.reserve0 = uint112((reserve0 * _internalData.lpBalanceOf) / liquiditySupply);
        _lastRecordedReserves.reserve1 = uint112((reserve1 * _internalData.lpBalanceOf) / liquiditySupply);

        internalData = _internalData;
        lastRecordedReserves = _lastRecordedReserves;

        return toMint;
    }

    /// @notice Adds liquidity to the Smart LP with specific amounts on each side.
    /// @param _amounts Amount of each token to add liquidity with.
    /// @return Output Smart LP tokens.
    function addLiquidityWithAmounts(
        uint256[] memory _amounts
    ) external override returns (uint256) {
        return 0;
    }

    /// @notice Redeems Smart LP tokens for the LP's reserves.
    /// @param _tokensIn Smart LP tokens to redeem.
    /// @return Output reserves from the redemption.
    function redeemLiquidity(
        uint256 _tokensIn
    ) external override returns (uint256[] memory) {
        return new uint256[](0);
    }

    /// @notice Calculates how much of the target token is supplied in the Smart LP.
    /// @return Total amount of ``TARGET_TOKEN`` held in the Smart LP position.
    function totalSuppliedAssets() external view returns (uint256) {
        return (
            internalData.targetBalanceOf
            + ((internalData.targetReserve == 0 ? lastRecordedReserves.reserve0 : lastRecordedReserves.reserve1) * 2)
        );
    }

    /// @notice Calculates the virtual (or stored) ratio of the Smart LP.
    /// @return The amount of `TARGET_TOKEN` one Smart LP token is worth.
    function virtualRatio() external view returns (uint256) {
        uint256 unit = 10 ** IERC20Ext(address(TARGET_TOKEN)).decimals();
        uint256 _totalSuppliedAssets = internalData.targetBalanceOf
            + ((internalData.targetReserve == 0 ? lastRecordedReserves.reserve0 : lastRecordedReserves.reserve1) * 2);
        return totalSupply() == 0
            ? unit
            : (unit * _totalSuppliedAssets) / totalSupply();
    }

    /// @notice Calculates the unrealized (or current/real time) ratio of the Smart LP.
    /// @return The amount of `TARGET_TOKEN` one Smart LP token is worth based on current pair reserves.
    function unrealizedRatio() external view returns (uint256) {
        uint256 unit = 10 ** IERC20Ext(address(TARGET_TOKEN)).decimals();
        uint256 liquiditySupply = LP_TOKEN.totalSupply();
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(address(LP_TOKEN)).getReserves();
        (uint256 uReserve0, uint256 uReserve1) = ((reserve0 * internalData.lpBalanceOf) / liquiditySupply, (reserve1 * internalData.lpBalanceOf) / liquiditySupply);
        uint256 _totalSuppliedAssets = internalData.targetBalanceOf
            + ((internalData.targetReserve == 0 ? uReserve0 : uReserve1) * 2);
        return totalSupply() == 0
            ? unit
            : (unit * _totalSuppliedAssets) / totalSupply();
    }

    function _setReserveTokens() internal override {
        token0 = IERC20(IUniswapV2Pair(address(LP_TOKEN)).token0());
        token1 = IERC20(IUniswapV2Pair(address(LP_TOKEN)).token1());
        internalData.targetReserve = TARGET_TOKEN == token0 ? 0 : 1;
    }
}