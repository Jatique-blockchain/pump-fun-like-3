// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";
import {MainEngine} from "../../src/newMainEngine.sol";
import {DeployMainEngine} from "../../script/newDeployMainEngine.s.sol";
import {CustomToken} from "../../src/newCustomToken.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
// import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";
import {LiquidityAmounts} from "@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol";

contract MainEngineSwapTest is Test {
    MainEngine public mainEngine;
    address public deployer;
    address public user;
    address public TOKEN_ADDRESS;
    uint24 public constant FEE = 3000;
    uint256 public constant SWAP_AMOUNT = 10 ether;
    uint256 constant INITIAL_TOKEN_AMOUNT = 100000 ether; // 100,000 tokens
    uint256 constant ETH_AMOUNT = 1000 ether;
    // IQuoterV2 public quoterV2;

    function setUp() public {
        console.log("setUp - Starting setup");

        string memory sepoliaRpcUrl = vm.envString("SEPOLIA_RPC_URL");
        // vm.createSelectFork(sepoliaRpcUrl);
        console.log("setUp - Forked Sepolia at block:", block.number);

        deployer = makeAddr("deployer");
        user = makeAddr("user");
        console.log("setUp - Created deployer address:", deployer);
        console.log("setUp - Created user address:", user);
        vm.deal(deployer, 10000000000000000 ether);
        vm.deal(user, 100000000000000000000 ether);
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

        // quoterV2 = mainEngine.quoterV2(); // Uniswap V3 Quoter address
        // console.log("setUp - Quoter address:", address(quoterV2));

        console.log("setUp - Setup completed");
    }

    function createTokensAndAddLiquidity() internal returns (address) {
        console.log("createTokensAndAddLiquidity - Starting");

        vm.startPrank(deployer);

        address token = createToken("Test Token", "TST");
        console.log("createTokensAndAddLiquidity - Token created at:", token);

        vm.stopPrank();

        uint256 tokenBalance = IERC20(token).balanceOf(address(mainEngine));
        console.log("createTokensAndAddLiquidity - MainEngine token balance:", tokenBalance);


        console.log("createTokensAndAddLiquidity - Completed");
        return token;
    }

    function nearestUsableTick(int24 tick, int24 tickSpacing) public pure returns (int24) {
        require(tickSpacing > 0, "TICK_SPACING");
        require(tick >= TickMath.MIN_TICK && tick <= TickMath.MAX_TICK, "TICK_BOUND");

        int24 rounded = tick / tickSpacing * tickSpacing;
        if (tick < 0 && tick % tickSpacing != 0) rounded -= tickSpacing;
        return rounded;
    }

    function createToken(string memory name, string memory symbol) internal returns (address) {
        console.log("createToken - Creating token:", name);
        uint256 lockedLiquidityPercentage = 50; // 50%
        uint24 fee = 3000; // 0.3%
        string memory description = "A test token";
        string memory imageUrl = "https://example.com/image.png";
        uint256 initialSupply = INITIAL_TOKEN_AMOUNT;
        // int24 tickLower = -273496;
        // int24 tickUpper = 273496;
        int24 tickLower = -2734;
        int24 tickUpper = 2734;
        uint256 amount0Desired = INITIAL_TOKEN_AMOUNT;
        uint256 amount1Desired = ETH_AMOUNT;
        uint256 amount0Min = 0 ether;
        uint256 amount1Min = 0 ether;
        tickLower = nearestUsableTick(tickLower, 60);
        tickUpper = nearestUsableTick(tickUpper, 60);

        console.log("createToken - Calling createTokenAndAddLiquidity");
        address tokenAddr = mainEngine.createTokenAndAddLiquidity{value: ETH_AMOUNT}(
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

        console.log("createToken - Token created at:", tokenAddr);

        assertTrue(tokenAddr != address(0), "Token creation failed");

        (, bool isCreated, bool initialLiquidityAdded,,,,, address pool,) = mainEngine.tokenInfo(tokenAddr);
        assertTrue(isCreated, "Token not marked as created");
        assertTrue(initialLiquidityAdded, "Initial liquidity not added");
        assertTrue(pool != address(0), "Pool not created");

        console.log("createToken - Token info:");
        console.log("  Is created:", isCreated);
        console.log("  Initial liquidity added:", initialLiquidityAdded);
        console.log("  Pool address:", pool);

        return tokenAddr;
    }

    function testSwapExactETHForTokensAndBack() public {
        console.log("testSwapExactETHForTokensAndBack - Starting test");

        TOKEN_ADDRESS = createTokensAndAddLiquidity();

        vm.startPrank(user);
        console.log("testSwapExactETHForTokensAndBack - Switched to user:", user);

        uint256 initialETHBalance = user.balance;
        console.log("testSwapExactETHForTokensAndBack - Initial ETH balance:", initialETHBalance);
        IERC20(mainEngine.WETH9()).approve(address(mainEngine), SWAP_AMOUNT);

        uint256 initialTokenBalance = mainEngine.getTokenBalance(TOKEN_ADDRESS, user);
        console.log("testSwapExactETHForTokensAndBack - Initial token balance:", initialTokenBalance);

        console.log("testSwapExactETHForTokensAndBack - Initial pool state:");
        logPoolInfo();

        // // Quote the swap using QuoterV2
        // (uint256 quoteAmountOut, uint160 sqrtPriceX96After_, uint32 initializedTicksCrossed_, uint256 gasEstimate_) =
        // quoterV2.quoteExactInputSingle(
        //     IQuoterV2.QuoteExactInputSingleParams({
        //         tokenIn: mainEngine.WETH9(),
        //         tokenOut: TOKEN_ADDRESS,
        //         fee: FEE,
        //         amountIn: SWAP_AMOUNT,
        //         sqrtPriceLimitX96: 0
        //     })
        // );
        // console.log("testSwapExactETHForTokensAndBack - Quoted amount out:", quoteAmountOut);
        // console.log("testSwapExactETHForTokensAndBack - Quoted sqrtPriceX96After:", sqrtPriceX96After_);
        // console.log("testSwapExactETHForTokensAndBack - Quoted initializedTicksCrossed:", initializedTicksCrossed_);
        // console.log("testSwapExactETHForTokensAndBack - Quoted gasEstimate:", gasEstimate_);
        logPoolInfo();
        console.log("testSwapExactETHForTokensAndBack - Swapping ETH for tokens");
        uint256 tokensReceived = mainEngine.swapExactETHForTokens{value: SWAP_AMOUNT}(TOKEN_ADDRESS);
        console.log("testSwapExactETHForTokensAndBack - Tokens received:", tokensReceived);

        uint256 postSwapETHBalance = user.balance;
        console.log("testSwapExactETHForTokensAndBack - Post-swap ETH balance:", postSwapETHBalance);

        uint256 postSwapTokenBalance = mainEngine.getTokenBalance(TOKEN_ADDRESS, user);
        console.log("testSwapExactETHForTokensAndBack - Post-swap token balance:", postSwapTokenBalance);

        assertLt(postSwapETHBalance, initialETHBalance, "ETH balance should decrease");
        assertGt(postSwapTokenBalance, initialTokenBalance, "Token balance should increase");
        assertEq(postSwapTokenBalance, tokensReceived, "Tokens received should match balance increase");
        // assertApproxEqRel(tokensReceived, quoteAmountOut, 1e16, "Received amount should be close to quoted amount");

        console.log("testSwapExactETHForTokensAndBack - Pool state after ETH to Token swap:");
        logPoolInfo();

        // // Quote the swap back using QuoterV2
        // (uint256 amountIn, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed, uint256 gasEstimate) = quoterV2
        //     .quoteExactOutputSingle(
        //     IQuoterV2.QuoteExactOutputSingleParams({
        //         tokenIn: TOKEN_ADDRESS,
        //         tokenOut: mainEngine.WETH9(),
        //         fee: FEE,
        //         amount: SWAP_AMOUNT,
        //         sqrtPriceLimitX96: 0
        //     })
        // );
        // console.log("testSwapExactETHForTokensAndBack - Quoted amount in for swap back:", amountIn);
        // console.log("testSwapExactETHForTokensAndBack - Quoted sqrtPriceX96After:", sqrtPriceX96After);
        // console.log("testSwapExactETHForTokensAndBack - Quoted initializedTicksCrossed:", initializedTicksCrossed);
        // console.log("testSwapExactETHForTokensAndBack - Quoted gasEstimate:", gasEstimate);

        console.log("testSwapExactETHForTokensAndBack - Approving tokens for swap");
        IERC20(TOKEN_ADDRESS).approve(address(mainEngine), postSwapTokenBalance);

        console.log("testSwapExactETHForTokensAndBack - Swapping tokens back to ETH");
        uint256 ethReceived = mainEngine.swapExactTokensForETH(TOKEN_ADDRESS, postSwapTokenBalance);
        console.log("testSwapExactETHForTokensAndBack - ETH received:", ethReceived);

        uint256 finalETHBalance = user.balance;
        console.log("testSwapExactETHForTokensAndBack - Final ETH balance:", finalETHBalance);

        uint256 finalTokenBalance = mainEngine.getTokenBalance(TOKEN_ADDRESS, user);
        console.log("testSwapExactETHForTokensAndBack - Final token balance:", finalTokenBalance);

        assertGt(finalETHBalance, postSwapETHBalance, "ETH balance should increase");
        assertLt(finalTokenBalance, postSwapTokenBalance, "Token balance should decrease");
        assertEq(finalTokenBalance, 0, "All tokens should be swapped back");
        assertEq(
            finalETHBalance, postSwapETHBalance + ethReceived, "ETH balance should increase by the amount received"
        );

        assertApproxEqRel(ethReceived, SWAP_AMOUNT, 1e16, "Received ETH should be close to initial swap amount");
        // assertApproxEqRel(ethReceived, amountIn, 1e16, "Received ETH should be close to quoted amount");

        console.log("testSwapExactETHForTokensAndBack - Final pool state:");
        logPoolInfo();

        vm.stopPrank();
        console.log("testSwapExactETHForTokensAndBack - Test completed");
    }

    function logPoolInfo() internal view {
        console.log("///////////////////////////////////////////////////////////////////////////////////");

        address poolAddress = mainEngine.getPoolAddress(TOKEN_ADDRESS);
        console.log("Pool address:", poolAddress);
        getPoolAmounts(poolAddress);
        uint128 poolLiquidity = mainEngine.getPoolLiquidity(TOKEN_ADDRESS);
        console.log("Pool liquidity:", poolLiquidity);

        (uint160 sqrtPriceX96, int24 tick) = mainEngine.getPoolSlot0(TOKEN_ADDRESS);
        console.log("Pool sqrtPriceX96:", sqrtPriceX96);

        uint256 tokenPrice = mainEngine.getTokenPrice(TOKEN_ADDRESS);
        console.log("Token price:", tokenPrice);

        (uint256 amount0, uint256 amount1) = getPoolAmounts(poolAddress);
        console.log("Pool token0 amount:", amount0);
        console.log("Pool token1 amount:", amount1);
    }

    function getPoolAmounts(address poolAddress) internal view returns (uint256 amount0, uint256 amount1) {
        console.log("getPoolAmounts: Starting function");
        console.log("getPoolAmounts: poolAddress", poolAddress);

        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);
        console.log("getPoolAmounts: pool address", address(pool));

        (uint160 sqrtPriceX96, int24 tick,,,,,) = pool.slot0();
        console.log("getPoolAmounts: sqrtPriceX96", sqrtPriceX96);
        console.logInt(int256(tick)); // Using logInt for int24

        uint128 liquidity = pool.liquidity();
        console.log("getPoolAmounts: liquidity", uint256(liquidity)); // Cast to uint256 for logging

        uint160 sqrtRatioAX96 = TickMath.getSqrtRatioAtTick(tick - 1);
        console.log("getPoolAmounts: sqrtRatioAX96", sqrtRatioAX96);

        uint160 sqrtRatioBX96 = TickMath.getSqrtRatioAtTick(tick + 1);
        console.log("getPoolAmounts: sqrtRatioBX96", sqrtRatioBX96);

        (amount0, amount1) =
            LiquidityAmounts.getAmountsForLiquidity(sqrtPriceX96, sqrtRatioAX96, sqrtRatioBX96, liquidity);

        console.log("getPoolAmounts: amount0", amount0);
        console.log("getPoolAmounts: amount1", amount1);
        console.log("getPoolAmounts: Function completed");
        console.log("////////////////////////////////////////////////////////////////////////////////////");
    }

    function testSwapExactTokensForETH() public {
        console.log("testSwapExactTokensForETH - Starting test");

        // Create tokens and add liquidity
        TOKEN_ADDRESS = createTokensAndAddLiquidity();

        vm.startPrank(user);
        console.log("testSwapExactTokensForETH - Switched to user:", user);

        // Mint tokens for the user
        uint256 mintAmount = 1 ether; // Amount of tokens to mint
        CustomToken(TOKEN_ADDRESS).mint(user, mintAmount);

        uint256 initialETHBalance = user.balance;
        console.log("testSwapExactTokensForETH - Initial ETH balance:", initialETHBalance);

        uint256 initialTokenBalance = IERC20(TOKEN_ADDRESS).balanceOf(user);
        console.log("testSwapExactTokensForETH - Initial token balance:", initialTokenBalance);

        console.log("testSwapExactTokensForETH - Initial pool state:");
        logPoolInfo();

        // Approve the MainEngine contract to spend tokens
        IERC20(TOKEN_ADDRESS).approve(address(mainEngine), mintAmount);

        // Perform the swap
        console.log("testSwapExactTokensForETH - Swapping tokens for ETH");
        uint256 ethReceived = mainEngine.swapExactTokensForETH(TOKEN_ADDRESS, mintAmount);

        console.log("testSwapExactTokensForETH - ETH received:", ethReceived);

        uint256 finalETHBalance = user.balance;
        console.log("testSwapExactTokensForETH - Final ETH balance:", finalETHBalance);

        uint256 finalTokenBalance = IERC20(TOKEN_ADDRESS).balanceOf(user);
        console.log("testSwapExactTokensForETH - Final token balance:", finalTokenBalance);

        // Assertions
        assertGt(finalETHBalance, initialETHBalance, "ETH balance should increase");
        assertLt(finalTokenBalance, initialTokenBalance, "Token balance should decrease");
        assertEq(finalTokenBalance, 0, "All tokens should be swapped");
        assertEq(finalETHBalance, initialETHBalance + ethReceived, "ETH balance should increase by the amount received");

        console.log("testSwapExactTokensForETH - Final pool state:");
        logPoolInfo();

        vm.stopPrank();
        console.log("testSwapExactTokensForETH - Test completed");
    }
}
