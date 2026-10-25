// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import { BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";

contract PointsHook is BaseHook {

    mapping(address => uint256) public points;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }


function _afterSwap(
    address,                    // who called the swap: the router, not Alice (unused)
    PoolKey calldata key,       // which pool the swap happened in
    SwapParams calldata params, // direction (zeroForOne) and the amount Alice asked for
    BalanceDelta delta,         // the tab: what actually went in and out
    bytes calldata hookData     // extra bytes Alice sent: her address
) internal override returns (bytes4, int128) {
    // Not ETH in, or no user given? No points, but let the swap continue.
    bool exit = !key.currency0.isAddressZero() || !params.zeroForOne || hookData.length == 0;
    if (exit) return (BaseHook.afterSwap.selector, 0);

    uint256 ethSpent = uint256(int256(-delta.amount0())); // negative = paid in, so flip how much Eth did she spend?
    address user = abi.decode(hookData, (address));       // who to reward, who gets the points
    uint256 pointsEarned = ethSpent / 5;                  // 20% how many points: remember in solidity there are no decimals so always devide or     uint256 pointsEarned = (ethSpent * 20) / 100;

    points[user] += pointsEarned;                         // save them

    return (BaseHook.afterSwap.selector, 0);              // "ran fine"
}


}


