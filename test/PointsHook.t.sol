// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";
import {BaseTest} from "./utils/BaseTest.sol";
import {PointsHook} from "../src/PointsHook.sol";

contract PointsHookTest is BaseTest {
    using EasyPosm for IPositionManager;

    Currency ethCurrency = Currency.wrap(address(0)); // native ETH = address zero
    Currency tokenCurrency;                           // the token people buy
    PoolKey poolKey;
    PointsHook hook;

    // Lets this test contract receive ETH (when selling, or getting change back)
    receive() external payable {}

    function setUp() public {
        // 1. Deploy Uniswap
        deployArtifactsAndLabel();

        // 2. Get one test token. deployCurrencyPair makes two; we keep the second.
        (, tokenCurrency) = deployCurrencyPair();

        // 3. Deploy the hook at an address with only the afterSwap switch on
        address flags = address(uint160(Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144));
        deployCodeTo("PointsHook.sol:PointsHook", abi.encode(poolManager), flags);
        hook = PointsHook(flags);

        // 4. Create an ETH / token pool with our hook
        poolKey = PoolKey(ethCurrency, tokenCurrency, 3000, 60, IHooks(hook));
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // 5. Give ourselves ETH, then add full-range liquidity
        int24 tickLower = TickMath.minUsableTick(60);
        int24 tickUpper = TickMath.maxUsableTick(60);
        uint128 liquidity = 100e18;
        (uint256 amount0, uint256 amount1) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );
        vm.deal(address(this), 1000 ether);
        positionManager.mint(
            poolKey, tickLower, tickUpper, liquidity,
            amount0 + 1, amount1 + 1,
            address(this), block.timestamp, Constants.ZERO_BYTES
        );
    }

    // Buying the token with ETH, with our address in hookData → 20% points
    function test_buyWithEth_givesPoints() public {
        uint256 amountIn = 1e18;

        swapRouter.swapExactTokensForTokens{value: amountIn}({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,                    // ETH in, token out
            poolKey: poolKey,
            hookData: abi.encode(address(this)), // "reward this address"
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        assertEq(hook.points(address(this)), 2e17); // 20% of 1 ETH
    }

    // Same buy, but no hookData → no points, and the swap must still work
    function test_buyWithoutHookData_givesNoPoints() public {
        uint256 amountIn = 1e18;

        swapRouter.swapExactTokensForTokens{value: amountIn}({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,      // empty
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        assertEq(hook.points(address(this)), 0);
    }


    function test_sellToken_givesNoPoints() public{
        uint256 amountIn = 1e18;

        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: false,                    // token in, ETH out
            poolKey: poolKey,
            hookData: abi.encode(address(this)), // "reward this address"
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        assertEq(hook.points(address(this)), 0);

    }

    function testFuzz_buyWithEth_givesTwentyPercent(uint256 amountIn) public {
    // 1. Keep the random amount between 0.001 ETH and 10 ETH
    amountIn = bound(amountIn, 0.001 ether, 10 ether);

    // 2. Buy the token with that much ETH, with our address in hookData
    swapRouter.swapExactTokensForTokens{value: amountIn}({
        amountIn: amountIn,
        amountOutMin: 0,
        zeroForOne: true,
        poolKey: poolKey,
        hookData: abi.encode(address(this)),
        receiver: address(this),
        deadline: block.timestamp + 1
    });

    // 3. Points should always be exactly 20% of what we spent
    assertEq(hook.points(address(this)), amountIn/5);
}
}