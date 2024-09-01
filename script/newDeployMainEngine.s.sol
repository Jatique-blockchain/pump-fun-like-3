// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {MainEngine} from "../src/newMainEngine.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {INonfungiblePositionManager} from "@uniswap/v3-periphery/contracts/interfaces/INonfungiblePositionManager.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {IWETH9} from "../test/mocks/IWETH.sol";
import {IQuoterV2} from "@uniswap/v3-periphery/contracts/interfaces/IQuoterV2.sol";

contract DeployMainEngine is Script {
    struct DeploymentInfo {
        address factory;
        address nonfungiblePositionManager;
        address swapRouter;
        address WETH9;
        address quoterV2;
        address tokenDescriptor;
        uint256 chainId;
    }

    DeploymentInfo public info;

    function run() external returns (MainEngine, DeploymentInfo memory) {
        //console.log("Starting DeployMainEngine script");

        info.chainId = block.chainid;
        //console.log("Chain ID:", info.chainId);

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        //console.log("Using private key from .env file");

        vm.startBroadcast(deployerPrivateKey);

        setAddressesFromEnv();

        MainEngine mainEngine = new MainEngine(
            IUniswapV3Factory(info.factory),
            INonfungiblePositionManager(info.nonfungiblePositionManager),
            ISwapRouter(info.swapRouter),
            info.WETH9,
            IQuoterV2(info.quoterV2)
        );
        //console.log("MainEngine deployed at:", address(mainEngine));

        vm.stopBroadcast();
        //console.log("DeployMainEngine script completed");
        return (mainEngine, info);
    }

    function setAddressesFromEnv() internal {
        info.factory = vm.envAddress("UNISWAP_V3_FACTORY");
        info.nonfungiblePositionManager = vm.envAddress("NONFUNGIBLE_POSITION_MANAGER");
        info.swapRouter = vm.envAddress("SWAP_ROUTER");
        info.WETH9 = vm.envAddress("WETH9");
        info.tokenDescriptor = vm.envAddress("TOKEN_DESCRIPTOR");
        info.quoterV2 = vm.envAddress("QUOTER_ADDRESS");
    }
}
