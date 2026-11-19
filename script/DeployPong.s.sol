// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { Pong } from "../src/Pong.sol";

/// @notice Deploy Pong on Base Sepolia (chain id 84532).
/// @dev Env: PRIVATE_KEY (deployer), PING_ADDRESS (Ping on Lasna),
///      PONG_VALUE_WEI (optional funding in Base Sepolia ETH, default 0).
contract DeployPong is Script {
    address payable internal constant BASE_SEPOLIA_PROXY =
        payable(0x476F44b11F5C942c58f4c8E3d0300E5710743585);

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address ping = vm.envAddress("PING_ADDRESS");
        uint256 value = vm.envOr("PONG_VALUE_WEI", uint256(0));
        vm.startBroadcast(deployerKey);
        Pong pong = new Pong{ value: value }(
            IPayable(BASE_SEPOLIA_PROXY),
            ping
        );
        vm.stopBroadcast();
        console.log("Pong deployed at:", address(pong));
        console.log("callbackSender (Ping):", ping);
        console.log("pongCount:", pong.pongCount());
    }
}
