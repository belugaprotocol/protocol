// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IERC20Ext} from "../interfaces/IERC20Ext.sol";
import {Errors, _require} from "../lib/Errors.sol";
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
    ) BaseMarketMaker(_lpToken, _targetToken) {}

    /// @notice Adjusts the market position when there is enough IL.
    function adjust() external override {
        InternalData memory _internalData = internalData;
        LastRecordedReserves memory _lastRecordedReserves = lastRecordedReserves;

        uint256 liquiditySupply = LP_TOKEN.totalSupply();
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(address(LP_TOKEN)).getReserves();

        // Check if the reserves changed enough to induce IL for an adjustment.
        uint256 targetReserve = _internalData.targetReserve == 0 ? (reserve0 * _internalData.lpBalanceOf) / liquiditySupply : (reserve1 * _internalData.lpBalanceOf) / liquiditySupply;
        uint256 targetVirtualReserve = _internalData.targetReserve == 0 ? _lastRecordedReserves.reserve0 : _lastRecordedReserves.reserve1;

        if((targetReserve * 1000) / targetVirtualReserve >= 5000) {
            // Check which way the reserve changed.
            if(targetReserve > targetVirtualReserve) {
                // In this case, we've gained more tokens from Il.
                // This means that we can take profit from the LP.
                uint256 performanceFee = ((((targetReserve - _internalData.targetBalanceOf) * ((targetReserve * 1000) / targetVirtualReserve)) / 10000) * 10) / 100;
                uint256 difference = ((targetReserve - _internalData.targetBalanceOf) / 2) - performanceFee;
                uint256 rate = ((_internalData.lpBalanceOf * 1e18) / targetReserve);
                uint256 burn = rate * difference;
                LP_TOKEN.safeTransfer(address(LP_TOKEN), burn);
                (uint256 r0Liquidity, uint256 r1Liquidity) = IUniswapV2Pair(address(LP_TOKEN)).burn(address(this));

                // Swap other reserve for our target token.
                (uint256 amount0Out, uint256 amount1Out) = _internalData.targetReserve == 0 ? (uint256(0), r1Liquidity) : (r0Liquidity, uint256(0));
                IUniswapV2Pair(address(LP_TOKEN)).swap(amount0Out, amount1Out, address(this), new bytes(0));

                _internalData.lpBalanceOf -= uint112(burn);
                _internalData.targetBalanceOf = uint112(TARGET_TOKEN.balanceOf(address(this)));

            } else if(targetReserve < targetVirtualReserve) {
                // In this case, we've lost tokens to IL. This means that we will 
                // need to supply more liquidity to cover the losses made by the LP.
                uint256 difference = (targetVirtualReserve - targetReserve) * 2;
                uint256 toSwap = difference / 2;
                TARGET_TOKEN.safeTransfer(address(LP_TOKEN), difference / 2);
                (uint256 amount0Out, uint256 amount1Out) = _internalData.targetReserve == 0 ? (toSwap, uint256(0)) : (uint256(0), toSwap);
                IUniswapV2Pair(address(LP_TOKEN)).swap(amount0Out, amount1Out, address(LP_TOKEN), new bytes(0));
                TARGET_TOKEN.safeTransfer(address(LP_TOKEN), toSwap);
                uint256 mint = IUniswapV2Pair(address(LP_TOKEN)).mint(address(this));
                _require(mint > 0, Errors.INSUFFICIENT_MINT);

                _internalData.lpBalanceOf += uint112(mint);
                _internalData.targetBalanceOf -= uint112(difference);
            }
        } else {
            // No IL. We do not need to adjust our position.
            return;
        }

        // Update stored data.
        liquiditySupply = LP_TOKEN.totalSupply();
        (reserve0, reserve1,) = IUniswapV2Pair(address(LP_TOKEN)).getReserves();
        _lastRecordedReserves.reserve0 = uint112((reserve0 * _internalData.lpBalanceOf) / liquiditySupply);
        _lastRecordedReserves.reserve1 = uint112((reserve1 * _internalData.lpBalanceOf) / liquiditySupply);

        internalData = _internalData;
        lastRecordedReserves = _lastRecordedReserves;

        emit Adjustment(block.timestamp);
    }

    /// @notice Adds liquidity to the Smart LP.
    /// @param _tokenIn Token to add liquidity with.
    /// @param _amountIn Amount of tokens to add liquidity with.
    /// @return Output Smart LP tokens.
    function addLiquidity(
        IERC20 _tokenIn,
        uint256 _amountIn
    ) external override nonReentrant returns (uint256) {
        _require(_amountIn > 0, Errors.CANNOT_DEPOSIT_ZERO);
        IERC20 _token0 = token0;
        IERC20 _token1 = token1;
        _require(_tokenIn == _token0 || _tokenIn == _token1, Errors.CANNOT_DEPOSIT_ZERO);

        // Zap into the LP.
        DepositStack memory _stack;
        _stack.tokenSide = _tokenIn == _token0 ? 0 : 1;
        InternalData memory _internalData = internalData;
        LastRecordedReserves memory _lastRecordedReserves = lastRecordedReserves;

        // Perform an adjustment beforehand if needed.
        uint256 liquiditySupply = LP_TOKEN.totalSupply();
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(address(LP_TOKEN)).getReserves();
        if(_internalData.lpBalanceOf > 0) {
            // Check if the reserves changed enough to induce IL for an adjustment.
            uint256 targetReserve = _internalData.targetReserve == 0 ? (reserve0 * _internalData.lpBalanceOf) / liquiditySupply : (reserve1 * _internalData.lpBalanceOf) / liquiditySupply;
            uint256 targetVirtualReserve = _internalData.targetReserve == 0 ? _lastRecordedReserves.reserve0 : _lastRecordedReserves.reserve1;
            if((targetReserve * 1000) / targetVirtualReserve >= 5000) {
                // Check which way the reserve changed.
                if(targetReserve > targetVirtualReserve) {
                    // In this case, we've gained more tokens from Il.
                    // This means that we can take profit from the LP.
                    uint256 performanceFee = ((((targetReserve - _internalData.targetBalanceOf) * ((targetReserve * 1000) / targetVirtualReserve)) / 10000) * 10) / 100;
                    uint256 difference = ((targetReserve - _internalData.targetBalanceOf) / 2) - performanceFee;
                    uint256 rate = ((_internalData.lpBalanceOf * 1e18) / targetReserve);
                    uint256 burn = rate * difference;
                    LP_TOKEN.safeTransfer(address(LP_TOKEN), burn);
                    (uint256 r0Liquidity, uint256 r1Liquidity) = IUniswapV2Pair(address(LP_TOKEN)).burn(address(this));

                    // Swap other reserve for our target token.
                    (uint256 amount0Out, uint256 amount1Out) = _internalData.targetReserve == 0 ? (uint256(0), r1Liquidity) : (r0Liquidity, uint256(0));
                    IUniswapV2Pair(address(LP_TOKEN)).swap(amount0Out, amount1Out, address(this), new bytes(0));

                    _internalData.lpBalanceOf -= uint112(burn);
                    _internalData.targetBalanceOf = uint112(TARGET_TOKEN.balanceOf(address(this)));

                } else if(targetReserve < targetVirtualReserve) {
                    // In this case, we've lost tokens to IL. This means that we will 
                    // need to supply more liquidity to cover the losses made by the LP.
                    uint256 difference = (targetVirtualReserve - targetReserve) * 2;
                    uint256 toSwap = difference / 2;
                    TARGET_TOKEN.safeTransfer(address(LP_TOKEN), difference / 2);
                    (uint256 amount0Out, uint256 amount1Out) = _internalData.targetReserve == 0 ? (toSwap, uint256(0)) : (uint256(0), toSwap);
                    IUniswapV2Pair(address(LP_TOKEN)).swap(amount0Out, amount1Out, address(LP_TOKEN), new bytes(0));
                    TARGET_TOKEN.safeTransfer(address(LP_TOKEN), toSwap);
                    uint256 mint = IUniswapV2Pair(address(LP_TOKEN)).mint(address(this));
                    _require(mint > 0, Errors.INSUFFICIENT_MINT);

                    _internalData.lpBalanceOf += uint112(mint);
                    _internalData.targetBalanceOf -= uint112(difference);
                }
            }
        }

        // We have to swap the token if it is not our target reserve.
        _stack.targetTokens = _amountIn;
        if(_stack.tokenSide != _internalData.targetReserve) {
            // It is cheaper for us to do a low-level swap.
            uint256 _balanceOf = TARGET_TOKEN.balanceOf(address(this));
            _tokenIn.safeTransferFrom(msg.sender, address(LP_TOKEN), _amountIn);
            (uint256 amount0Out, uint256 amount1Out) = _stack.tokenSide == 0 ? (uint256(0), _amountIn) : (_amountIn, uint256(0));
            IUniswapV2Pair(address(LP_TOKEN)).swap(amount0Out, amount1Out, address(this), new bytes(0));
            _stack.targetTokens = TARGET_TOKEN.balanceOf(address(this)) - _balanceOf;
        }

        // Calculate and mint shares.
        uint256 __totalSupply = totalSupply();
        _stack.toMint = __totalSupply == 0
            ? _stack.targetTokens
            : (_stack.targetTokens * __totalSupply) / (_internalData.targetBalanceOf + ((_internalData.targetReserve == 0 ? _lastRecordedReserves.reserve0 : _lastRecordedReserves.reserve1) * 2));
        _mint(msg.sender, _stack.toMint);

        // Create LP position.
        if(_stack.tokenSide == _internalData.targetReserve) _tokenIn.safeTransferFrom(msg.sender, address(this), _amountIn);
        _internalData.targetBalanceOf += uint112(_stack.targetTokens / 2);

        // We need to swap half of half to the other side for the LP.
        uint256 targetIn = (_stack.targetTokens / 2) / 2;
        TARGET_TOKEN.safeTransfer(address(LP_TOKEN), targetIn);
        _stack.otherSide = _internalData.targetReserve == 0 ? token1 : token0;
        _stack.tokensOtherSide = _stack.otherSide.balanceOf(address(this));
        (uint256 amount0Out, uint256 amount1Out) = _internalData.targetReserve == 0 ? (uint256(0), targetIn) : (targetIn, uint256(0));
        IUniswapV2Pair(address(LP_TOKEN)).swap(amount0Out, amount1Out, address(this), new bytes(0));
        _stack.tokensOtherSide = _stack.otherSide.balanceOf(address(this)) - _stack.tokensOtherSide;

        // Mint liquidity.
        TARGET_TOKEN.safeTransfer(address(LP_TOKEN), targetIn);
        _stack.otherSide.safeTransfer(address(LP_TOKEN), _stack.tokensOtherSide);
        _stack.mint = uint112(IUniswapV2Pair(address(LP_TOKEN)).mint(address(this)));
        _require(_stack.mint > 0, Errors.INSUFFICIENT_MINT);

        // Write to our position.
        _internalData.lpBalanceOf += uint112(_stack.mint);
        liquiditySupply = LP_TOKEN.totalSupply();
        (reserve0, reserve1,) = IUniswapV2Pair(address(LP_TOKEN)).getReserves();
        
        _lastRecordedReserves.reserve0 = uint112((reserve0 * _internalData.lpBalanceOf) / liquiditySupply);
        _lastRecordedReserves.reserve1 = uint112((reserve1 * _internalData.lpBalanceOf) / liquiditySupply);

        internalData = _internalData;
        lastRecordedReserves = _lastRecordedReserves;

        emit LiquidityAdded(msg.sender, _amountIn, _stack.toMint);
        return _stack.toMint;
    }

    /// @notice Redeems Smart LP tokens for the LP's reserves.
    /// @param _tokensIn Smart LP tokens to redeem.
    /// @param _amountOutMin Min tokens received from the redemption.
    /// @return Output reserves from the redemption.
    function redeemLiquidity(
        uint256 _tokensIn,
        uint256 _amountOutMin
    ) external override returns (uint256) {
        RedemptionStack memory _stack;
        InternalData memory _internalData = internalData;
        LastRecordedReserves memory _lastRecordedReserves = lastRecordedReserves;

        // Perform an adjustment beforehand if needed.
        uint256 liquiditySupply = LP_TOKEN.totalSupply();
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(address(LP_TOKEN)).getReserves();
        {
            // Check if the reserves changed enough to induce IL for an adjustment.
            _stack.targetReserve = _internalData.targetReserve == 0 ? (reserve0 * _internalData.lpBalanceOf) / liquiditySupply : (reserve1 * _internalData.lpBalanceOf) / liquiditySupply;
            _stack.targetVirtualReserve = _internalData.targetReserve == 0 ? _lastRecordedReserves.reserve0 : _lastRecordedReserves.reserve1;
            if((_stack.targetReserve * 1000) / _stack.targetVirtualReserve >= 5000) {
                // Check which way the reserve changed.
                if(_stack.targetReserve > _stack.targetVirtualReserve) {
                    // In this case, we've gained more tokens from Il.
                    // This means that we can take profit from the LP.
                    uint256 performanceFee = ((((_stack.targetReserve - _internalData.targetBalanceOf) * ((_stack.targetReserve * 1000) / _stack.targetVirtualReserve)) / 10000) * 10) / 100;
                    uint256 difference = ((_stack.targetReserve - _internalData.targetBalanceOf) / 2) - performanceFee;
                    uint256 rate = ((_internalData.lpBalanceOf * 1e18) / _stack.targetReserve);
                    uint256 burn = rate * difference;
                    LP_TOKEN.safeTransfer(address(LP_TOKEN), burn);
                    (uint256 r0Liquidity, uint256 r1Liquidity) = IUniswapV2Pair(address(LP_TOKEN)).burn(address(this));

                    // Swap other reserve for our target token.
                    (uint256 amount0Out, uint256 amount1Out) = _internalData.targetReserve == 0 ? (uint256(0), r1Liquidity) : (r0Liquidity, uint256(0));
                    IUniswapV2Pair(address(LP_TOKEN)).swap(amount0Out, amount1Out, address(this), new bytes(0));

                    _internalData.lpBalanceOf -= uint112(burn);
                    _internalData.targetBalanceOf = uint112(TARGET_TOKEN.balanceOf(address(this)));

                } else if(_stack.targetReserve < _stack.targetVirtualReserve) {
                    // In this case, we've lost tokens to IL. This means that we will 
                    // need to supply more liquidity to cover the losses made by the LP.
                    uint256 difference = (_stack.targetVirtualReserve - _stack.targetReserve) * 2;
                    uint256 toSwap = difference / 2;
                    TARGET_TOKEN.safeTransfer(address(LP_TOKEN), difference / 2);
                    (uint256 amount0Out, uint256 amount1Out) = _internalData.targetReserve == 0 ? (toSwap, uint256(0)) : (uint256(0), toSwap);
                    IUniswapV2Pair(address(LP_TOKEN)).swap(amount0Out, amount1Out, address(LP_TOKEN), new bytes(0));
                    TARGET_TOKEN.safeTransfer(address(LP_TOKEN), toSwap);
                    uint256 mint = IUniswapV2Pair(address(LP_TOKEN)).mint(address(this));
                    _require(mint > 0, Errors.INSUFFICIENT_MINT);

                    _internalData.lpBalanceOf += uint112(mint);
                    _internalData.targetBalanceOf -= uint112(difference);
                }
            }
        }

        _stack.startingBalance = TARGET_TOKEN.balanceOf(address(this));
        _stack.__totalSupply = totalSupply();
        _burn(msg.sender, _tokensIn);
        _stack.totalTargetTokens = _internalData.targetBalanceOf + ((_internalData.targetReserve == 0 ? _lastRecordedReserves.reserve0 : _lastRecordedReserves.reserve1) * 2);
        uint256 targetAmount = (_stack.totalTargetTokens * _tokensIn) / _stack.__totalSupply;

        // Calculate LP tokens to burn and remove liquidity.
        _stack.lpTokensNeeded = 
            ((
                (
                    ((_internalData.targetReserve == 0 ? _lastRecordedReserves.reserve0 : _lastRecordedReserves.reserve1) * 2) * 1e18
                ) / _internalData.lpBalanceOf
            ) / (targetAmount / 2));
        LP_TOKEN.safeTransfer(address(LP_TOKEN), _stack.lpTokensNeeded);
        (uint256 r0Liquidity, uint256 r1Liquidity) = IUniswapV2Pair(address(LP_TOKEN)).burn(address(this));

        // Zap other side of the LP into the target token.
        (uint256 amount0Out, uint256 amount1Out) = _internalData.targetReserve == 0 ? (uint256(0), r1Liquidity) : (r0Liquidity, uint256(0));
        _internalData.targetReserve == 0 ? token1.safeTransfer(address(LP_TOKEN), r1Liquidity) : token0.safeTransfer(address(LP_TOKEN), r0Liquidity);
        IUniswapV2Pair(address(LP_TOKEN)).swap(amount0Out, amount1Out, address(this), new bytes(0));
        _stack.endAmount = TARGET_TOKEN.balanceOf(address(this)) - _stack.startingBalance;
        _require(_stack.endAmount >= _amountOutMin, Errors.SLIPPAGE);

        // Update stored data.
        liquiditySupply = LP_TOKEN.totalSupply();
        (reserve0, reserve1,) = IUniswapV2Pair(address(LP_TOKEN)).getReserves();

        _internalData.lpBalanceOf -= uint112(_stack.lpTokensNeeded);
        _internalData.targetBalanceOf -= uint112(targetAmount / 2);
        _lastRecordedReserves.reserve0 = uint112((reserve0 * _internalData.lpBalanceOf) / liquiditySupply);
        _lastRecordedReserves.reserve1 = uint112((reserve1 * _internalData.lpBalanceOf) / liquiditySupply);
        internalData = _internalData;
        lastRecordedReserves = _lastRecordedReserves;

        TARGET_TOKEN.safeTransfer(msg.sender, _stack.endAmount);

        emit LiquidityRedeemed(msg.sender, _tokensIn, targetAmount);
        return _stack.endAmount;
    }

    /// @notice Safer version of `redeemLiquidity` which involves no zapping.
    /// @param _tokensIn Smart LP tokens to redeem.
    /// @return Output reserves from the redemption.
    function safeRedeemLiquidity(
        uint256 _tokensIn
    ) external override returns (uint256[] memory) {
        RedemptionStack memory _stack;
        InternalData memory _internalData = internalData;
        LastRecordedReserves memory _lastRecordedReserves = lastRecordedReserves;

        // Perform an adjustment beforehand if needed.
        uint256 liquiditySupply = LP_TOKEN.totalSupply();
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(address(LP_TOKEN)).getReserves();
        {
            // Check if the reserves changed enough to induce IL for an adjustment.
            _stack.targetReserve = _internalData.targetReserve == 0 ? (reserve0 * _internalData.lpBalanceOf) / liquiditySupply : (reserve1 * _internalData.lpBalanceOf) / liquiditySupply;
            _stack.targetVirtualReserve = _internalData.targetReserve == 0 ? _lastRecordedReserves.reserve0 : _lastRecordedReserves.reserve1;
            if((_stack.targetReserve * 1000) / _stack.targetVirtualReserve >= 5000) {
                // Check which way the reserve changed.
                if(_stack.targetReserve > _stack.targetVirtualReserve) {
                    // In this case, we've gained more tokens from Il.
                    // This means that we can take profit from the LP.
                    uint256 performanceFee = ((((_stack.targetReserve - _internalData.targetBalanceOf) * ((_stack.targetReserve * 1000) / _stack.targetVirtualReserve)) / 10000) * 10) / 100;
                    uint256 difference = ((_stack.targetReserve - _internalData.targetBalanceOf) / 2) - performanceFee;
                    uint256 rate = ((_internalData.lpBalanceOf * 1e18) / _stack.targetReserve);
                    uint256 burn = rate * difference;
                    LP_TOKEN.safeTransfer(address(LP_TOKEN), burn);
                    (uint256 r0Liquidity, uint256 r1Liquidity) = IUniswapV2Pair(address(LP_TOKEN)).burn(address(this));

                    // Swap other reserve for our target token.
                    (uint256 amount0Out, uint256 amount1Out) = _internalData.targetReserve == 0 ? (uint256(0), r1Liquidity) : (r0Liquidity, uint256(0));
                    IUniswapV2Pair(address(LP_TOKEN)).swap(amount0Out, amount1Out, address(this), new bytes(0));

                    _internalData.lpBalanceOf -= uint112(burn);
                    _internalData.targetBalanceOf = uint112(TARGET_TOKEN.balanceOf(address(this)));

                } else if(_stack.targetReserve < _stack.targetVirtualReserve) {
                    // In this case, we've lost tokens to IL. This means that we will 
                    // need to supply more liquidity to cover the losses made by the LP.
                    uint256 difference = (_stack.targetVirtualReserve - _stack.targetReserve) * 2;
                    uint256 toSwap = difference / 2;
                    TARGET_TOKEN.safeTransfer(address(LP_TOKEN), difference / 2);
                    (uint256 amount0Out, uint256 amount1Out) = _internalData.targetReserve == 0 ? (toSwap, uint256(0)) : (uint256(0), toSwap);
                    IUniswapV2Pair(address(LP_TOKEN)).swap(amount0Out, amount1Out, address(LP_TOKEN), new bytes(0));
                    TARGET_TOKEN.safeTransfer(address(LP_TOKEN), toSwap);
                    uint256 mint = IUniswapV2Pair(address(LP_TOKEN)).mint(address(this));
                    _require(mint > 0, Errors.INSUFFICIENT_MINT);

                    _internalData.lpBalanceOf += uint112(mint);
                    _internalData.targetBalanceOf -= uint112(difference);
                }
            }
        }

        uint256 __totalSupply = totalSupply();
        _burn(msg.sender, _tokensIn);
        uint256 totalTargetTokens = _internalData.targetBalanceOf + ((_internalData.targetReserve == 0 ? _lastRecordedReserves.reserve0 : _lastRecordedReserves.reserve1) * 2);
        uint256 targetAmount = (totalTargetTokens * _tokensIn) / __totalSupply;

        // Calculate LP tokens to send and transfer tokens.
        uint256 lpTokensNeeded = 
            ((
                (
                    ((_internalData.targetReserve == 0 ? _lastRecordedReserves.reserve0 : _lastRecordedReserves.reserve1) * 2) * 1e18
                ) / _internalData.lpBalanceOf
            ) / (targetAmount / 2));

        // Adjust virtual state.
        liquiditySupply = LP_TOKEN.totalSupply();
        (reserve0, reserve1,) = IUniswapV2Pair(address(LP_TOKEN)).getReserves();

        _internalData.lpBalanceOf -= uint112(lpTokensNeeded);
        _internalData.targetBalanceOf -= uint112(targetAmount / 2);
        _lastRecordedReserves.reserve0 = uint112((reserve0 * _internalData.lpBalanceOf) / liquiditySupply);
        _lastRecordedReserves.reserve1 = uint112((reserve1 * _internalData.lpBalanceOf) / liquiditySupply);

        internalData = _internalData;
        lastRecordedReserves = _lastRecordedReserves;

        TARGET_TOKEN.safeTransfer(msg.sender, targetAmount / 2);
        LP_TOKEN.safeTransfer(msg.sender, lpTokensNeeded);

        uint256[] memory outputs = new uint256[](2);
        outputs[0] = targetAmount / 2;
        outputs[1] = lpTokensNeeded;

        emit LiquidityRedeemed(msg.sender, _tokensIn, targetAmount);
        return outputs;
    }

    /// @notice Calculates if a ratio adjustment is possible.
    /// @return Whether or not the Smart LP should adjust its ratio.
    function shouldAdjust() external view override returns (bool) {
        InternalData memory _internalData = internalData;
        LastRecordedReserves memory _lastRecordedReserves = lastRecordedReserves;

        uint256 liquiditySupply = LP_TOKEN.totalSupply();
        (uint256 reserve0, uint256 reserve1,) = IUniswapV2Pair(address(LP_TOKEN)).getReserves();

        // Calculate reserves for checking for an adjustment.
        uint256 targetReserve = _internalData.targetReserve == 0 ? (reserve0 * _internalData.lpBalanceOf) / liquiditySupply : (reserve1 * _internalData.lpBalanceOf) / liquiditySupply;
        uint256 targetVirtualReserve = _internalData.targetReserve == 0 ? _lastRecordedReserves.reserve0 : _lastRecordedReserves.reserve1;

        return (targetReserve * 1000) / targetVirtualReserve >= 5000;
    }

    /// @notice Calculates how much of the target token is supplied in the Smart LP.
    /// @return Total amount of tokens held in the Smart LP position.
    function totalSuppliedAssets() external view override returns (uint256) {
        return (
            internalData.targetBalanceOf
            + ((internalData.targetReserve == 0 ? lastRecordedReserves.reserve0 : lastRecordedReserves.reserve1) * 2)
        );
    }

    /// @notice Calculates the virtual (or stored) ratio of the Smart LP.
    /// @return The amount of `TARGET_TOKEN` one Smart LP token is worth.
    function virtualRatio() external view override returns (uint256) {
        uint256 unit = 10 ** IERC20Ext(address(TARGET_TOKEN)).decimals();
        uint256 _totalSuppliedAssets = internalData.targetBalanceOf
            + ((internalData.targetReserve == 0 ? lastRecordedReserves.reserve0 : lastRecordedReserves.reserve1) * 2);
        return totalSupply() == 0
            ? unit
            : (unit * _totalSuppliedAssets) / totalSupply();
    }

    /// @notice Calculates the unrealized (or current/real time) ratio of the Smart LP.
    /// @return The amount of `TARGET_TOKEN` one Smart LP token is worth based on current pair reserves.
    function unrealizedRatio() external view override returns (uint256) {
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