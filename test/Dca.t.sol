// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { IUniswapV2Factory } from "v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import { IUniswapV2Router02 } from "v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import { DcaToken } from "../src/DcaToken.sol";
import { DcaVault } from "../src/DcaVault.sol";
import { DcaExecutor } from "../src/DcaExecutor.sol";
import { DcaReactive } from "../src/DcaReactive.sol";

/// @notice Minimal WETH9 interface (local, 0.8.29) — the 0.6.6 WETH9
///         implementation is deployed from a precompiled artifact instead
///         (this Foundry build cannot compile 0.5.16/0.6.6 sources in-project).
interface IWETH9 {
    function deposit() external payable;
    function withdraw(uint256 wad) external;
    function approve(address guy, uint256 wad) external returns (bool);
    function transfer(address dst, uint256 wad) external returns (bool);
    function balanceOf(address guy) external view returns (uint256);
}

/// @notice Full-stack tests for the DCA vault: a local Uniswap V2 deployment
///         (factory + router + WETH9 + DCAT pair, 10 ETH / 100k DCAT liquidity)
///         backs the executor's real swaps; the reactive contract is driven
///         with synthetic Cron100 logs from the etched SYSTEM address.
contract DcaTest is Test {
    address internal constant SYSTEM =
        0x8888888888888888888888888888888888888888;
    address payable internal constant BASE_SEPOLIA_PROXY =
        payable(0x476F44b11F5C942c58f4c8E3d0300E5710743585);
    address internal constant LEGACY_SYSTEM_ADDR =
        0x0000000000000000000000000000000000fffFfF;
    // keccak256("Cron100(uint256)") — verified in shell against
    // keccak256("Cron10(uint256)") == Ping's hardcoded CRON10 topic.
    uint256 internal constant CRON100_TOPIC_0 =
        0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70;

    IUniswapV2Factory internal factory;
    IWETH9 internal weth;
    IUniswapV2Router02 internal router;
    DcaToken internal token;
    DcaVault internal vault;
    DcaExecutor internal executor;
    DcaReactive internal reactive;

    address internal user = makeAddr("user");

    function setUp() public {
        vm.deal(address(this), 100 ether);
        // SYSTEM (0x8888...) has no code on a local chain — etch a STOP byte
        // so subscribe()/requestCallback() calls succeed in tests.
        vm.etch(SYSTEM, hex"00");

        // Local Uniswap V2 stack, deployed from precompiled artifacts
        // (artifacts-v2/; the 0.5.16/0.6.6 sources cannot compile in this
        // Foundry project — see artifacts-v2/README.md). Seeded with
        // 10 ETH / 100,000 DCAT of liquidity (~1 DCAT = 0.0001 ETH).
        address factoryAddr = vm.deployCode(
            "artifacts-v2/UniswapV2Factory.json",
            abi.encode(address(this))
        );
        factory = IUniswapV2Factory(factoryAddr);
        weth = IWETH9(vm.deployCode("artifacts-v2/WETH9.json"));
        router = IUniswapV2Router02(
            vm.deployCode(
                "artifacts-v2/UniswapV2Router02.json",
                abi.encode(factoryAddr, address(weth))
            )
        );
        token = new DcaToken();
        token.approve(address(router), 100_000 ether);
        router.addLiquidityETH{ value: 10 ether }(
            address(token),
            100_000 ether,
            0,
            0,
            address(this),
            block.timestamp + 1
        );

        // DCA stack, wired exactly like the testnet deploy order:
        // reactive (Lasna) -> vault + executor (Base Sepolia) -> setter.
        vault = new DcaVault();
        reactive = new DcaReactive(84532);
        executor = new DcaExecutor{ value: 1 ether }(
            IPayable(BASE_SEPOLIA_PROXY),
            address(reactive),
            vault,
            router,
            address(weth),
            500 // 5% slippage
        );
        vault.setExecutor(address(executor));
        reactive.setCallbackRecipient(address(executor));

        // _coverDebt() (called by resume()/coverDebt()) reads the service
        // provider's debt — the etched STOP byte returns empty data and
        // decoding a uint256 from it would revert, so mock debt() -> 0.
        vm.mockCall(
            SYSTEM,
            abi.encodeWithSignature("debt(address)", address(reactive)),
            abi.encode(uint256(0))
        );

        vm.deal(user, 10 ether);
    }

    function _cron100Log() internal view returns (IReactive.LogRecord memory) {
        return
            IReactive.LogRecord({
                chainId: block.chainid,
                contractAddress: LEGACY_SYSTEM_ADDR,
                topic0: CRON100_TOPIC_0,
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

    function _tick() internal {
        vm.prank(SYSTEM);
        reactive.react(_cron100Log());
    }

    // ---- Vault ----

    function testVaultDepositAndWithdraw() public {
        vm.prank(user);
        vault.deposit{ value: 1 ether }();
        assertEq(vault.balances(user), 1 ether);

        uint256 before = user.balance;
        vm.prank(user);
        vault.withdraw(0.4 ether);
        assertEq(vault.balances(user), 0.6 ether);
        assertEq(user.balance, before + 0.4 ether);
    }

    function testVaultPlainTransferCountsAsDeposit() public {
        vm.prank(user);
        (bool ok, ) = address(vault).call{ value: 0.25 ether }("");
        assertTrue(ok);
        assertEq(vault.balances(user), 0.25 ether);
    }

    function testVaultWithdrawRevertsWhenInsufficient() public {
        vm.prank(user);
        vault.deposit{ value: 0.1 ether }();
        vm.prank(user);
        vm.expectRevert("DcaVault: insufficient balance");
        vault.withdraw(0.2 ether);
    }

    function testVaultSpendOnlyExecutor() public {
        vm.prank(user);
        vault.deposit{ value: 1 ether }();
        vm.expectRevert("DcaVault: not executor");
        vault.spend(user, 0.1 ether);
    }

    function testVaultSetExecutorOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert("DcaVault: not owner");
        vault.setExecutor(address(0x1234));
        vm.expectRevert("DcaVault: zero executor");
        vault.setExecutor(address(0));
    }

    // ---- Executor: swaps against the local V2 pair ----

    function testExecutorBuyEndToEnd() public {
        vm.prank(user);
        vault.deposit{ value: 0.1 ether }();

        vm.prank(BASE_SEPOLIA_PROXY);
        executor.executeBuy(address(reactive), user, 0.01 ether, address(token));

        // ~100 DCAT for 0.01 ETH at 1 DCAT = 0.0001 ETH, minus 0.3% fee.
        assertGt(token.balanceOf(user), 90 ether);
        assertEq(vault.balances(user), 0.09 ether);
        assertEq(executor.buyCount(), 1);
        assertEq(executor.skipCount(), 0);
    }

    function testExecutorBuySkipsOnInsufficientBalance() public {
        vm.prank(user);
        vault.deposit{ value: 0.001 ether }();

        vm.prank(BASE_SEPOLIA_PROXY);
        executor.executeBuy(address(reactive), user, 0.01 ether, address(token));

        // No revert: skipped, balances untouched.
        assertEq(executor.skipCount(), 1);
        assertEq(executor.buyCount(), 0);
        assertEq(vault.balances(user), 0.001 ether);
        assertEq(token.balanceOf(user), 0);
    }

    function testExecutorRejectsWrongSender() public {
        vm.prank(BASE_SEPOLIA_PROXY);
        vm.expectRevert();
        executor.executeBuy(address(0x1234), user, 0.01 ether, address(token));
    }

    function testExecutorRejectsNonProxyCaller() public {
        vm.expectRevert();
        executor.executeBuy(address(reactive), user, 0.01 ether, address(token));
    }

    function testExecutorSlippageBounds() public {
        executor.setSlippageBps(5000);
        assertEq(executor.slippageBps(), 5000);
        vm.expectRevert("DcaExecutor: slippage too high");
        executor.setSlippageBps(5001);
        vm.prank(user);
        vm.expectRevert("DcaExecutor: not owner");
        executor.setSlippageBps(100);
    }

    // ---- Reactive: schedules + Cron100 ticks ----

    function testReactiveCreateSchedule() public {
        vm.prank(user);
        uint256 id = reactive.createSchedule(address(token), 0.01 ether, 3);
        assertEq(id, 0);
        (
            address sUser,
            address sToken,
            uint256 sAmount,
            uint256 sInterval,
            uint256 sLast,
            bool sActive
        ) = reactive.schedules(0);
        assertEq(sUser, user);
        assertEq(sToken, address(token));
        assertEq(sAmount, 0.01 ether);
        assertEq(sInterval, 3);
        assertEq(sLast, 0);
        assertTrue(sActive);
        assertEq(reactive.scheduleCount(), 1);
    }

    function testReactiveCreateScheduleValidation() public {
        vm.prank(user);
        vm.expectRevert("DcaReactive: zero token");
        reactive.createSchedule(address(0), 0.01 ether, 1);
        vm.prank(user);
        vm.expectRevert("DcaReactive: zero amount");
        reactive.createSchedule(address(token), 0, 1);
        vm.prank(user);
        vm.expectRevert("DcaReactive: zero interval");
        reactive.createSchedule(address(token), 0.01 ether, 0);
    }

    function testReactiveCancelSchedule() public {
        vm.prank(user);
        reactive.createSchedule(address(token), 0.01 ether, 1);
        vm.prank(address(0xBEEF)); // not the schedule owner
        vm.expectRevert("DcaReactive: not schedule owner");
        reactive.cancelSchedule(0);
        vm.prank(user);
        reactive.cancelSchedule(0);
        (, , , , , bool active) = reactive.schedules(0);
        assertFalse(active);
        vm.prank(user);
        vm.expectRevert("DcaReactive: already inactive");
        reactive.cancelSchedule(0);
    }

    function testReactiveTickFiresDueSchedule() public {
        vm.prank(user);
        reactive.createSchedule(address(token), 0.01 ether, 2);

        _tick(); // tick 1: 1 - 0 < 2, not due
        assertEq(reactive.tickCount(), 1);
        assertEq(reactive.executionCount(), 0);

        _tick(); // tick 2: 2 - 0 >= 2, fires
        assertEq(reactive.tickCount(), 2);
        assertEq(reactive.executionCount(), 1);
        (, , , , uint256 last, ) = reactive.schedules(0);
        assertEq(last, 2);

        _tick(); // tick 3: 3 - 2 < 2, not due
        assertEq(reactive.executionCount(), 1);
    }

    function testReactiveCapAndRoundRobin() public {
        for (uint256 i = 0; i < 7; i++) {
            vm.prank(user);
            reactive.createSchedule(address(token), 0.01 ether, 1);
        }
        _tick(); // all 7 due, cap is 5
        assertEq(reactive.executionCount(), 5);
        _tick(); // remaining 2 + 3 re-due, cap 5 again
        assertEq(reactive.executionCount(), 10);
    }

    function testReactiveSkipsCancelledSchedule() public {
        vm.prank(user);
        reactive.createSchedule(address(token), 0.01 ether, 1);
        vm.prank(user);
        reactive.createSchedule(address(token), 0.01 ether, 1);
        vm.prank(user);
        reactive.cancelSchedule(0);
        _tick();
        assertEq(reactive.executionCount(), 1);
    }

    function testReactiveIgnoresOtherTopics() public {
        vm.prank(user);
        reactive.createSchedule(address(token), 0.01 ether, 1);
        IReactive.LogRecord memory log_ = _cron100Log();
        log_.topic0 = 0xdeadbeef;
        vm.prank(SYSTEM);
        reactive.react(log_);
        assertEq(reactive.tickCount(), 0);
        assertEq(reactive.executionCount(), 0);
    }

    function testReactiveRevertsForNonSystemCaller() public {
        vm.expectRevert();
        reactive.react(_cron100Log());
    }

    function testReactivePauseAndResume() public {
        reactive.pause();
        reactive.resume();
    }

    function testReactiveSetCallbackRecipientOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert("DcaReactive: not owner");
        reactive.setCallbackRecipient(address(0x1234));
    }
}
