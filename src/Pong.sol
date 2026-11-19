// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

/// @title Pong — minimal callback contract proving the callback half of the loop.
/// @notice Deployed on Base Sepolia. Receives `pong(address,uint256)` callbacks
///         from the Ping reactive contract on Lasna via the Base Sepolia callback
///         proxy. The first argument is overwritten by the proxy with the
///         reactive contract's address and authenticated with both guards.
contract Pong is AbstractCallback {
    event Ponged(
        address indexed reactive_,
        uint256 indexed tick_,
        uint256 indexed blockNumber
    );

    uint256 public pongCount;

    /// @param callbackProxy_ Callback proxy on the destination chain
    ///        (Base Sepolia: 0x476F44b11F5C942c58f4c8E3d0300E5710743585).
    /// @param callbackSender_ The Ping reactive contract's address on Lasna.
    constructor(
        IPayable callbackProxy_,
        address callbackSender_
    ) payable AbstractCallback(callbackProxy_, callbackSender_) {}

    /// @notice Called by the callback proxy on every Ping tick.
    function pong(
        address reactive_,
        uint256 tick_
    ) external onlyServiceProvider onlyCallbackSender(reactive_) {
        pongCount++;
        emit Ponged(reactive_, tick_, block.number);
    }

    /// @notice Settle outstanding debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }
}
