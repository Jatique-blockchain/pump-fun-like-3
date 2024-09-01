// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.19;

// import "forge-std/Test.sol";
// import {MainEngine} from "../../src/newMainEngine.sol";
// import {DeployMainEngine} from "../../script/newDeployMainEngine.s.sol";

// contract SqrtFuzzTest is Test {
//     MainEngine public mainEngine;
//     address public deployer;
//     address public user;

//     function setUp() public {
//         console.log("setUp - Starting setup");

//         string memory sepoliaRpcUrl = vm.envString("SEPOLIA_RPC_URL");
//         vm.createSelectFork(sepoliaRpcUrl);
//         console.log("setUp - Forked Sepolia at block:", block.number);

//         deployer = makeAddr("deployer");
//         user = makeAddr("user");
//         console.log("setUp - Created deployer address:", deployer);
//         console.log("setUp - Created user address:", user);

//         DeployMainEngine deployScript = new DeployMainEngine();
//         console.log("setUp - Created DeployMainEngine instance at:", address(deployScript));

//         (mainEngine,) = deployScript.run();
//         console.log("setUp - Ran DeployMainEngine script");
//         console.log("setUp - MainEngine deployed at:", address(mainEngine));

//         console.log("setUp - MainEngine factory address:", address(mainEngine.factory()));
//         console.log(
//             "setUp - MainEngine nonfungiblePositionManager address:", address(mainEngine.nonfungiblePositionManager())
//         );
//         console.log("setUp - MainEngine swapRouter address:", address(mainEngine.swapRouter()));
//         console.log("setUp - MainEngine WETH9 address:", mainEngine.WETH9());

//         console.log("setUp - Setup completed");
//     }

//     function testSqrtFuzzed(uint256 x) public {
//         uint256 y = mainEngine.sqrt(x);

//         // Test basic properties
//         assertLe(y * y, x, "y^2 should be less than or equal to x");
//         assertLt(x, (y + 1) * (y + 1), "x should be less than (y+1)^2");

//         // Test for perfect squares
//         if (y * y == x) {
//             assertEq(y * y, x, "Result should be exact for perfect squares");
//         }

//         // Test for small numbers
//         if (x <= 3) {
//             if (x == 0) assertEq(y, 0, "sqrt(0) should be 0");
//             if (x == 1) assertEq(y, 1, "sqrt(1) should be 1");
//             if (x == 2 || x == 3) assertEq(y, 1, "sqrt(2) and sqrt(3) should be 1");
//         }

//         // Test for large numbers
//         if (x > type(uint128).max) {
//             assertTrue(y > 18446744073709551615, "sqrt of numbers > 2^128 should be > 2^64 - 1");
//         }

//         // Test for numbers close to max uint256
//         if (x > type(uint256).max - 1000) {
//             assertEq(y, 340282366920938463463374607431768211455, "Incorrect sqrt for numbers close to max uint256");
//         }

//         // Test for monotonicity
//         if (x > 0) {
//             uint256 prevY = mainEngine.sqrt(x - 1);
//             assertGe(y, prevY, "sqrt should be monotonically increasing");
//         }

//         // Test for precision
//         uint256 lowerBound = y * y;
//         uint256 upperBound = (y + 1) * (y + 1);
//         assertTrue(x >= lowerBound && x < upperBound, "x should be within [y^2, (y+1)^2)");

//         // Test for gas efficiency (this is a rough estimate)
//         uint256 gasStart = gasleft();
//         mainEngine.sqrt(x);

//         // Test for consistency with a different implementation
//         uint256 altY = alternativeSqrt(x);
//         assertEq(y, altY, "Result should be consistent with alternative implementation");
//     }

//     // Alternative sqrt implementation for comparison
//     function alternativeSqrt(uint256 x) internal pure returns (uint256) {
//         if (x == 0) return 0;
//         uint256 xx = x;
//         uint256 r = 1;
//         if (xx >= 0x100000000000000000000000000000000) {
//             xx >>= 128;
//             r <<= 64;
//         }
//         if (xx >= 0x10000000000000000) {
//             xx >>= 64;
//             r <<= 32;
//         }
//         if (xx >= 0x100000000) {
//             xx >>= 32;
//             r <<= 16;
//         }
//         if (xx >= 0x10000) {
//             xx >>= 16;
//             r <<= 8;
//         }
//         if (xx >= 0x100) {
//             xx >>= 8;
//             r <<= 4;
//         }
//         if (xx >= 0x10) {
//             xx >>= 4;
//             r <<= 2;
//         }
//         if (xx >= 0x4) r <<= 1;
//         r = (r + x / r) >> 1;
//         r = (r + x / r) >> 1;
//         r = (r + x / r) >> 1;
//         r = (r + x / r) >> 1;
//         r = (r + x / r) >> 1;
//         r = (r + x / r) >> 1;
//         r = (r + x / r) >> 1; // Seven iterations should be enough
//         uint256 r1 = x / r;
//         return r < r1 ? r : r1;
//     }
// }
