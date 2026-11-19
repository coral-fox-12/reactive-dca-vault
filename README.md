# Reactive DCA Vault

Self-running cross-chain DCA (dollar-cost averaging) vault on
[Reactive Network (Omni)](https://dev.reactive.network/).

**Event:** Reactive Omni Buildathon (DoraHacks, Nov 5 – Dec 5, 2026)
**Track:** Set It and Forget It ($2,000 1st / $250 runner-up, paid in REACT)

## Concept

A user sets a DCA schedule once (token, fixed amount, interval) and funds a
vault on Base Sepolia. A reactive contract on Lasna testnet subscribes to
CRON ticks and fires a Uniswap V2 swap on Base Sepolia every interval — no
bot, no keeper, nothing to babysit. A dashboard shows the schedule, next run,
every executed buy with its tx hash, and the average entry price.

## Architecture

| Contract | Chain | Role |
| --- | --- | --- |
| `Ping` (`src/Ping.sol`) | Lasna (5318007) | Step-1 loop proof: subscribes to Cron10, requests a callback per tick |
| `Pong` (`src/Pong.sol`) | Base Sepolia (84532) | Step-1 loop proof: receives `pong(address,uint256)` callbacks via the Base Sepolia callback proxy |
| `DcaVault` | Base Sepolia | Step 2: holds user funds, only callable via authenticated callback |
| `DcaReactive` | Lasna | Step 2: CRON subscription + per-user schedule state, requests swap callbacks |

Step 1 proves the full loop: **CRON event → `react()` → callback request →
callback tx on Base Sepolia**. Step 2 replaces Ping/Pong with the vault.

Key facts (verified from the docs):

- System contract: `0x8888888888888888888888888888888888888888` (Lasna + mainnet)
- Base Sepolia callback proxy: `0x476F44b11F5C942c58f4c8E3d0300E5710743585`
- Lasna RPC: `https://lasna-rpc.rnk.dev/`, chain id `5318007`
- Callbacks are billed to the **recipient** on the destination chain, in that
  chain's native token; the reactive contract pays for `react()` in REACT.
- Deploy order: reactive contract → callback contract (with reactive address)
  → set recipient on the reactive contract → fund both.

## Development

Requires [Foundry](https://book.getfoundry.sh/) (`forge`, `cast`).

```shell
forge build
forge test
```

Deploy (testnet only; deployer key lives in gitignored `.wallet.json`):

```shell
# Lasna: deploy Ping, funded with lREACT
PRIVATE_KEY=$(python3 -c "import json;print(json.load(open('.wallet.json'))['private_key'])") \
PING_VALUE_WEI=1000000000000000000 \
forge script script/DeployPing.s.sol --rpc-url https://lasna-rpc.rnk.dev/ --chain-id 5318007 --broadcast

# Base Sepolia: deploy Pong (needs PING_ADDRESS from the step above)
PRIVATE_KEY=$(python3 -c "import json;print(json.load(open('.wallet.json'))['private_key'])") \
PING_ADDRESS=0x... PONG_VALUE_WEI=10000000000000000 \
forge script script/DeployPong.s.sol --rpc-url https://sepolia.base.org --chain-id 84532 --broadcast

# Then set the recipient on Ping (owner-only) and watch Cron10 ticks arrive.
```

Funding the testnet wallet: send Sepolia ETH to the lREACT faucet contracts
(`0x9b9BB25f1A81078C544C829c5EB7822d747Cf434` on Ethereum Sepolia or
`0x2afaFD298b23b62760711756088F75B7409f5967` on Base Sepolia) — 1 ETH → 100
lREACT, max 5 ETH/tx.

## Submission evidence (Reactive Omni Buildathon — track: Set It and Forget It)

Live loop proven end-to-end on testnet, 19 Nov 2026. All on testnet — $0 spent.

- **Dashboard:** https://reactive-dca-vault.surge.sh/ (reads live on-chain state; falls back to a labelled snapshot)
- **Demo video:** `reactive-dca-vault-demo-v1.mp4` — 2 min 44 s, 1920×1080, submitted with the DoraHacks entry
- **Schedule #0:** DCAT, 0.0001 ETH per buy, Cron100 (~2 min/tick), ticks 3 / buys 2, lastExecutedTick 3, active = true
- **Status (honest): PAUSED** — unpaid SYSTEM debt 0.0167138 lREACT exceeds the contract balance 0.0074661 lREACT, so the CRON subscription is paused; the vault is empty (both buys spent the 0.0002 ETH deposit). The dashboard shows this banner live.

### Deployed contracts

| Contract | Chain | Address |
| --- | --- | --- |
| DcaReactive (CRON scheduler) | Lasna (5318007) | `0x09F73B2A778D834FD9D6c2077C0143ceF280C576` |
| DcaVault (holds user ETH) | Base Sepolia (84532) | `0x8f1ee4c7f0e0a1c8efe05dd177691dbb406bb4a1` |
| DcaExecutor (callback → swap) | Base Sepolia | `0x7a1f950154978f4aaa53bb9d257c0f7b3375fa14` |
| DcaToken (DCAT, demo ERC20) | Base Sepolia | `0x09F73B2A778D834FD9D6c2077C0143ceF280C576` |
| Uniswap V2 pair (DCAT/WETH) | Base Sepolia | `0x5D52B2d78ed319dD7bD11a38Ad623eB12d93eB17` |
| Ping / Pong (step-1 loop proof) | Lasna / Base Sepolia | `0xDB4D23b94FA88C9e38c844d2e628D757f9D257Ae` / `0x745b0e9a3b8516b40443a9ac841f5a6d7a933b07` |

### The two live buys (full loop: Lasna CRON tick → `react()` → callback → Uniswap V2 swap)

| Buy | Spent | Received | Base Sepolia callback tx | Block |
| --- | --- | --- | --- | --- |
| #1 (tick 2, Lasna 8720601) | 0.0001 ETH | 906.61 DCAT | `0x34c20415df89ca444d456599fc81d416dfb1d3ae9d8db011b0a729a4edeec17d` | 60779144 |
| #2 (tick 3, Lasna 8720901) | 0.0001 ETH | 755.70 DCAT | `0x980aa2211f2244a236c58efe3a1c8c457b930648600bd7ba4e1280d4f1905b41` | 60780743 |

Average: 0.0002 ETH → 1,662.31 DCAT = 8,311,550 DCAT/ETH. Buy #2 paid less DCAT per ETH than #1 — normal constant-product price impact as the pair reserve shrank. Both receipts verified on-chain (vault `Spent` → WETH → pair `Swap` → executor `BuyExecuted`, status 1).

Loop proof (step 1): Ping/Pong delivered **15/15 callbacks, zero misses** (Cron10, ticks 6–20). Measured cost: ~0.017 lREACT per buy, dominated by the callback.

## Status

- [x] Step 1 scaffold: repo, wallet, Ping/Pong contracts + tests
- [x] Step 1: fund wallet, deploy, prove the live loop (CRON → react → callback) — 15/15 callbacks
- [x] Step 2: Vault + DCA reactive contract + Uniswap V2 integration (26/26 forge tests)
- [x] Step 3: live DCA cycles (2 buys proven on-chain), dashboard, demo video
- [ ] DoraHacks submit (repo + contracts + tx hashes + video) — by 5 Dec 2026

## License

MIT — see [LICENSE](LICENSE).
