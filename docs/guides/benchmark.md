---
sidebar_position: 2
---

# Benchmarks

Numbers first, then everything else.

`FireSync` with 5,000 all-sync listeners costs **18.5ms** per frame. `FireDeferred` under the same load costs **0.116ms** — and that gap widens as listener count climbs. The right fire method for your use case matters. The data below shows exactly when each one wins.

These numbers are the raw output of VeSignal's benchmarker, captured on a live Roblox server with 120 frames sampled per cell.

:::caution FireDeferred ratios are misleading
`FireDeferred` shows ratios like `0.006x` and `0.028x` that look extraordinary — but they are a timing artifact, not a real performance win. `FireDeferred` does not execute any listeners. It calls `task.defer` and returns immediately. The benchmark measures the cost of *queuing* the work, not running it. All those deferred fires pile up and execute later, outside the measurement window. The actual listener execution cost is the same as `FireSync` — it just happens on the next cycle.

Use `FireDeferred` when you need to break re-entrance or intentionally delay execution. Do not use it to "go faster."
:::

---

## The Setup

- **Samples per cell:** 120 Heartbeat frames
- **Fires per frame:** 100
- **Baseline method:** FireSync

Four listener profiles, tested across five listener counts each. All values are wall-clock cost of 100 signal fires per Heartbeat. Run in an empty place for the cleanest results.

- **All-sync** — every listener registered with `Connect`
- **Half async** — half registered with `ConnectAsync`, half with `Connect`
- **All-async** — every listener registered with `ConnectAsync`
- **Once (reconnect)** — `Once` listeners that reconnect immediately after each fire

---

## All-Sync Listeners

When `AsyncCount == 0`, `Fire` takes the sync-only fast path and is effectively identical to `FireSync`. `FireDeferred` appears cheapest here but see the caveat above — its numbers measure scheduling cost only, not execution.

| Listeners | FireSync | Fire | FireAsync | FireDeferred | FireSafe |
|----------:|:--------:|:----:|:---------:|:------------:|:--------:|
| 10 | 0.05 ms | 0.047 ms | 0.177 ms | 0.133 ms | 0.131 ms |
| 100 | 0.354 ms | 0.375 ms | 1.659 ms | 0.126 ms | 1.262 ms |
| 500 | 1.892 ms | 2.17 ms | 7.403 ms | 0.127 ms | 5.678 ms |
| 1,000 | 3.852 ms | 3.684 ms | 14.589 ms | 0.107 ms | 10.463 ms |
| 5,000 | 18.539 ms | 18.974 ms | 76.019 ms | 0.116 ms | 62.485 ms |

**Throughput (fires/s) at 100 listeners:**

| FireSync | Fire | FireAsync | FireDeferred | FireSafe |
|:--------:|:----:|:---------:|:------------:|:--------:|
| 282,634 | 266,405 | 60,259 | 794,697 | 79,265 |

`Fire` and `FireSync` are essentially tied across all counts — the fast path kicks in whenever there are no async connections. `FireAsync` costs ~4× more due to thread dispatch overhead on every listener.

---

## Half-Async Listeners

Once async listeners are in the mix, `Fire` must snapshot both `Fn` and `IsAsync` per connection and conditionally resume threads. Cost roughly triples vs all-sync.

| Listeners | FireSync | Fire | FireAsync | FireDeferred | FireSafe |
|----------:|:--------:|:----:|:---------:|:------------:|:--------:|
| 10 | 0.05 ms | 0.125 ms | 0.175 ms | 0.113 ms | 0.206 ms |
| 100 | 0.362 ms | 1.07 ms | 1.808 ms | 0.123 ms | 1.793 ms |
| 500 | 1.873 ms | 5.105 ms | 7.57 ms | 0.122 ms | 8.506 ms |
| 1,000 | 3.676 ms | 10.068 ms | 14.656 ms | 0.105 ms | 16.091 ms |
| 5,000 | 19.548 ms | 55.725 ms | 77.676 ms | 0.11 ms | 87.212 ms |

`FireSync` ignores `IsAsync` entirely — it always calls every listener directly. If you need raw throughput and can tolerate blocking async listeners, `FireSync` is the right choice even in a mixed setup.

---

## All-Async Listeners

When every listener is async, `Fire` and `FireAsync` converge — both dispatch every listener to a pooled thread. `FireSync` remains the cheapest option here because it ignores the async flag and calls every listener directly on the firing coroutine.

| Listeners | FireSync | Fire | FireAsync | FireDeferred | FireSafe |
|----------:|:--------:|:----:|:---------:|:------------:|:--------:|
| 10 | 0.046 ms | 0.181 ms | 0.165 ms | 0.099 ms | 0.243 ms |
| 100 | 0.371 ms | 1.596 ms | 1.466 ms | 0.11 ms | 2.411 ms |
| 500 | 1.743 ms | 7.63 ms | 7.499 ms | 0.12 ms | 13.953 ms |
| 1,000 | 3.744 ms | 16.346 ms | 15.859 ms | 0.122 ms | 23.979 ms |
| 5,000 | 19.085 ms | 81.308 ms | 81.628 ms | 0.136 ms | 116.704 ms |

`FireSafe` is most expensive here because it deep-copies table arguments and wraps every listener in `pcall` — costs stack with listener count.

---

## Once Listeners (Reconnect)

Connection pool reuse dominates here. Each fire disconnects the listener, runs the callback, then the test immediately reconnects. Costs are dramatically lower than persistent listeners because the pool eliminates allocation overhead.

| Listeners | FireSync | Fire | FireAsync | FireDeferred | FireSafe |
|----------:|:--------:|:----:|:---------:|:------------:|:--------:|
| 10 | 0.011 ms | 0.011 ms | 0.015 ms | 0.109 ms | 0.015 ms |
| 100 | 0.025 ms | 0.026 ms | 0.039 ms | 0.100 ms | 0.037 ms |
| 500 | 0.088 ms | 0.089 ms | 0.151 ms | 0.102 ms | 0.136 ms |
| 1,000 | 0.174 ms | 0.178 ms | 0.294 ms | 0.161 ms | 0.265 ms |
| 5,000 | 1.004 ms | 0.943 ms | 1.646 ms | 0.131 ms | 1.507 ms |

`FireDeferred` is unusually slow at low counts (9.83× at 10 listeners) — the `task.defer` overhead dominates when the actual fire work is near-zero. It recovers at 1,000+ listeners where the deferred cost becomes proportionally negligible.

---

## What These Numbers Mean in Practice

**10–100 listeners** — all methods are fast. Pick based on semantics, not performance.

**100–1,000 listeners, all-sync** — `Fire` and `FireSync` are equivalent. Avoid `FireAsync` and `FireSafe` on hot paths.

**100–1,000 listeners, mixed or all-async** — `FireSync` is 3–4× faster than `Fire` if you can tolerate blocking async listeners. `FireDeferred` can offload execution to the next cycle, but the listeners still run — just later.

**1,000+ listeners** — `FireDeferred` has near-zero firing cost because it only queues work. Useful when you need to unblock the current frame. The listener execution cost still hits on the deferred cycle.

**Once-heavy patterns** — the connection pool makes reconnect-heavy code far cheaper than it looks. At 1,000 `Once` listeners, `Fire` costs 0.178ms — less than half the cost of 1,000 persistent async listeners.

---

## Running the Benchmarker

The benchmarker that produced these results is included as `Benchmarker.lua` in the `src` folder.

### Setup

1. Place `VeSignal` somewhere accessible (e.g. `ReplicatedStorage`)
2. Place `Benchmarker.lua` in `ServerScriptService`
3. Add an `ObjectValue` named `SignalReference` as a child of the script, with its `Value` pointing at the VeSignal `ModuleScript`
4. Require and run it from a `Script`:

```lua
local VeSignalBenchmark = require(ServerScriptService.Benchmarker)

local Benchmark = VeSignalBenchmark.new()
Benchmark:Run()
```

### Configuration

`VeSignalBenchmark.new()` accepts an optional config table:

```lua
local Benchmark = VeSignalBenchmark.new({
    ListenerCounts = { 10, 100, 500, 1000 },  -- which counts to test
    SampleFrames   = 120,                      -- Heartbeat frames sampled per cell
    WarmupFrames   = 30,                       -- frames discarded before sampling
    FiresPerFrame  = 100,                      -- fires issued per frame
    BaselineMethod = "FireSync",               -- method used for ratio calculations
})
```

All fields are optional — unset fields fall back to the defaults used for the numbers above.

### Reading the Output

Each cell prints as it finishes:

```
FireSync  | All-sync listeners  |  100 listeners | avg 0.354 ms  min 0.294  max 0.542  σ 0.071 | 282634 fires/s
Fire      | All-sync listeners  |  100 listeners | avg 0.375 ms  min 0.293  max 0.639  σ 0.087 | 266405 fires/s
  → Fire / FireSync ratio: 1.061x  [FireSync FASTER]
```

The `σ` column is standard deviation. High σ relative to the average means the frame time was inconsistent — usually GC pressure or Roblox scheduler noise during that window. Treat high-σ rows with skepticism and re-run if needed.
