// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.13;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DSTest} from "ds-test/test.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {UniswapMarketMaker} from "../markets/UniswapMarketMaker.sol";
import {IHevm} from "./utils/IHevm.sol";
import {MockToken} from "./mocks/MockToken.sol";

contract MarketMakerTest is DSTest {

    IHevm public constant HEVM = IHevm(HEVM_ADDRESS);

    MockToken public token0;

    MockToken public token1;

    IERC20 public lp;

    IUniswapV2Factory public ammFactory;

    UniswapMarketMaker public marketMaker;

    function setUp() public {
        // Deploy AMM.
        token0 = new MockToken();
        token1 = new MockToken();
        bytes memory factoryCode = abi.encodePacked(HEVM.getCode("node_modules/@uniswap/v2-core/build/UniswapV2Factory.json"), abi.encode(address(0)));
        ammFactory = IUniswapV2Factory(deployContractWithBytecode(factoryCode));

        // Create pair and deploy market maker.
        (address pair) = ammFactory.createPair(address(token0), address(token1));
        lp = IERC20(pair);
        marketMaker = new UniswapMarketMaker(lp, IERC20(address(token0)));
    }

    function testAddLiquidity() public {
        // Mint reserves.
        token0.mint(address(lp), 100e18);
        token1.mint(address(lp), 1000e18);
        IUniswapV2Pair(address(lp)).mint(address(100));

        // Perform deposit.
        (uint256 r0B, uint256 r1B) = marketMaker.lastRecordedReserves();
        token0.mint(address(1), 3e18);
        HEVM.startPrank(address(1));
        token0.approve(address(marketMaker), 3e18);
        marketMaker.addLiquidity(token0, 3e18);
        HEVM.stopPrank();
        (uint256 r0A, uint256 r1A) = marketMaker.lastRecordedReserves();
        
        // Check the state effects.
        assertGt(r0A, r0B);
        assertGt(r1A, r1B);
    }
    
    function deployContractWithBytecode(
        bytes memory _bytecode
    ) private returns (address contractAddress) {
        assembly {
            contractAddress := create(0, add(_bytecode, 0x20), mload(_bytecode))
        }
    }

}