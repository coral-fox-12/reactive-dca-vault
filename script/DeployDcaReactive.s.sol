// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { DcaReactive } from "../src/DcaReactive.sol";

/// @notice Deploy DcaReactive on Lasna testnet (chain id 5318007).
/// @dev Env: PRIVATE_KEY (deployer), REACTIVE_VALUE_WEI (optional funding in
///      lREACT for tick/debt coverage, default 0).
///      Destination chain id is Base Sepolia (84532). CRON: Cron100.
///      Deploy order: this FIRST — the executor on Base Sepolia takes this
///      contract's address in its constructor.
contract DeployDcaReactive is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        uint256 value = vm.envOr("REACTIVE_VALUE_WEI", uint256(0));
        vm.startBroadcast(deployerKey);
        DcaReactive reactive = new DcaReactive{ value: value }(84532);
        vm.stopBroadcast();
        console.log("DcaReactive deployed at:", address(reactive));
        console.log("destinationChainId:", reactive.destinationChainId());
        console.log("owner:", reactive.owner());
        console.log("tickCount:", reactive.tickCount());
    }
}
