# Precompiled Uniswap V2 artifacts

The canonical Uniswap V2 contracts are Solidity 0.5.16 (v2-core) and 0.6.6
(v2-periphery). This Foundry 1.9.0 project cannot compile sources across
incompatible solc versions in one project (`Error: Found incompatible
versions`), so the V2 contracts are compiled once with standalone solc
binaries and deployed from these artifacts via `vm.deployCode`.

## How to rebuild

```bash
# Install the old solc binaries (one-time):
mkdir -p ~/.svm/0.5.16 ~/.svm/0.6.6
curl -o ~/.svm/0.5.16/solc-0.5.16 \
  https://binaries.soliditylang.org/linux-amd64/solc-linux-amd64-v0.5.16+commit.9c3226ce
curl -o ~/.svm/0.6.6/solc-0.6.6 \
  https://binaries.soliditylang.org/linux-amd64/solc-linux-amd64-v0.6.6+commit.6c089d02
chmod +x ~/.svm/0.5.16/solc-0.5.16 ~/.svm/0.6.6/solc-0.6.6

# Rebuild the artifacts (script saved at /tmp/v2build/build_artifacts.py):
python3 /tmp/v2build/build_artifacts.py
```

The build uses `--optimize --optimize-runs 999999` (same as the canonical
V2 deployments) and these remappings:

```
@uniswap/v2-core/=lib/v2-core/
@uniswap/lib/=lib/solidity-lib/
```

## CRITICAL: compile the factory from inside lib/v2-core

The factory embeds the pair creation code, and the pair's init code hash is
part of its creation bytecode metadata. `UniswapV2Library.pairFor` (used by
the router for every swap) hardcodes the canonical hash
`0x96e8ac4277198ff8b6f785478aa9a39f403cb768dd02cbee326c3e7da348845f`.
The metadata hash depends on the source paths as passed to solc, so the
factory MUST be compiled with cwd=`lib/v2-core` and source path
`contracts/UniswapV2Factory.sol`. Compiling it from the repo root (path
`lib/v2-core/contracts/...`) produces a different pair hash, and then the
router's `pairFor` computes a pair address that has no code — swaps revert
with "call to non-contract address" (found 19/11, fixed by rebuilding the
factory artifact from inside lib/v2-core; verify with
`/tmp/v2build/build_factory.py`, which prints both hashes).

## Sources

- `UniswapV2Factory.json` — Uniswap/v2-core v1.0.1, `UniswapV2Factory`
  (constructor: feeToSetter). Compiled with solc 0.5.16.
- `UniswapV2Router02.json` — Uniswap/v2-periphery (main), `UniswapV2Router02`
  (constructor: factory, WETH). Compiled with solc 0.6.6.
- `WETH9.json` — Uniswap/v2-periphery test helper, `WETH9` (no constructor
  args). Compiled with solc 0.6.6. Used in local tests only — on Base
  Sepolia the WETH predeploy `0x4200000000000000000000000000000000000006`
  is used instead.

V2-core and v2-periphery are GPL-3.0 (Uniswap). They are used here as
unmodified dependencies, exactly as the official Reactive demos use them.
