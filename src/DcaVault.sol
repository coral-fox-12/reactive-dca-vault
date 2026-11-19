// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title DcaVault — holds user ETH for scheduled DCA buys on Base Sepolia.
/// @notice Funds can only leave via `spend()`, callable solely by the
///         DcaExecutor — which itself is only reachable through an
///         authenticated Reactive callback. Users deposit ETH, the executor
///         spends it one buy at a time, and users withdraw the remainder
///         (plus the bought tokens, which the executor sends straight to them).
contract DcaVault {
    address public immutable owner;
    address public executor;

    mapping(address => uint256) public balances;

    event Deposited(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event ExecutorSet(address indexed executor);
    event Spent(address indexed user, uint256 amount);

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "DcaVault: not owner");
        _;
    }

    modifier onlyExecutor() {
        require(msg.sender == executor, "DcaVault: not executor");
        _;
    }

    /// @notice Point the vault at its executor (once, by the owner).
    function setExecutor(address executor_) external onlyOwner {
        require(executor_ != address(0), "DcaVault: zero executor");
        executor = executor_;
        emit ExecutorSet(executor_);
    }

    /// @notice Deposit ETH into the caller's DCA balance.
    function deposit() external payable {
        require(msg.value > 0, "DcaVault: zero deposit");
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    /// @notice Withdraw ETH back to the caller.
    function withdraw(uint256 amount_) external {
        require(balances[msg.sender] >= amount_, "DcaVault: insufficient balance");
        balances[msg.sender] -= amount_;
        (bool ok, ) = msg.sender.call{ value: amount_ }("");
        require(ok, "DcaVault: withdraw failed");
        emit Withdrawn(msg.sender, amount_);
    }

    /// @notice Spend a user's ETH on a DCA buy. Only the executor may call.
    /// @dev Balance is deducted BEFORE the external call (checks-effects-interactions).
    function spend(address user_, uint256 amount_) external onlyExecutor {
        require(balances[user_] >= amount_, "DcaVault: insufficient balance");
        balances[user_] -= amount_;
        (bool ok, ) = msg.sender.call{ value: amount_ }("");
        require(ok, "DcaVault: spend failed");
        emit Spent(user_, amount_);
    }

    /// @notice Plain ETH transfers count as deposits for the sender.
    receive() external payable {
        require(msg.value > 0, "DcaVault: zero deposit");
        balances[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }
}
