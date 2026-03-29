---
sidebar_position: 4
---

# FAQ

Answers to the questions that come up most often.

---

## General

**What is VeSignal?**

VeSignal is a high-performance Luau signal library for Roblox. It provides typed, priority-ordered events with connection pooling, multiple firing modes, and UDTF-derived type signatures that propagate your signal's `Signature` type to `Fire`, `Wait`, and all connect methods.

---

**Does VeSignal require the new Luau type solver?**

Only for full type inference. VeSignal works at runtime under the classic solver, but the UDTF type functions (`FireSignature`, `WaitSignature`) that derive `Fire` and `Wait` signatures require `--!strict` with the new solver enabled.

---

**Is VeSignal free?**

Yes. VeSignal is released under the MIT License.

---

**Can I use VeSignal on both the server and client?**

Yes. VeSignal has no `RunService` dependency. Require it on the server, client, or any shared `ModuleScript`.

---

## Connections

**What's the difference between `Connect` and `ConnectAsync`?**

`Connect` calls the listener synchronously on the firing coroutine. `ConnectAsync` dispatches the listener to a pooled coroutine thread — the firing coroutine continues immediately and the listener runs independently. Use `ConnectAsync` whenever a listener needs to yield.

---

**What does `ConnectIf` do differently from guarding inside the callback?**

The result is the same for sync connections, but `ConnectIf` keeps the guard at the call site and makes intent explicit. For `ConnectIfAsync`, there is an additional benefit: if the predicate fails, no thread is acquired and no resume overhead is paid.

---

**When should I use `OnceTimeout` over `Once`?**

Use `OnceTimeout` when the event is expected but not guaranteed within a known window — button presses, server acknowledgements, NPC interactions. If the event never fires, `OnceTimeout` cleans up the connection automatically so there is no leak.

---

**What happens if `OnceTimeout` fires and the signal also fires?**

The `done` flag ensures only the first one wins. If the signal fires before the timeout, the callback is called and the timeout fires silently with no effect. If the timeout fires first, the connection is removed and the signal fire is ignored.

---

**What happens to connections when a signal is destroyed?**

`Destroy` calls `DisconnectAll`, which disconnects every active connection and returns them to the internal pool. If the signal wraps a `RBXScriptSignal`, the underlying Roblox connection is also disconnected.

---

## Firing

**Which `Fire` variant should I use by default?**

Use `Fire`. It respects each connection's `IsAsync` flag — sync listeners run directly, async listeners are dispatched to threads. It has a fast path when all listeners are sync (zero thread overhead).

---

**When should I use `FireSync`?**

When you know all listeners are sync and want the lowest possible overhead. `FireSync` skips all async bookkeeping entirely.

---

**When should I use `FireDeferred`?**

When you want to break re-entrance. If a signal fires while it is already firing, VeSignal defers the second fire via `task.defer`. `FireDeferred` always defers — useful when you intentionally want the fire to happen on the next cycle.

---

**When should I use `FireSafe`?**

When listeners are untrusted (user plugins, modular systems) or when you need to guarantee that arguments are not mutated across listeners. `FireSafe` deep-copies table arguments and wraps each listener in `pcall`, surfacing errors as `warn` output.

---

## Combinators

**Does `Signal.any` fire once or every time?**

Every time. The combined signal re-fires whenever any input fires. If you only want the first, call `Once` on the combined signal.

---

**Does `Signal.all` fire every time after all inputs have fired?**

Yes. Once the "all inputs have fired" threshold is crossed, every subsequent fire from any input triggers the combined signal. If you want a one-shot, call `Once` on the combined signal.

---

**Do I need to destroy combined signals?**

Yes, if the combined signal is no longer needed. Its `Destroy` method disconnects all input connections. If you only call `Destroy` on the input signals without destroying the combined signal, the internal connections are left dangling.

---

## Priority

**What is the default priority?**

`0`. Connections with the same priority fire in insertion order.

**Does a higher number mean higher or lower priority?**

Higher number = runs first. Use positive integers to front-run default listeners, negative integers to run last.

---

## Performance

**Is VeSignal safe to call every frame?**

Yes. `Fire` and `Connect`/`Disconnect` are designed for hot paths. Connections are pooled (up to 1000 by default) to avoid allocation on reconnect-heavy code paths. Thread pools are reused across fires.

---

**What is the connection pool?**

When a connection is disconnected, VeSignal holds it in an internal pool rather than letting it be garbage collected. The next `Connect` call reuses a pooled object instead of allocating a new table. The pool cap is 1000 connections.
