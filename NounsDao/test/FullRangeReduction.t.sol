// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {GasSnapshot} from "forge-gas-snapshot/GasSnapshot.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {FeeReducerHook} from "../contracts/FeeReducerHook.sol";
import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {FullRangeFeeImplementation} from "./shared/implementation/FullRangeFeeImplementation.sol";
import {Deployers} from "@uniswap/v4-core/test/utils/Deployers.sol";
import {MockERC20} from "solmate/test/utils/mocks/MockERC20.sol";
import {MockERC721} from "solmate/test/utils/mocks/MockERC721.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {FullRange} from "../contracts/FullRange.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {HookEnabledSwapRouter} from "./utils/HookEnabledSwapRouter.sol";

contract TestFeeReducerHook is Test, Deployers, GasSnapshot {
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;

    int24 constant TICK_SPACING = 60;

    FeeReducerHook discountFullRange;
    HookEnabledSwapRouter router;
    MockERC20 token0;
    MockERC20 token1;
    MockERC20 token2;
    MockERC721 nftToken;
    PoolId id;
    PoolKey key2;
    PoolId id2;
    FullRangeFeeImplementation fullRangeFee = FullRangeFeeImplementation(
        address(uint160(Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_SWAP_FLAG))
    );

    // For a pool that gets initialized with liquidity in setUp()
    PoolKey keyWithLiq;
    PoolId idWithLiq;

    function setUp() public {
        deployFreshManagerAndRouters();
        router = new HookEnabledSwapRouter(manager);
        MockERC20[] memory tokens = deployTokens(3, 2 ** 128);
        token0 = tokens[0];
        token1 = tokens[1];
        token2 = tokens[2];

        nftToken = new MockERC721("NFT Token", "NFT");
        FullRangeFeeImplementation impl = new FullRangeFeeImplementation(manager, fullRangeFee);
        vm.etch(address(fullRangeFee), address(impl).code);

        key = createPoolKey(token0, token1);
        id = key.toId();

        key2 = createPoolKey(token1, token2);
        id2 = key.toId();

        keyWithLiq = createPoolKey(token0, token2);
        idWithLiq = keyWithLiq.toId();

        token0.approve(address(fullRangeFee), type(uint256).max);
        token1.approve(address(fullRangeFee), type(uint256).max);
        token2.approve(address(fullRangeFee), type(uint256).max);
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        token2.approve(address(router), type(uint256).max);
        
        
        initPool(keyWithLiq.currency0, keyWithLiq.currency1, fullRangeFee, 3000, SQRT_PRICE_1_1, ZERO_BYTES);
        fullRangeFee.addLiquidity(
            FeeReducerHook.AddLiquidityParams(
                keyWithLiq.currency0,
                keyWithLiq.currency1,
                3000,
                100 ether,
                100 ether,
                99 ether,
                99 ether,
                address(this),
                block.timestamp + 1000
            )
        );
    }

    function testSwapWithDiscount() public {
        // Mint an NFT to the test contract
        nftToken.mint(address(this), 1);

        uint256 balanceBefore = token0.balanceOf(address(this));

        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 1 ether,
            sqrtPriceLimitX96: SQRT_PRICE_1_2
        });

        HookEnabledSwapRouter.TestSettings memory settings = HookEnabledSwapRouter.TestSettings({
            takeClaims: false,
            settleUsingBurn: false
        });

        router.swap(key, params, settings, ZERO_BYTES);

        uint256 balanceAfter = token0.balanceOf(address(this));
        uint256 amountSpent = balanceBefore - balanceAfter;

        // Calculate the expected fee (0.15% instead of 0.3%)
        uint256 expectedFee = (1 ether * 15) / 10000;

        // Assert that the amount spent is close to 1 ether + expected fee
        assertApproxEqRel(amountSpent, 1 ether + expectedFee, 1e16); // 1% tolerance
    }

    function testFullRange_beforeInitialize_AllowsPoolCreation() public {
        PoolKey memory testKey = key;

        vm.expectEmit(true, true, true, true);
        
        snapStart("FullRangeInitialize");
        manager.initialize(testKey, SQRT_PRICE_1_1, ZERO_BYTES);
        snapEnd();

        (, address liquidityToken) = fullRangeFee.poolInfo(id);

        assertFalse(liquidityToken == address(0));
    }


    function createPoolKey(MockERC20 tokenA, MockERC20 tokenB) internal view returns (PoolKey memory) {
        if (address(tokenA) > address(tokenB)) (tokenA, tokenB) = (tokenB, tokenA);
        return PoolKey(Currency.wrap(address(tokenA)), Currency.wrap(address(tokenB)), 3000, TICK_SPACING, fullRangeFee);
    }
}