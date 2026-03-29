---
sidebar_position: 1
---

# Getting Started

VeSignal is a single-file Luau module. Install it, require it, and start connecting.

---

## Installation

Get VeSignal from the Roblox Creator Store:

**[Get VeSignal on Creator Store](https://create.roblox.com/store/asset/98802343952796/VeSignal)**

Drop `VeSignal.lua` into `ReplicatedStorage` (or any shared module location) and require it:

```lua
local Signal = require(ReplicatedStorage.VeSignal)
```

VeSignal requires the **new Luau type solver** for full generic type inference. Enable it in Studio under Beta Features → New Luau Solver.

---

## Your First Signal

```lua
local Signal = require(ReplicatedStorage.VeSignal)

local onDamage = Signal.new() :: Signal.Signal<(victim: Player, amount: number) -> ()>

-- Connect a listener
local connection = onDamage:Connect(function(victim, amount)
    print(victim.Name, "took", amount, "damage")
end)

-- Fire the signal
onDamage:Fire(player, 25)

-- Clean up when done
connection:Disconnect()
```

---

## Typed Signals

Declare the signal's signature with a type cast. VeSignal's UDTF type functions propagate the signature to `Fire`, `Wait`, and all connect methods so your IDE catches type errors automatically:

```lua
-- Fire's signature is inferred as (self, victim: Player, amount: number) -> ()
onDamage:Fire(player, 25)    -- ok
onDamage:Fire("bad", true)   -- type error
```

---

## Async Listeners

Use `ConnectAsync` for listeners that should run in their own thread and not block the firing coroutine:

```lua
onDamage:ConnectAsync(function(victim, amount)
    -- Runs in a pooled thread — yielding here is safe
    task.wait(0.5)
    applyBloodEffect(victim)
end)
```

---

## Priority

Listeners with higher priority numbers run first. Default is `0`:

```lua
signal:Connect(earlyHandler, 10)   -- runs first
signal:Connect(normalHandler)      -- priority 0
signal:Connect(lateHandler, -1)    -- runs last
```

---

## Combinators

React to multiple signals at once without boilerplate:

```lua
-- Fires whenever either signal fires
local either = Signal.any(playerSpawned, mapLoaded)

-- Fires once both have fired at least once
local both = Signal.all(playerSpawned, mapLoaded)
both:Once(function()
    startGame()
end)
```

---

## Quick Reference

| I want to… | Method |
|------------|--------|
| Connect a sync listener | [`Connect`](./documentation#connecting) |
| Connect an async listener | [`ConnectAsync`](./documentation#connecting) |
| Connect with a condition | [`ConnectIf`](./documentation#connecting) |
| Connect once | [`Once`](./documentation#connecting) |
| Connect once with a deadline | [`OnceTimeout`](./documentation#connecting) |
| Fire all listeners | [`Fire`](./documentation#firing) |
| Fire without blocking | [`FireAsync`](./documentation#firing) |
| Yield until the signal fires | [`Wait`](./documentation#waiting) |
| Combine signals | [`Signal.any` / `Signal.all`](./documentation#constructors) |
| See practical examples | [Use Cases](./guides/use-cases) |
