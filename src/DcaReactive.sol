// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title DcaReactive — Lasna reactive contract: CRON scheduler for the DCA vault.
/// @notice Subscribes to Cron100 ticks (~2 min). On every tick it scans user
///         schedules and requests a callback to the DcaExecutor on Base Sepolia
///         for each schedule whose interval has elapsed. Cron100, NOT Cron10:
///         step 2 measured ~0.012-0.014 lREACT per tick, so Cron10 would drain
///         the contract in minutes; Cron100 buys ~2 min per tick instead.
/// @dev Schedules are created by users directly on this contract (Lasna);
///      funds live separately in the DcaVault on Base Sepolia under the same
///      address. At most MAX_CALLBACKS_PER_TICK callbacks per tick, scanned
///      round-robin via `cursor` so no schedule starves.
contract DcaReactive is AbstractReactive {
    address internal constant LEGACY_SYSTEM_ADDR =
        0x0000000000000000000000000000000000fffFfF;
    // keccak256("Cron100(uint256)") — verified against keccak256("Cron10(uint256)")
    // == Ping's hardcoded CRON10 topic, so the signature scheme is confirmed.
    uint256 internal constant CRON100_TOPIC_0 =
        0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70;

    uint64 internal constant CALLBACK_GAS_LIMIT = 1_000_000;
    uint256 public constant MAX_CALLBACKS_PER_TICK = 5;

    struct Schedule {
        address user;
        address tokenOut;
        uint256 amountIn;
        uint256 intervalTicks; // in Cron100 ticks (~2 min each)
        uint256 lastExecutedTick;
        bool active;
    }

    address public immutable owner;
    uint256 public immutable destinationChainId;
    address public callbackRecipient;
    uint256 public tickCount;
    uint256 public scheduleCount;
    uint256 public executionCount;
    mapping(uint256 => Schedule) public schedules;

    uint256 internal cursor;

    event ScheduleCreated(
        uint256 indexed id,
        address indexed user,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 intervalTicks
    );
    event ScheduleCancelled(uint256 indexed id, address indexed user);
    event ScheduleExecuted(
        uint256 indexed id,
        address indexed user,
        uint256 indexed tickCount
    );
    event Tick(uint256 indexed blockNumber, uint256 tickCount);
    event CallbackRequested(
        uint256 indexed blockNumber,
        address indexed recipient,
        uint256 indexed scheduleId
    );

    /// @param destinationChainId_ Chain id of the callback destination (Base Sepolia: 84532).
    constructor(uint256 destinationChainId_) payable {
        owner = msg.sender;
        destinationChainId = destinationChainId_;
        SYSTEM.subscribe(
            block.chainid,
            LEGACY_SYSTEM_ADDR,
            CRON100_TOPIC_0,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "DcaReactive: not owner");
        _;
    }

    /// @notice Create a DCA schedule. First buy fires `intervalTicks` ticks
    ///         after creation (no immediate burst).
    function createSchedule(
        address tokenOut_,
        uint256 amountIn_,
        uint256 intervalTicks_
    ) external returns (uint256 id) {
        require(tokenOut_ != address(0), "DcaReactive: zero token");
        require(amountIn_ > 0, "DcaReactive: zero amount");
        require(intervalTicks_ >= 1, "DcaReactive: zero interval");
        id = scheduleCount++;
        schedules[id] = Schedule({
            user: msg.sender,
            tokenOut: tokenOut_,
            amountIn: amountIn_,
            intervalTicks: intervalTicks_,
            lastExecutedTick: tickCount,
            active: true
        });
        emit ScheduleCreated(id, msg.sender, tokenOut_, amountIn_, intervalTicks_);
    }

    /// @notice Cancel your own schedule.
    function cancelSchedule(uint256 id_) external {
        Schedule storage s = schedules[id_];
        require(s.user == msg.sender, "DcaReactive: not schedule owner");
        require(s.active, "DcaReactive: already inactive");
        s.active = false;
        emit ScheduleCancelled(id_, msg.sender);
    }

    /// @notice Set the callback recipient (DcaExecutor on the destination chain).
    ///         Deploy order: DcaReactive first, then Vault + Executor with this
    ///         contract's address, then this setter.
    function setCallbackRecipient(address recipient_) external onlyOwner {
        callbackRecipient = recipient_;
    }

    /// @notice Pause the CRON subscription (stops per-tick billing).
    function pause() external onlyOwner {
        SYSTEM.unsubscribe(
            block.chainid,
            LEGACY_SYSTEM_ADDR,
            CRON100_TOPIC_0,
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
            CRON100_TOPIC_0,
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
        if (log_.topic0 != CRON100_TOPIC_0) return;
        tickCount++;
        emit Tick(block.number, tickCount);
        uint256 n = scheduleCount;
        if (callbackRecipient == address(0) || n == 0) return;
        uint256 sent = 0;
        uint256 scanned = 0;
        for (uint256 i = 0; i < n && sent < MAX_CALLBACKS_PER_TICK; i++) {
            scanned = i + 1;
            uint256 id = (cursor + i) % n;
            Schedule storage s = schedules[id];
            if (!s.active) continue;
            if (tickCount - s.lastExecutedTick < s.intervalTicks) continue;
            s.lastExecutedTick = tickCount;
            bytes memory payload = abi.encodeWithSignature(
                "executeBuy(address,address,uint256,address)",
                address(0),
                s.user,
                s.amountIn,
                s.tokenOut
            );
            SYSTEM.requestCallbackV_1_0(
                ISystemContract.CallbackConfiguration_V_1_0({
                    chainId: destinationChainId,
                    recipient: callbackRecipient,
                    gasLimit: CALLBACK_GAS_LIMIT,
                    payload: payload
                })
            );
            executionCount++;
            sent++;
            emit ScheduleExecuted(id, s.user, tickCount);
            emit CallbackRequested(block.number, callbackRecipient, id);
        }
        cursor = (cursor + scanned) % n;
    }
}
