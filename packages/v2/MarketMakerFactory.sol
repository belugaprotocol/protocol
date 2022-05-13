// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

contract MarketMakerFactory is Clones {

    /// @notice Enum for different liquidity pools.
    enum PoolType {
        UniswapV2,
        Solidly,
        Kyberswap
    }

    /// @notice Template for a specific pool type.
    mapping(PoolType => address) public templateForPoolType;

    /// @notice Market maker vault for a specific pool.
    mapping(address => address) public marketMakerVaultForPool;

    function createNewMarket(address _pool) external returns (address) {
        address pool = clone(templateForPoolType[calculatePoolType(_pool)]);
        marketMakerVaultForPool[_pool] = pool;
    }

    function calculatePoolType() public view returns (PoolType) {
        return PoolType.UniswapV2;
    }
}