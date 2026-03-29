# VeSignal

Fast, type-safe signals for Roblox.

**[Documentation](https://vel136.github.io/VeSignal/)** · **[Creator Store](https://create.roblox.com/store/asset/98802343952796/VeSignal)**

VeSignal is a high-performance Luau signal library with first-class support for the new Luau type solver. It features connection pooling, priority ordering, async-aware firing, and UDTF-derived type signatures so your IDE knows exactly what arguments `Fire` and `Wait` accept.

---

## Install

Get VeSignal from the **[Roblox Creator Store](https://create.roblox.com/store/asset/98802343952796/VeSignal)**, drop `VeSignal.lua` into `ReplicatedStorage`, and require it:

```lua
local Signal = require(ReplicatedStorage.VeSignal)
```

Requires the **new Luau type solver** for full type inference. Enable it in Studio under Beta Features.

---

## Quick Start

```lua
local Signal = require(ReplicatedStorage.VeSignal)

-- Create a typed signal
local onDamage = Signal.new() :: Signal.Signal<(victim: Player, amount: number) -> ()>

-- Connect a listener
onDamage:Connect(function(victim, amount)
    print(victim.Name, "took", amount, "damage")
end)

-- Fire it
onDamage:Fire(player, 25)
```

---

## API

### Constructors

| Function | Description |
|----------|-------------|
| `Signal.new()` | Creates a new signal |
| `Signal.wrap(rbxSignal)` | Proxies a `RBXScriptSignal` into a Signal |
| `Signal.any(...)` | Fires whenever **any** of the given signals fires |
| `Signal.all(...)` | Fires once all given signals have fired at least once |

### Connecting

| Method | Description |
|--------|-------------|
| `Connect(fn, priority?)` | Sync listener |
| `ConnectAsync(fn, priority?)` | Listener runs in a pooled thread |
| `ConnectIf(predicate, fn, priority?)` | Sync listener, only called when predicate passes |
| `ConnectIfAsync(predicate, fn, priority?)` | Async listener, only called when predicate passes |
| `Once(fn, priority?)` | Fires once then auto-disconnects |
| `OnceAsync(fn, priority?)` | Async once |
| `OnceTimeout(fn, timeout, priority?)` | Fires once or silently disconnects after `timeout` seconds |
| `OnceAsyncTimeout(fn, timeout, priority?)` | Async version of `OnceTimeout` |

### Firing

| Method | Description |
|--------|-------------|
| `Fire(...)` | Respects per-connection `IsAsync` flag |
| `FireSync(...)` | All listeners called synchronously |
| `FireAsync(...)` | All listeners run in pooled threads |
| `FireDeferred(...)` | Fires on the next resumption cycle via `task.defer` |
| `FireSafe(...)` | `pcall`-wrapped, deep-copies table args |

### Waiting

| Method | Description |
|--------|-------------|
| `Wait(timeout, priority?)` | Yields until fired or timeout expires |
| `WaitPriority(priority?)` | Yields until fired, with optional priority |

### Utility

| Method | Description |
|--------|-------------|
| `GetListenerCount()` | Returns number of active connections |
| `HasListeners()` | Returns `true` if any listeners are connected |
| `DisconnectAll()` | Disconnects and pools all connections |
| `Destroy()` | Disconnects all and clears the signal |

---

## Priority

Higher-priority listeners run first. Default priority is `0`. Pass a positive integer to front-run, negative to run last:

```lua
signal:Connect(lateHandler, -1)   -- runs last
signal:Connect(earlyHandler, 10)  -- runs first
```

---

## License

MIT — Copyright © 2026 VeDevelopment
