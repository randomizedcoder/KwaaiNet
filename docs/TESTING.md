# Testing Guide

## Current Test Landscape

All tests are inline `#[cfg(test)] mod tests` — no integration test directories.

| Crate | Tests | Key areas |
|-------|-------|-----------|
| kwaai-hivemind-dht | 8 | codec, value serialisation, server, client |
| kwaai-inference | 7 | engine, shard (RopeCache), tokenizer |
| kwaai-p2p | 5 | DHT, hivemind, RPC |
| kwaai-p2p-daemon | 5 | DHT, daemon, client, stream |
| kwaai-cli | 13 | config (13), throughput, shard_cmd |
| kwaai-distributed | 2 | expert registry, averaging |
| kwaai-compression | 2 | quantization roundtrip, sparse top-K |
| kwaai-wasm | 2 | WASM bindings |
| kwaai-trust | 0 | empty test modules |

## Test Dependencies

Current dev-dependencies:

- `tempfile` — isolated filesystem for config tests
- `tokio-test` — async test runtime
- `criterion` — benchmark stubs (compression + inference)
- `wasm-bindgen-test` — WASM bindings

No parameterized or property-based test frameworks are used.

## Framework Decision

| Framework | Pros | Cons |
|-----------|------|------|
| Plain loops | Zero deps, matches existing patterns | No per-case names in output |
| `rstest` | Named sub-tests, fixture support | New dependency |
| `test-case` | Lightweight parameterization | New dependency |
| `proptest` | Property-based, finds edge cases | Heavier dep, slower runs |

**Current choice: plain loops.** This matches the existing test style and adds no
new dependencies. The `config.rs` tests use `for` loops to cover multiple inputs
within a single `#[test]` function.

**Recommendation:** adopt `rstest` or `test-case` when broader test coverage work
begins — each parameter combo gets its own named sub-test in CI output, making
failures easier to diagnose.

## Coverage Gaps

- **kwaai-trust**: no tests at all (empty test modules)
- **kwaai-cli**: `block_rpc`, `rebalancer`, `hf` modules have empty test modules
- **Benchmarks**: criterion stubs exist in compression + inference (not yet implemented)
- **Cross-arch**: handled by Nix MicroVM lifecycle tests, not Rust unit tests

## Running Tests

```bash
# All crates
cargo test --all

# Single module, verbose
cargo test -p kwaai-cli -- config::tests -v

# Single test
cargo test -p kwaai-cli -- config::tests::set_key_boolean_values
```

**CI:** `.github/workflows/ci.yml` runs `cargo test --all` on ubuntu + macos.

**Nix lifecycle tests:**

```bash
make test                        # all Nix tests
make test-lifecycle-x86_64       # x86_64 MicroVM lifecycle
```
