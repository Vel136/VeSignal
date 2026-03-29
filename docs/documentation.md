---
sidebar_position: 2
sidebar_label: "Overview"
---

# VeSignal

Fast, type-safe signals for Roblox.

VeSignal is a pure Luau signal library with connection pooling, priority-ordered dispatch, async-aware firing modes, and UDTF-derived type signatures. Every signal is generic over its `Signature` type — fire, connect, and wait methods all resolve to the correct argument types automatically.

---

## Constructors

### `Signal.new()`

Creates a new signal. Optionally annotate it with a type cast:

```lua
local signal = Signal.new() :: Signal.Signal<(x: number) -> ()>
```

### `Signal.wrap(rbxSignal)`

Proxies a Roblox `RBXScriptSignal` into a VeSignal. All fires from the Roblox signal are forwarded through the wrapper:

```lua
local onTouch = Signal.wrap(part.Touched)
onTouch:Connect(function(hit) ... end)
```

Destroy the wrapper to also disconnect the underlying Roblox connection.

### `Signal.any(...)`

Returns a new signal that fires whenever **any** of the given signals fires. The new signal re-fires with the same arguments as the triggering input.

```lua
local either = Signal.any(signalA, signalB)
either:Connect(function(...) ... end)
```

Destroy the combined signal to clean up all input connections.

### `Signal.all(...)`

Returns a new signal that fires once **all** given signals have fired at least once. Fires with the arguments of the last signal to complete the set. Subsequent fires from any input continue to fire the combined signal.

```lua
local both = Signal.all(playerReady, mapReady)
both:Once(startGame)
```

---

## Connecting

All connect methods return a `Connection` object. Call `connection:Disconnect()` to remove it.

### `Connect(fn, priority?)`

Registers a synchronous listener. Listeners with higher priority run first; default priority is `0`.

```lua
signal:Connect(function(x) print(x) end)
signal:Connect(earlyHandler, 10)
```

`ConnectSync` is an alias for `Connect`.

### `ConnectAsync(fn, priority?)`

Registers a listener that runs in a pooled coroutine thread. The firing coroutine is not blocked and the listener may yield freely.

```lua
signal:ConnectAsync(function(x)
    task.wait(1)
    doSomething(x)
end)
```

### `ConnectIf(predicate, fn, priority?)`

Registers a sync listener that only runs when `predicate(...)` returns `true`. The predicate receives the same arguments as the listener.

```lua
signal:ConnectIf(
    function(player) return player.Team.Name == "Red" end,
    function(player) onRedTeamPlayer(player) end
)
```

### `ConnectIfAsync(predicate, fn, priority?)`

Same as `ConnectIf` but runs `fn` in a pooled thread.

### `Once(fn, priority?)`

Registers a listener that automatically disconnects after the first fire.

```lua
signal:Once(function(x) print("first fire:", x) end)
```

### `OnceAsync(fn, priority?)`

Same as `Once` but runs `fn` in a pooled thread.

### `OnceTimeout(fn, timeout, priority?)`

Registers a once listener with a deadline. If the signal fires before `timeout` seconds, `fn` is called and the connection is removed. If the timeout expires first, the connection is silently removed and `fn` is **not** called.

```lua
signal:OnceTimeout(function(x)
    print("fired in time:", x)
end, 5)
```

### `OnceAsyncTimeout(fn, timeout, priority?)`

Same as `OnceTimeout` but runs `fn` in a pooled thread.

---

## Firing

### `Fire(...)`

The standard fire method. Sync listeners are called directly; async listeners (`IsAsync = true`) are dispatched to pooled threads. This is the recommended default.

### `FireSync(...)`

Calls all listeners synchronously regardless of their `IsAsync` flag. The fastest firing mode — use when you know all listeners are sync and no re-entrance is expected.

### `FireAsync(...)`

Dispatches every listener to a pooled coroutine thread. Use when you want to guarantee the firing coroutine is never blocked, even by sync listeners.

### `FireDeferred(...)`

Schedules a `FireSync` on the next `task.defer` cycle. Useful for breaking re-entrance without losing the fire.

### `FireSafe(...)`

Like `Fire`, but wraps each listener in `pcall` and deep-copies all table arguments before dispatch. Errors are surfaced as `warn` output rather than propagating. Use when listeners are untrusted or arguments must not be mutated.

---

## Waiting

Both wait methods must be called from inside a coroutine or `task` context.

### `Wait(timeout, priority?)`

Yields the current coroutine until the signal fires, then returns the fire arguments. If `timeout > 0` and the signal does not fire in time, the coroutine resumes with no values.

```lua
local x = signal:Wait(5)
if x then
    print("got:", x)
else
    print("timed out")
end
```

### `WaitPriority(priority?)`

Yields until the signal fires. No timeout. The optional `priority` controls where in the listener queue the internal `Once` is inserted.

---

## Utility

### `GetListenerCount()`

Returns the number of currently active connections.

### `HasListeners()`

Returns `true` if at least one connection is active.

### `DisconnectAll()`

Disconnects every active connection and returns all connection objects to the pool.

### `Destroy()`

Calls `DisconnectAll`, then disconnects any proxied `RBXScriptSignal` and clears the signal table. Do not use the signal after calling this.

---

## Connection

The object returned by all connect methods.

| Property | Type | Description |
|----------|------|-------------|
| `Signal` | `Signal<Signature>` | The owning signal |
| `Connected` | `boolean` | `true` while the listener is active |
| `IsAsync` | `boolean` | `true` if the listener runs in a thread |
| `Priority` | `number` | Dispatch priority |
| `Fn` | `Signature` | The registered callback |

`Disconnect()` and `Destroy()` are aliases — both remove the listener and return the connection to the internal pool.
