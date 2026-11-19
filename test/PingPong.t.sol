// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { Ping } from "../src/Ping.sol";
import { Pong } from "../src/Pong.sol";

contract PingPongTest is Test {
    address internal constant SYSTEM =
        0x8888888888888888888888888888888888888888;
    address payable internal constant BASE_SEPOLIA_PROXY =
        payable(0x476F44b11F5C942c58f4c8E3d0300E5710743585);
    uint256 internal constant CRON10_TOPIC_0 =
        0x04463f7c1651e6b9774d7f85c85bb94654e3c46ca79b0c16fb16d4183307b687;

    Ping internal ping;
    Pong internal pong;

    function setUp() public {
        // SYSTEM (0x8888...) has no code on a local chain, and Foundry
        // reverts calls to non-contract addresses — etch a STOP byte so
        // subscribe()/requestCallback() calls succeed in tests.
        vm.etch(SYSTEM, hex"00");
        ping = new Ping(84532);
        pong = new Pong(IPayable(BASE_SEPOLIA_PROXY), address(ping));
        ping.setCallbackRecipient(address(pong));
    }

    function _cron10Log() internal view returns (IReactive.LogRecord memory) {
        return
            IReactive.LogRecord({
                chainId: block.chainid,
                contractAddress: address(
                    0x0000000000000000000000000000000000fffFfF
                ),
                topic0: CRON10_TOPIC_0,
                topic1: 0,
                topic2: 0,
                topic3: 0,
                data: abi.encode(block.number),
                blockNumber: block.number,
                opCode: 1,
                blockHash: 0,
                txHash: 0,
                logIndex: 0
            });
    }

    function testReactCountsCron10Ticks() public {
        vm.prank(SYSTEM);
        ping.react(_cron10Log());
        assertEq(ping.tickCount(), 1);

        vm.prank(SYSTEM);
        ping.react(_cron10Log());
        assertEq(ping.tickCount(), 2);
    }

    function testReactIgnoresOtherTopics() public {
        IReactive.LogRecord memory log_ = _cron10Log();
        log_.topic0 = 0xdeadbeef;
        vm.prank(SYSTEM);
        ping.react(log_);
        assertEq(ping.tickCount(), 0);
    }

    function testReactRevertsForNonSystemCaller() public {
        vm.expectRevert();
        ping.react(_cron10Log());
    }

    function testPongAcceptsCallbackFromProxy() public {
        vm.prank(BASE_SEPOLIA_PROXY);
        pong.pong(address(ping), 1);
        assertEq(pong.pongCount(), 1);
    }

    function testPongRejectsWrongSender() public {
        vm.prank(BASE_SEPOLIA_PROXY);
        vm.expectRevert();
        pong.pong(address(0x1234), 1);
    }

    function testPongRejectsNonProxyCaller() public {
        vm.expectRevert();
        pong.pong(address(ping), 1);
    }
}
