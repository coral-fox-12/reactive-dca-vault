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

## Status

- [x] Step 1 scaffold: repo, wallet, Ping/Pong contracts + tests
- [ ] Step 1: fund wallet, deploy, prove the live loop (CRON → react → callback)
- [ ] Step 2: Vault + DCA reactive contract + Uniswap V2 integration
- [ ] Step 3: live DCA cycles, dashboard, demo video, DoraHacks submit

## License

MIT — see [LICENSE](LICENSE).
