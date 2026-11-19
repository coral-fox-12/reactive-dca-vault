// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { DcaReactive } from "../src/DcaReactive.sol";

/// @notice Point DcaReactive at its executor (last step of the deploy order).
/// @dev Env: PRIVATE_KEY (deployer = reactive owner), REACTIVE_ADDRESS
///      (DcaReactive on Lasna), EXECUTOR_ADDRESS (DcaExecutor on Base Sepolia).
contract SetCallbackRecipient is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address reactiveAddr = vm.envAddress("REACTIVE_ADDRESS");
        address executor = vm.envAddress("EXECUTOR_ADDRESS");
        vm.startBroadcast(deployerKey);
        DcaReactive reactive = DcaReactive(payable(reactiveAddr));
        reactive.setCallbackRecipient(executor);
        vm.stopBroadcast();
        console.log("DcaReactive:", reactiveAddr);
        console.log("callbackRecipient set to:", reactive.callbackRecipient());
    }
}
