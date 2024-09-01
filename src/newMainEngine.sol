// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {CustomToken} from "./newCustomToken.sol";
import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {TransferHelper} from "@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
// import {UD60x18, ud, unwrap} from "@prb/math/src/UD60x18.sol";
import {console} from "forge-std/console.sol";
import {TickMath} from "@uniswap/v3-core/contracts/libraries/TickMath.sol";
import {FullMath} from "@uniswap/v3-core/contracts/libraries/FullMath.sol";
import {IWETH9} from "../test/mocks/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";

contract MainEngine is IERC721Receiver, Ownable {
    uint256 public constant MIN_CREATE_COST = 0.0001 ether;
    uint256 public constant LIQUIDITY_LOCK_PERIOD = 3 days;
    uint24 public constant poolFee = 3000; // 0.3%

    struct TokenInfo {
        address creator;
        bool isCreated;
        bool initialLiquidityAdded;
        uint256 positionId;
        uint256 lockedLiquidityPercentage;
        uint256 withdrawableLiquidity;
        uint256 creationTime;
        address pool;
        uint128 liquidity;
    }

    struct Deposit {
        address owner;
        uint128 liquidity;
        address token0;
        address token1;
    }

    mapping(address => TokenInfo) public tokenInfo;
    mapping(uint256 => Deposit) public deposits;

    IUniswapV3Factory public immutable factory;
    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    ISwapRouter public immutable swapRouter;
    IQuoterV2 public immutable quoterV2;
    address public immutable WETH9;

    event TokenCreated(
        address indexed tokenAddress,
        address indexed creator,
        string name,
        string symbol,
        uint256 initialSupply,
        uint256 lockedLiquidityPercentage
    );
    event PoolCreated(address indexed token, address indexed pool);
    event LiquidityAdded(address indexed token, address indexed provider, uint256 amount);
    event Swapped(address indexed token, address indexed user, uint256 amountIn, uint256 amountOut);
    event LiquidityWithdrawn(address indexed token, address indexed provider, uint256 amount);
    event FeesCollected(address indexed token, address indexed collector, uint256 amount0, uint256 amount1);

    error InsufficientETHSent();
    error TokenNotCreated();
    error NotAuthorized();
    error PoolAlreadyExists();
    error PoolDoesNotExist();
    error InsufficientETHProvided();
    error MustSendETH();
    error InitialLiquidityAlreadyAdded();
    error InvalidInitialSupply();
    error InvalidLockedLiquidityPercentage();
    error InsufficientWithdrawableLiquidity();
    error WithdrawalTooEarly();
    error ZeroAmountProvided();
    error ZeroLiquidityMinted();
    error MustProvidBothAmountsOrNeither();
    error MustProvideBothAmounts();
    error InvalidTokenOrder();
    error ZeroAmount();
    error SqrtPriceOutOfBounds();
    error NoLiquidityMinted();

    constructor(
        IUniswapV3Factory _factory,
        INonfungiblePositionManager _nonfungiblePositionManager,
        ISwapRouter _swapRouter,
        address _WETH9,
        IQuoterV2 _quoterV2
    ) Ownable(msg.sender) {
        factory = _factory;
        nonfungiblePositionManager = _nonfungiblePositionManager;
        swapRouter = _swapRouter;
        WETH9 = _WETH9;
        quoterV2 = _quoterV2;
    }

    modifier onlyTokenCreator(address tokenAddress) {
        if (msg.sender != tokenInfo[tokenAddress].creator) revert NotAuthorized();
        _;
    }

    modifier tokenExists(address tokenAddress) {
        if (!tokenInfo[tokenAddress].isCreated) revert TokenNotCreated();
        _;
    }

    /// @notice Creates a new token and adds initial liquidity
    /// @param name Token name
    /// @param symbol Token symbol
    /// @param description Token description
    /// @param imageUrl Token image URL
    /// @param initialSupply Initial token supply
    /// @param lockedLiquidityPercentage Percentage of liquidity to be locked
    /// @return tokenAddress The address of the newly created token
    function createTokenAndAddLiquidity(
        string memory name,
        string memory symbol,
        string memory description,
        string memory imageUrl,
        uint256 initialSupply,
        uint256 lockedLiquidityPercentage,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) external payable returns (address tokenAddress) {
        console.log("Starting createTokenAndAddLiquidity function");
        console.log("Input parameters:");
        console.log("- name:", name);
        console.log("- symbol:", symbol);
        console.log("- description:", description);
        console.log("- imageUrl:", imageUrl);
        console.log("- initialSupply:", initialSupply);
        console.log("- lockedLiquidityPercentage:", lockedLiquidityPercentage);
        console.log("- fee:", fee);
        console.log("- amount0Desired:", amount0Desired);
        console.log("- amount1Desired:", amount1Desired);
        console.log("- amount0Min:", amount0Min);
        console.log("- amount1Min:", amount1Min);
        console.log("Received ETH amount (msg.value):", msg.value);

        console.log("Checking if sufficient ETH sent");
        if (msg.value < MIN_CREATE_COST) {
            console.log("Error: Insufficient ETH sent. Required:", MIN_CREATE_COST, "Received:", msg.value);
            revert InsufficientETHSent();
        }
        console.log("Sufficient ETH sent");

        console.log("Checking initial supply");
        if (initialSupply == 0) {
            console.log("Error: Invalid initial supply");
            revert InvalidInitialSupply();
        }
        console.log("Initial supply is valid");

        console.log("Checking locked liquidity percentage");
        if (lockedLiquidityPercentage > 100) {
            console.log("Error: Invalid locked liquidity percentage:", lockedLiquidityPercentage);
            revert InvalidLockedLiquidityPercentage();
        }
        console.log("Locked liquidity percentage is valid");

        console.log("Creating token");
        tokenAddress = _createToken(name, symbol, description, imageUrl, initialSupply);
        console.log("Token created at address:", tokenAddress);

        console.log("Setting token info");
        console.log("Setting locked liquidity percentage:", lockedLiquidityPercentage);
        tokenInfo[tokenAddress].lockedLiquidityPercentage = lockedLiquidityPercentage;
        console.log("Setting creation time:", block.timestamp);
        tokenInfo[tokenAddress].creationTime = block.timestamp;

        console.log("Setting up pool for token");
        _setupPool(tokenAddress, msg.value);
        console.log("Pool setup completed");

        console.log("Adding initial liquidity");
        console.log("Parameters for _addInitialLiquidity:");
        console.log("- tokenAddress:", tokenAddress);
        console.log("- initialSupply:", initialSupply);
        console.log("- msg.value:", msg.value);
        console.log("- fee:", fee);
        console.log("- amount0Desired:", amount0Desired);
        console.log("- amount1Desired:", amount1Desired);
        console.log("- amount0Min:", amount0Min);
        console.log("- amount1Min:", amount1Min);

        _addInitialLiquidity(
            tokenAddress,
            initialSupply,
            msg.value,
            fee,
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min
        );

        console.log("Initial liquidity added successfully");
        console.log("Function execution completed");
        console.log("Returning token address:", tokenAddress);
        return tokenAddress;
    }
    /// @notice Internal function to create a new token
    /// @param name Token name
    /// @param symbol Token symbol
    /// @param description Token description
    /// @param imageUrl Token image URL
    /// @param initialSupply Initial token supply
    /// @return tokenAddress The address of the newly created token

    function _createToken(
        string memory name,
        string memory symbol,
        string memory description,
        string memory imageUrl,
        uint256 initialSupply
    ) internal returns (address tokenAddress) {
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, block.timestamp));
        tokenAddress = Create2.deploy(
            0,
            salt,
            abi.encodePacked(
                type(CustomToken).creationCode,
                abi.encode(name, symbol, description, imageUrl, address(this), initialSupply)
            )
        );

        tokenInfo[tokenAddress] = TokenInfo({
            creator: msg.sender,
            isCreated: true,
            initialLiquidityAdded: false,
            positionId: 0,
            lockedLiquidityPercentage: 0,
            withdrawableLiquidity: 0,
            creationTime: block.timestamp,
            pool: address(0),
            liquidity: 0
        });

        emit TokenCreated(
            tokenAddress, msg.sender, name, symbol, initialSupply, tokenInfo[tokenAddress].lockedLiquidityPercentage
        );

        return tokenAddress;
    }

    function _setupPool(address tokenAddress, uint256 ethAmount) internal {
        console.log("Starting _setupPool function with tokenAddress: %s and ethAmount: %s", tokenAddress, ethAmount);

        if (tokenInfo[tokenAddress].pool != address(0)) {
            console.log("Error: Pool already exists for token %s", tokenAddress);
            revert PoolAlreadyExists();
        }

        // Order tokens
        console.log("Ordering tokens...");
        (address token0, address token1) = orderTokens(tokenAddress);
        console.log("Ordered tokens: token0 = %s, token1 = %s", token0, token1);

        // Create pool
        console.log("Creating pool...");
        address pool = factory.createPool(token0, token1, poolFee);
        console.log("Pool created at address: %s", pool);
        tokenInfo[tokenAddress].pool = pool;

        // Get token balances
        console.log("Getting token balances...");
        uint256 tokenAmount = IERC20Metadata(tokenAddress).balanceOf(address(this));
        uint256 wethAmount = ethAmount; // Assuming ethAmount is in Wei
        console.log("Token balance: %s, WETH balance: %s", tokenAmount, wethAmount);

        // Get token decimals
        console.log("Getting token decimals...");
        uint8 decimals0 = IERC20Metadata(token0).decimals();
        uint8 decimals1 = IERC20Metadata(token1).decimals();
        console.log("Decimals for token0: %s, Decimals for token1: %s", decimals0, decimals1);

        // Calculate the initial sqrtPriceX96
        console.log("Calculating initial sqrtPriceX96...");
        uint160 sqrtPriceX96 = calculateInitialSqrtPrice(
            token0,
            token1,
            token0 == tokenAddress ? tokenAmount : wethAmount,
            token1 == tokenAddress ? tokenAmount : wethAmount,
            decimals0,
            decimals1
        );
        console.log("Calculated sqrtPriceX96: %s", sqrtPriceX96);

        // Initialize the pool with the calculated price
        console.log("Initializing pool...");
        IUniswapV3Pool(pool).initialize(sqrtPriceX96);
        console.log("Pool initialized successfully");

        emit PoolCreated(tokenAddress, pool);
        console.log("PoolCreated event emitted for token %s and pool %s", tokenAddress, pool);
    }

    function calculateInitialSqrtPrice(
        address token0,
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint8 decimals0,
        uint8 decimals1
    ) public view returns (uint160 sqrtPriceX96) {
        console.log("Starting calculateInitialSqrtPrice function");

        if (token0 >= token1) {
            console.log("Error: Invalid token order. token0 should be less than token1");
            revert InvalidTokenOrder();
        }
        if (amount0 == 0 || amount1 == 0) {
            console.log("Error: Zero amount detected for either amount0 or amount1");
            revert ZeroAmount();
        }

        console.log("Calculating price...");
        uint256 price = FullMath.mulDiv(amount1, 10 ** decimals0, amount0);
        console.log("Intermediate price calculation: %s", price);
        price = FullMath.mulDiv(price, 2 ** 96, 10 ** decimals1);
        console.log("Final price calculation: %s", price);

        console.log("Calculating square root of price...");
        sqrtPriceX96 = uint160(sqrt(price));
        console.log("Calculated sqrtPriceX96: %s", sqrtPriceX96);

        if (sqrtPriceX96 < TickMath.MIN_SQRT_RATIO || sqrtPriceX96 > TickMath.MAX_SQRT_RATIO) {
            console.log(
                "Error: sqrtPriceX96 out of bounds. MIN: %s, MAX: %s, Calculated: %s",
                TickMath.MIN_SQRT_RATIO,
                TickMath.MAX_SQRT_RATIO,
                sqrtPriceX96
            );
            revert SqrtPriceOutOfBounds();
        }

        console.log("calculateInitialSqrtPrice function completed successfully");
    }

    function sqrt(uint256 x) public pure returns (uint256 y) {
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
    }

    /// @notice Internal function to add initial liquidity
    /// @param tokenAddress The address of the token to add liquidity for
    /// @param tokenAmount The amount of tokens to add as liquidity
    /// @param ethAmount The amount of ETH to add as liquidity

    function _addInitialLiquidity(
        address tokenAddress,
        uint256 tokenAmount,
        uint256 ethAmount,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) internal {
        console.log("Starting _addInitialLiquidity for token:");
        console.logAddress(tokenAddress);
        console.log("Token amount: %s", tokenAmount);
        console.log("ETH amount: %s", ethAmount);

        if (tokenInfo[tokenAddress].initialLiquidityAdded) {
            console.log("Error: Initial liquidity already added for token:");
            console.logAddress(tokenAddress);
            revert InitialLiquidityAlreadyAdded();
        }
        if (tokenAmount == 0 || ethAmount == 0) {
            console.log("Error: Zero amount provided.");
            console.log("Token amount: %s, ETH amount: %s", tokenAmount, ethAmount);
            revert ZeroAmountProvided();
        }

        (address token0, address token1) = orderTokens(tokenAddress);
        console.log("Ordered tokens - Token0:");
        console.logAddress(token0);
        console.log("Token1:");
        console.logAddress(token1);

        console.log("Approving position manager to spend tokens");
        TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), amount0Desired);
        TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), amount1Desired);

        console.log("Minting position with params:");
        console.log("  Fee: %s", uint256(fee));
        // console.log("  Tick Lower: %s", int256(tickLower));
        // console.log("  Tick Upper: %s", int256(tickUpper));
        console.log("  Amount0 Desired: %s", amount0Desired);
        console.log("  Amount1 Desired: %s", amount1Desired);
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: amount0Min,
            amount1Min: amount1Min,
            recipient: address(this),
            deadline: block.timestamp
        });

        (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1) = nonfungiblePositionManager.mint(params);

        console.log("Position minted:");
        console.log("  Token ID: %s", tokenId);
        console.log("  Liquidity: %s", uint256(liquidity));
        console.log("  Amount0: %s", amount0);
        console.log("  Amount1: %s", amount1);

        if (liquidity <= 0) {
            revert NoLiquidityMinted();
        }

        console.log("Updating token info");
        tokenInfo[tokenAddress].positionId = tokenId;
        tokenInfo[tokenAddress].liquidity = liquidity;
        tokenInfo[tokenAddress].initialLiquidityAdded = true;
        tokenInfo[tokenAddress].withdrawableLiquidity =
            liquidity * (100 - tokenInfo[tokenAddress].lockedLiquidityPercentage) / 100;

        console.log("Creating deposit info");
        deposits[tokenId] = Deposit({owner: msg.sender, liquidity: liquidity, token0: token0, token1: token1});

        console.log("Emitting LiquidityAdded event");
        console.log("_addInitialLiquidity completed successfully");
    }
    /// @notice Withdraws liquidity from a token position
    /// @param tokenAddress The address of the token to withdraw liquidity from
    /// @param amount The amount of liquidity to withdraw

    function withdrawLiquidity(address tokenAddress, uint256 amount)
        external
        tokenExists(tokenAddress)
        onlyTokenCreator(tokenAddress)
    {
        if (block.timestamp < tokenInfo[tokenAddress].creationTime + LIQUIDITY_LOCK_PERIOD) revert WithdrawalTooEarly();
        if (amount > tokenInfo[tokenAddress].withdrawableLiquidity) revert InsufficientWithdrawableLiquidity();

        tokenInfo[tokenAddress].withdrawableLiquidity -= amount;

        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
            tokenId: tokenInfo[tokenAddress].positionId,
            liquidity: uint128(amount),
            amount0Min: 0,
            amount1Min: 0,
            deadline: block.timestamp
        });

        (uint256 amount0, uint256 amount1) = nonfungiblePositionManager.decreaseLiquidity(params);

        INonfungiblePositionManager.CollectParams memory collectParams = INonfungiblePositionManager.CollectParams({
            tokenId: tokenInfo[tokenAddress].positionId,
            recipient: msg.sender,
            amount0Max: uint128(amount0),
            amount1Max: uint128(amount1)
        });

        nonfungiblePositionManager.collect(collectParams);

        emit LiquidityWithdrawn(tokenAddress, msg.sender, amount);
    }

    /// @notice Collects fees for a given token position
    /// @param tokenAddress The address of the token to collect fees for
    /// @return amount0 The amount of token0 collected as fees
    /// @return amount1 The amount of token1 collected as fees
    function collectFees(address tokenAddress)
        external
        tokenExists(tokenAddress)
        onlyTokenCreator(tokenAddress)
        returns (uint256 amount0, uint256 amount1)
    {
        uint256 tokenId = tokenInfo[tokenAddress].positionId;

        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: type(uint128).max,
            amount1Max: type(uint128).max
        });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);

        uint256 totalFees = amount0 + amount1;
        uint256 systemFee = totalFees / 100; // 1% system fee
        uint256 userFee = totalFees - systemFee;

        // Transfer 99% of fees to the user
        if (amount0 > 0) {
            TransferHelper.safeTransfer(deposits[tokenId].token0, msg.sender, (amount0 * 99) / 100);
        }
        if (amount1 > 0) {
            TransferHelper.safeTransfer(deposits[tokenId].token1, msg.sender, (amount1 * 99) / 100);
        }

        emit FeesCollected(tokenAddress, msg.sender, amount0, amount1);
    }

    /// @notice Swaps exact tokens for ETH
    /// @param tokenAddress The address of the token to swap
    /// @param tokenAmount The amount of tokens to swap
    function swapExactTokensForETH(address tokenAddress, uint256 tokenAmount)
        external
        tokenExists(tokenAddress)
        returns (uint256)
    {
        TransferHelper.safeTransferFrom(tokenAddress, msg.sender, address(this), tokenAmount);
        TransferHelper.safeApprove(tokenAddress, address(swapRouter), tokenAmount);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenAddress,
            tokenOut: WETH9,
            fee: poolFee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: tokenAmount,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = swapRouter.exactInputSingle(params);
        TransferHelper.safeTransferETH(msg.sender, amountOut);

        emit Swapped(tokenAddress, msg.sender, tokenAmount, amountOut);
        return amountOut;
    }

    function swapExactETHForTokens(address tokenAddress) external payable tokenExists(tokenAddress) returns (uint256) {
        if (msg.value == 0) revert MustSendETH();
        // TransferHelper.safeTransferFrom(WETH9, msg.sender, address(this), msg.value);

        TransferHelper.safeApprove(WETH9, address(swapRouter),msg.value);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: WETH9,
            tokenOut: tokenAddress,
            fee: poolFee,
            recipient: msg.sender,
            deadline: block.timestamp,
            amountIn: msg.value,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        uint256 amountOut = swapRouter.exactInputSingle(params);
        console.log("this is hte amount out oooooooooooooooooooooooooooooooooooooooooooooooooooooooooo",amountOut);

        IERC20Metadata(tokenAddress).transfer(msg.sender, amountOut);

        emit Swapped(tokenAddress, msg.sender, msg.value, amountOut);
        return amountOut;
    }

    /// @notice Transfers funds to owner of NFT
    /// @param tokenId The id of the erc721
    /// @param amount0 The amount of token0
    /// @param amount1 The amount of token1
    function _sendToOwner(uint256 tokenId, uint256 amount0, uint256 amount1) internal {
        // Get owner of contract
        address owner = deposits[tokenId].owner;

        address token0 = deposits[tokenId].token0;
        address token1 = deposits[tokenId].token1;
        // Send collected fees to owner
        TransferHelper.safeTransfer(token0, owner, amount0);
        TransferHelper.safeTransfer(token1, owner, amount1);
    }

    function onERC721Received(address, /*operator*/ address, /*from*/ uint256, /* tokenId*/ bytes calldata)
        external
        pure
        override
        returns (bytes4)
    {
        // Here we can add any logic we want to execute when receiving an NFT
        // For now, we'll just create a deposit

        // Return the function selector to indicate successful receipt
        return this.onERC721Received.selector;
    }
    /// @notice Transfers the NFT to the owner
    /// @param tokenId The id of the erc721

    function retrieveNFT(uint256 tokenId) external {
        // Must be the owner of the NFT
        require(msg.sender == deposits[tokenId].owner, "Not the owner");
        // Transfer ownership to original owner
        nonfungiblePositionManager.safeTransferFrom(address(this), msg.sender, tokenId);
        // Remove information related to tokenId
        delete deposits[tokenId];
    }

    function getTokenPrice(address tokenAddress) external view tokenExists(tokenAddress) returns (uint256) {
        address pool = tokenInfo[tokenAddress].pool;
        if (pool == address(0)) revert PoolDoesNotExist();
        (uint160 sqrtPriceX96,,,,,,) = IUniswapV3Pool(pool).slot0();
        return uint256(sqrtPriceX96) ** 2 * 1e18 / 2 ** 192;
    }

    function orderTokens(address tokenAddress) public view returns (address token0, address token1) {
        if (tokenAddress < WETH9) {
            token0 = tokenAddress;
            token1 = WETH9;
        } else {
            token0 = WETH9;
            token1 = tokenAddress;
        }
    }

    receive() external payable {}

    ////////////////////////////////////////////////////////////////////////////
    //////// THESE ARE TEST FUNCTION...WOULD BE REMOVED BEFORE DEPLOYMENTS/////
    ///////////////////////////////////////////////////////////////////////////
    // Add this function to the MainEngine contract

    function createTokenForTest(
        string memory name,
        string memory symbol,
        string memory description,
        string memory imageUrl,
        uint256 initialSupply
    ) external returns (address tokenAddress) {
        return _createToken(name, symbol, description, imageUrl, initialSupply);
    }
    // Add this function to the MainEngine contract

    function testSetupPool(address tokenAddress) external payable {
        require(msg.value > 0, "Must send ETH to setup the pool");
        _setupPool(tokenAddress, msg.value);
    }

    function testAddInitialLiquidity(
        address tokenAddress,
        uint24 fee,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 amount0Min,
        uint256 amount1Min
    ) external payable {
        if (tokenInfo[tokenAddress].initialLiquidityAdded) {
            revert InitialLiquidityAlreadyAdded();
        }

        uint256 tokenAmount = IERC20Metadata(tokenAddress).balanceOf(address(this));

        // Call the existing _addInitialLiquidity function
        _addInitialLiquidity(
            tokenAddress,
            tokenAmount,
            msg.value,
            fee,
            tickLower,
            tickUpper,
            amount0Desired,
            amount1Desired,
            amount0Min,
            amount1Min
        );
    }

    function getPoolAddress(address tokenAddress) public view returns (address) {
        return tokenInfo[tokenAddress].pool;
    }

    function getPoolLiquidity(address tokenAddress) public view returns (uint128) {
        return tokenInfo[tokenAddress].liquidity;
    }

    function getTokenBalance(address tokenAddress, address account) public view returns (uint256) {
        return IERC20(tokenAddress).balanceOf(account);
    }

    function getPoolSlot0(address tokenAddress) public view returns (uint160 sqrtPriceX96, int24 tick) {
        address pool = getPoolAddress(tokenAddress);
        (sqrtPriceX96, tick,,,,,) = IUniswapV3Pool(pool).slot0();
    }
}
