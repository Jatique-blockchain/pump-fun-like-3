// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {MainEngine} from "../../src/newMainEngine.sol";
import {CustomToken} from "../../src/newCustomToken.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {DeployMainEngine} from "../../script/newDeployMainEngine.s.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";

contract MainEngineTest is Test {
    MainEngine public mainEngine;
    address public user;
    uint256 constant INITIAL_ETH = 0.1 ether;
    uint256 constant MIN_CREATE_COST = 0.0001 ether;
    address public deployer;
    uint256 constant INITIAL_TOKEN_AMOUNT = 1000 ether; // 1000 tokens
    uint256 constant ETH_AMOUNT = 0.1 ether;

    function setUp() public {
        console.log("setUp - Starting setup");

        string memory sepoliaRpcUrl = vm.envString("SEPOLIA_RPC_URL");
        vm.createSelectFork(sepoliaRpcUrl);
        console.log("setUp - Forked Sepolia at block:", block.number);

        deployer = makeAddr("deployer");
        user = makeAddr("user");
        console.log("setUp - Created deployer address:", deployer);
        console.log("setUp - Created user address:", user);

        DeployMainEngine deployScript = new DeployMainEngine();
        console.log("setUp - Created DeployMainEngine instance at:", address(deployScript));

        (mainEngine,) = deployScript.run();
        console.log("setUp - Ran DeployMainEngine script");
        console.log("setUp - MainEngine deployed at:", address(mainEngine));

        console.log("setUp - MainEngine factory address:", address(mainEngine.factory()));
        console.log(
            "setUp - MainEngine nonfungiblePositionManager address:", address(mainEngine.nonfungiblePositionManager())
        );
        console.log("setUp - MainEngine swapRouter address:", address(mainEngine.swapRouter()));
        console.log("setUp - MainEngine WETH9 address:", mainEngine.WETH9());

        console.log("setUp - Setup completed");
    }

    function nearestUsableTick(int24 tick, int24 tickSpacing) public pure returns (int24) {
        require(tickSpacing > 0, "TICK_SPACING");
        require(tick >= TickMath.MIN_TICK && tick <= TickMath.MAX_TICK, "TICK_BOUND");

        int24 rounded = tick / tickSpacing * tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) rounded -= tickSpacing;
        return rounded;
    }

    function testCreateTokenAndAddLiquidity() public {
        console.log("testCreateTokenAndAddLiquidity - Starting test");
        vm.startPrank(user);
        console.log("testCreateTokenAndAddLiquidity - Started pranking as user:", user);

        string memory name = "Test Token";
        string memory symbol = "TST";
        string memory description = "A test token";
        string memory imageUrl = "https://example.com/image.png";
        uint256 initialSupply = INITIAL_TOKEN_AMOUNT;
        uint256 lockedLiquidityPercentage = 50; // 50%
        uint24 fee = 3000; // 0.3%
        int24 tickLower = -273496;
        int24 tickUpper = 273496;
        uint256 amount0Desired = INITIAL_TOKEN_AMOUNT;
        uint256 amount1Desired = ETH_AMOUNT;
        uint256 amount0Min = 0 ether;
        uint256 amount1Min = 0 ether;
        tickLower = nearestUsableTick(tickLower, 60);
        tickUpper = nearestUsableTick(tickUpper, 60);

        console.log("testCreateTokenAndAddLiquidity - Calling createTokenAndAddLiquidity");
        address tokenAddress = mainEngine.createTokenAndAddLiquidity{value: ETH_AMOUNT}(
            name,
            symbol,
            description,
            imageUrl,
            initialSupply,
            lockedLiquidityPercentage,
            fee,
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min
        );
        console.log("testCreateTokenAndAddLiquidity - Token created at address:", tokenAddress);

        console.log("testCreateTokenAndAddLiquidity - Verifying token creation");
        CustomToken token = CustomToken(tokenAddress);
        assertEq(token.name(), name, "Token name mismatch");
        assertEq(token.symbol(), symbol, "Token symbol mismatch");
        assertEq(token.totalSupply(), initialSupply, "Initial supply mismatch");

        console.log("testCreateTokenAndAddLiquidity - Verifying token info");
        (
            address creator,
            bool isCreated,
            bool initialLiquidityAdded,
            uint256 positionId,
            uint256 storedLockedLiquidityPercentage,
            uint256 withdrawableLiquidity,
            uint256 creationTime,
            address poolAddress,
            uint128 liquidity
        ) = mainEngine.tokenInfo(tokenAddress);

        console.log("testCreateTokenAndAddLiquidity - Creator:", creator);
        console.log("testCreateTokenAndAddLiquidity - Is created:", isCreated);
        console.log("testCreateTokenAndAddLiquidity - Initial liquidity added:", initialLiquidityAdded);
        console.log("testCreateTokenAndAddLiquidity - Position ID:", positionId);
        console.log("testCreateTokenAndAddLiquidity - Locked liquidity percentage:", storedLockedLiquidityPercentage);
        console.log("testCreateTokenAndAddLiquidity - Withdrawable liquidity:", withdrawableLiquidity);
        console.log("testCreateTokenAndAddLiquidity - Creation time:", creationTime);
        console.log("testCreateTokenAndAddLiquidity - Pool address:", poolAddress);
        console.log("testCreateTokenAndAddLiquidity - Liquidity:", liquidity);

        assertEq(creator, user, "Creator mismatch");
        assertTrue(isCreated, "Token not marked as created");
        assertTrue(initialLiquidityAdded, "Initial liquidity not added");
        assertGt(positionId, 0, "Invalid position ID");
        assertEq(storedLockedLiquidityPercentage, lockedLiquidityPercentage, "Locked liquidity percentage mismatch");
        assertGt(withdrawableLiquidity, 0, "No withdrawable liquidity");
        assertEq(creationTime, block.timestamp, "Creation time mismatch");
        assertTrue(poolAddress != address(0), "Pool not created");
        assertGt(liquidity, 0, "No liquidity added");

        console.log("testCreateTokenAndAddLiquidity - Verifying pool setup");
        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        assertEq(pool.fee(), fee, "Pool fee mismatch");

        console.log("testCreateTokenAndAddLiquidity - Verifying liquidity position");
        INonfungiblePositionManager positionManager = mainEngine.nonfungiblePositionManager();
        (
            ,
            ,
            address token0,
            address token1,
            uint24 positionFee,
            int24 positionTickLower,
            int24 positionTickUpper,
            uint128 positionLiquidity,
            ,
            ,
            ,
        ) = positionManager.positions(positionId);

        console.log("testCreateTokenAndAddLiquidity - Token0:", token0);
        console.log("testCreateTokenAndAddLiquidity - Token1:", token1);
        console.log("testCreateTokenAndAddLiquidity - Position fee:", positionFee);
        console.log("testCreateTokenAndAddLiquidity - Position liquidity:", positionLiquidity);

        assertTrue(token0 < token1, "Tokens not sorted");
        assertTrue(token0 == tokenAddress || token1 == tokenAddress, "Token not in position");
        assertEq(positionFee, fee, "Position fee mismatch");
        assertEq(positionTickLower, tickLower, "Lower tick mismatch");
        assertEq(positionTickUpper, tickUpper, "Upper tick mismatch");
        assertGt(positionLiquidity, 0, "No liquidity in position");

        vm.stopPrank();
        console.log("testCreateTokenAndAddLiquidity - Test completed");
    }

    function testCreateTokenAndAddLiquidityInsufficientETH() public {
        console.log("testCreateTokenAndAddLiquidityInsufficientETH - Starting test");
        vm.startPrank(user);

        console.log("testCreateTokenAndAddLiquidityInsufficientETH - Expecting revert");
        vm.expectRevert(MainEngine.InsufficientETHSent.selector);
        mainEngine.createTokenAndAddLiquidity{value: MIN_CREATE_COST - 1}(
            "Test", "TST", "Description", "ImageURL", 1000, 50, 3000, -887220, 887220, 1000, 1, 990, 0
        );

        vm.stopPrank();
        console.log("testCreateTokenAndAddLiquidityInsufficientETH - Test completed");
    }

    function testCreateTokenAndAddLiquidityInvalidInitialSupply() public {
        console.log("testCreateTokenAndAddLiquidityInvalidInitialSupply - Starting test");
        vm.startPrank(user);

        console.log("testCreateTokenAndAddLiquidityInvalidInitialSupply - Expecting revert");
        vm.expectRevert(MainEngine.InvalidInitialSupply.selector);
        mainEngine.createTokenAndAddLiquidity{value: 1 ether}(
            "Test", "TST", "Description", "ImageURL", 0, 50, 3000, -887220, 887220, 1000, 1, 990, 0
        );

        vm.stopPrank();
        console.log("testCreateTokenAndAddLiquidityInvalidInitialSupply - Test completed");
    }

    function testCreateTokenAndAddLiquidityInvalidLockedPercentage() public {
        console.log("testCreateTokenAndAddLiquidityInvalidLockedPercentage - Starting test");
        vm.startPrank(user);

        console.log("testCreateTokenAndAddLiquidityInvalidLockedPercentage - Expecting revert");
        vm.expectRevert(MainEngine.InvalidLockedLiquidityPercentage.selector);
        mainEngine.createTokenAndAddLiquidity{value: 1 ether}(
            "Test", "TST", "Description", "ImageURL", 1000, 101, 3000, -887220, 887220, 1000, 1, 990, 0
        );

        vm.stopPrank();
        console.log("testCreateTokenAndAddLiquidityInvalidLockedPercentage - Test completed");
    }
}
