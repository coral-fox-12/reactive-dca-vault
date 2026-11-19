// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { IUniswapV2Router02 } from "v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import { DcaVault } from "./DcaVault.sol";

/// @title DcaExecutor — Base Sepolia callback contract for the DCA vault.
/// @notice Receives `executeBuy` callbacks from the DcaReactive contract on
///         Lasna via the Base Sepolia callback proxy, verifies them with the
///         same guards as Pong (onlyServiceProvider + onlyCallbackSender),
///         then executes one DCA buy: vault ETH -> Uniswap V2 swap -> tokens
///         straight to the user.
/// @dev minAmountOut is derived on-chain from the pair's current reserves
///      (getAmountsOut, discounted by slippageBps) — the reactive contract
///      cannot price the destination chain, so pricing lives here. If the
///      user has insufficient vault balance the buy is SKIPPED (event, no
///      revert) so one broke schedule cannot brick the callback loop.
contract DcaExecutor is AbstractCallback {
    DcaVault public immutable vault;
    IUniswapV2Router02 public immutable router;
    address public immutable weth;
    address public immutable owner;

    uint256 public slippageBps; // e.g. 500 = 5% max slippage vs quoted amounts
    uint256 public buyCount;
    uint256 public skipCount;

    event BuyExecuted(
        address indexed user,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 buyCount
    );
    event BuySkipped(
        address indexed user,
        address indexed tokenOut,
        uint256 amountIn,
        string reason
    );
    event SlippageSet(uint256 slippageBps);

    /// @param callbackProxy_ Callback proxy on the destination chain
    ///        (Base Sepolia: 0x476F44b11F5C942c58f4c8E3d0300E5710743585).
    /// @param callbackSender_ The DcaReactive contract's address on Lasna.
    /// @param vault_ The DcaVault holding user ETH.
    /// @param router_ Uniswap V2 router on the destination chain.
    /// @param weth_ WETH on the destination chain.
    /// @param slippageBps_ Max slippage in basis points (<= 5000).
    constructor(
        IPayable callbackProxy_,
        address callbackSender_,
        DcaVault vault_,
        IUniswapV2Router02 router_,
        address weth_,
        uint256 slippageBps_
    ) payable AbstractCallback(callbackProxy_, callbackSender_) {
        require(
            address(vault_) != address(0) &&
                address(router_) != address(0) &&
                weth_ != address(0),
            "DcaExecutor: zero address"
        );
        require(slippageBps_ <= 5000, "DcaExecutor: slippage too high");
        owner = msg.sender;
        vault = vault_;
        router = router_;
        weth = weth_;
        slippageBps = slippageBps_;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "DcaExecutor: not owner");
        _;
    }

    function setSlippageBps(uint256 slippageBps_) external onlyOwner {
        require(slippageBps_ <= 5000, "DcaExecutor: slippage too high");
        slippageBps = slippageBps_;
        emit SlippageSet(slippageBps_);
    }

    /// @notice Execute one DCA buy. Called by the callback proxy only.
    function executeBuy(
        address reactive_,
        address user_,
        uint256 amountIn_,
        address tokenOut_
    ) external onlyServiceProvider onlyCallbackSender(reactive_) {
        if (vault.balances(user_) < amountIn_) {
            skipCount++;
            emit BuySkipped(user_, tokenOut_, amountIn_, "insufficient vault balance");
            return;
        }
        address[] memory path = new address[](2);
        path[0] = weth;
        path[1] = tokenOut_;
        uint256[] memory quoted = router.getAmountsOut(amountIn_, path);
        uint256 minOut = (quoted[1] * (10000 - slippageBps)) / 10000;
        vault.spend(user_, amountIn_);
        uint256[] memory amounts = router.swapExactETHForTokens{ value: amountIn_ }(
            minOut,
            path,
            user_,
            block.timestamp
        );
        buyCount++;
        emit BuyExecuted(user_, tokenOut_, amountIn_, amounts[1], buyCount);
    }

    /// @notice Settle outstanding debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }

    /// @notice Accept ETH (funding for callback gas on the destination chain).
    receive() external payable override {}
}
