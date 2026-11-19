// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { DcaToken } from "../src/DcaToken.sol";

/// @notice Minimal interfaces for the precompiled Uniswap V2 artifacts
///         (0.5.16 factory / 0.6.6 router — deployed via vm.deployCode).
interface IV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

interface IV2Router {
    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external payable returns (uint256 amountToken, uint256 amountETH, uint256 liquidity);
}

/// @notice Deploy our own Uniswap V2 stack on Base Sepolia (chain id 84532):
///         factory + router + DcaToken, create the WETH/DCAT pair and seed it
///         with testnet liquidity. No usable V2 pair exists on Base Sepolia
///         (probed 19/11 — mainnet factories have no code here), so we deploy
///         our own. Uses the WETH predeploy 0x4200...0006, NOT a local WETH9.
/// @dev Env: PRIVATE_KEY (deployer). Liquidity: 0.001 ETH + 10,000 DCAT
///      (same 1 DCAT = 0.0001 ETH ratio as the local tests).
contract DeployV2 is Script {
    address internal constant WETH_PREDEPLOY =
        0x4200000000000000000000000000000000000006;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerKey);
        (address factoryAddr, address routerAddr, address token, address pair) =
            _deployStack(deployerKey);
        _seedLiquidity(routerAddr, token, deployerKey);
        vm.stopBroadcast();
        console.log("UniswapV2Factory:", factoryAddr);
        console.log("UniswapV2Router02:", routerAddr);
        console.log("DcaToken:", token);
        console.log("WETH/DCAT pair:", pair);
    }

    function _deployStack(uint256 deployerKey)
        internal
        returns (address factoryAddr, address routerAddr, address token, address pair)
    {
        factoryAddr = vm.deployCode(
            "artifacts-v2/UniswapV2Factory.json",
            abi.encode(vm.addr(deployerKey))
        );
        routerAddr = vm.deployCode(
            "artifacts-v2/UniswapV2Router02.json",
            abi.encode(factoryAddr, WETH_PREDEPLOY)
        );
        token = address(new DcaToken());
        pair = IV2Factory(factoryAddr).createPair(token, WETH_PREDEPLOY);
    }

    function _seedLiquidity(address routerAddr, address token, uint256 deployerKey)
        internal
    {
        DcaToken(token).approve(routerAddr, 10_000 ether);
        (uint256 amountToken, uint256 amountETH, uint256 liquidity) =
            IV2Router(routerAddr).addLiquidityETH{ value: 0.001 ether }(
                token,
                10_000 ether,
                0,
                0,
                vm.addr(deployerKey),
                block.timestamp + 600
            );
        console.log("liquidity seeded: token", amountToken);
        console.log("liquidity seeded: ETH", amountETH);
        console.log("liquidity seeded: LP", liquidity);
    }
}
