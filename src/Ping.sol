// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title Ping — minimal reactive contract proving the CRON → react → callback loop.
/// @notice Deployed on Lasna testnet. Subscribes to Cron10 ticks (~10s) from the
///         legacy system contract, counts them, and requests a callback to the
///         Pong contract on Base Sepolia on every tick. This is the loop-proof
///         for the DCA vault (step 1); the production DCA reactive contract
///         replaces it in step 2.
contract Ping is AbstractReactive {
    address internal constant LEGACY_SYSTEM_ADDR =
        0x0000000000000000000000000000000000fffFfF;
    uint256 internal constant CRON10_TOPIC_0 =
        0x04463f7c1651e6b9774d7f85c85bb94654e3c46ca79b0c16fb16d4183307b687;

    uint64 internal constant CALLBACK_GAS_LIMIT = 1_000_000;

    address public immutable owner;
    uint256 public immutable destinationChainId;
    address public callbackRecipient;
    uint256 public tickCount;

    event Tick(uint256 indexed blockNumber, uint256 tickCount);
    event CallbackRequested(uint256 indexed blockNumber, address indexed recipient);

    /// @param destinationChainId_ Chain id of the callback destination (Base Sepolia: 84532).
    constructor(uint256 destinationChainId_) payable {
        owner = msg.sender;
        destinationChainId = destinationChainId_;
        SYSTEM.subscribe(
            block.chainid,
            LEGACY_SYSTEM_ADDR,
            CRON10_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Ping: not owner");
        _;
    }

    /// @notice Set the callback recipient (Pong on the destination chain).
    ///         Deploy order: Ping first, then Pong with Ping's address, then this setter.
    function setCallbackRecipient(address recipient_) external onlyOwner {
        callbackRecipient = recipient_;
    }

    /// @notice Pause the CRON subscription (stops per-tick billing).
    function pause() external onlyOwner {
        SYSTEM.unsubscribe(
            block.chainid,
            LEGACY_SYSTEM_ADDR,
            CRON10_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @notice Resume the CRON subscription (settles any debt first).
    function resume() external onlyOwner {
        _coverDebt();
        SYSTEM.subscribe(
            block.chainid,
            LEGACY_SYSTEM_ADDR,
            CRON10_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @notice Settle outstanding debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        if (log_.topic0 != CRON10_TOPIC_0) return;
        tickCount++;
        emit Tick(block.number, tickCount);
        if (callbackRecipient != address(0)) {
            bytes memory payload = abi.encodeWithSignature(
                "pong(address,uint256)",
                address(0),
                tickCount
            );
            SYSTEM.requestCallbackV_1_0(
                ISystemContract.CallbackConfiguration_V_1_0({
                    chainId: destinationChainId,
                    recipient: callbackRecipient,
                    gasLimit: CALLBACK_GAS_LIMIT,
                    payload: payload
                })
            );
            emit CallbackRequested(block.number, callbackRecipient);
        }
    }
}
