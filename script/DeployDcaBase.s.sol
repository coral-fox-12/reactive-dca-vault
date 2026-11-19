// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { IUniswapV2Router02 } from "v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import { DcaVault } from "../src/DcaVault.sol";
import { DcaExecutor } from "../src/DcaExecutor.sol";

/// @notice Deploy the DCA vault + executor on Base Sepolia (chain id 84532).
/// @dev Env: PRIVATE_KEY (deployer), REACTIVE_ADDRESS (DcaReactive on Lasna),
///      ROUTER_ADDRESS (Uniswap V2 router on Base Sepolia),
///      EXECUTOR_VALUE_WEI (optional funding in ETH for callback gas, default
///      0.0005 ETH — same as Pong in step 2).
///      WETH is the Base Sepolia predeploy 0x4200...0006. Slippage 500 bps (5%).
contract DeployDcaBase is Script {
    address payable internal constant BASE_SEPOLIA_PROXY =
        payable(0x476F44b11F5C942c58f4c8E3d0300E5710743585);
    address internal constant WETH_PREDEPLOY =
        0x4200000000000000000000000000000000000006;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address reactive = vm.envAddress("REACTIVE_ADDRESS");
        address router = vm.envAddress("ROUTER_ADDRESS");
        uint256 value = vm.envOr("EXECUTOR_VALUE_WEI", uint256(0.0005 ether));

        vm.startBroadcast(deployerKey);
        DcaVault vault = new DcaVault();
        console.log("DcaVault deployed at:", address(vault));

        DcaExecutor executor = new DcaExecutor{ value: value }(
            IPayable(BASE_SEPOLIA_PROXY),
            reactive,
            vault,
            IUniswapV2Router02(router),
            WETH_PREDEPLOY,
            500 // 5% slippage
        );
        console.log("DcaExecutor deployed at:", address(executor));
        console.log("callbackSender (DcaReactive):", reactive);

        vault.setExecutor(address(executor));
        console.log("vault executor set to:", vault.executor());
        vm.stopBroadcast();
    }
}
