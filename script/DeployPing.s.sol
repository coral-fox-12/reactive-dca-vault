// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { Ping } from "../src/Ping.sol";

/// @notice Deploy Ping on Lasna testnet (chain id 5318007).
/// @dev Env: PRIVATE_KEY (deployer), PING_VALUE_WEI (optional funding in lREACT, default 0).
///      Destination chain id is Base Sepolia (84532).
contract DeployPing is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        uint256 value = vm.envOr("PING_VALUE_WEI", uint256(0));
        vm.startBroadcast(deployerKey);
        Ping ping = new Ping{ value: value }(84532);
        vm.stopBroadcast();
        console.log("Ping deployed at:", address(ping));
        console.log("destinationChainId:", ping.destinationChainId());
        console.log("owner:", ping.owner());
    }
}
