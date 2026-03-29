-- MIT License
--
-- Copyright (c) 2026 Ve Development

--[=[
	@class Signal

	Fast, type-safe signals for Roblox.

	VeSignal provides typed, priority-ordered events with connection pooling,
	multiple firing modes, and UDTF-derived type signatures. The `Signature`
	generic propagates to `Fire`, `Wait`, and all connect methods so your IDE
	catches argument type errors automatically.

	Requires the **new Luau type solver** for full generic inference.

	```lua
	local Signal = require(ReplicatedStorage.VeSignal)

	local onDamage = Signal.new() :: Signal.Signal<(victim: Player, amount: number) -> ()>

	onDamage:Connect(function(victim, amount)
	    print(victim.Name, "took", amount, "damage")
	end)

	onDamage:Fire(player, 25)
	```
]=]
local Signal = {}

-- ─── Constructors ─────────────────────────────────────────────────────────────

--[=[
	@function new
	@within Signal

	Creates a new signal. Optionally annotate it with a type cast to lock in
	the `Signature` generic.

	```lua
	local signal = Signal.new() :: Signal.Signal<(x: number) -> ()>
	```

	@return Signal<Signature>
]=]
function Signal.new() end

--[=[
	@function wrap
	@within Signal

	Proxies a Roblox `RBXScriptSignal` into a VeSignal. All fires from the
	Roblox signal are forwarded through the wrapper. Destroying the wrapper also
	disconnects the underlying Roblox connection.

	```lua
	local onTouch = Signal.wrap(workspace.Part.Touched)
	onTouch:Connect(function(hit) ... end)
	```

	@param rbxSignal RBXScriptSignal -- The Roblox signal to wrap.
	@return Signal<Signature>
]=]
function Signal.wrap(rbxSignal: RBXScriptSignal) end

--[=[
	@function any
	@within Signal

	Returns a new signal that fires whenever **any** of the given signals fires.
	The combined signal re-fires with the same arguments as the triggering input.

	Destroy the combined signal to clean up all input connections.

	```lua
	local either = Signal.any(signalA, signalB)
	either:Connect(function(...) ... end)
	either:Destroy()
	```

	@param ... Signal<Signature> -- Two or more signals to combine.
	@return Signal<Signature>
]=]
function Signal.any(...) end

--[=[
	@function all
	@within Signal

	Returns a new signal that fires once **all** given signals have fired at
	least once. Fires with the arguments of the last signal to complete the set.
	Subsequent fires from any input continue to fire the combined signal.

	```lua
	local both = Signal.all(playerReady, mapReady)
	both:Once(startGame)
	```

	@param ... Signal<Signature> -- Two or more signals to combine.
	@return Signal<Signature>
]=]
function Signal.all(...) end

-- ─── Connecting ───────────────────────────────────────────────────────────────

--[=[
	@method Connect
	@within Signal

	Registers a synchronous listener. Listeners with higher `priority` run
	first; the default priority is `0`. Connections with the same priority fire
	in insertion order.

	```lua
	local conn = signal:Connect(function(x) print(x) end)
	conn:Disconnect()
	```

	`ConnectSync` is an alias for `Connect`.

	@param fn Signature -- The callback to invoke when the signal fires.
	@param priority number? -- Dispatch priority. Higher runs first. Default: `0`.
	@return Connection<Signature>
]=]
function Signal:Connect(fn, priority) end

--[=[
	@method ConnectAsync
	@within Signal

	Registers a listener that runs in a pooled coroutine thread. The firing
	coroutine is not blocked and the listener may yield freely.

	```lua
	signal:ConnectAsync(function(x)
	    task.wait(1)
	    doSomething(x)
	end)
	```

	@param fn Signature -- The callback to invoke in a pooled thread.
	@param priority number? -- Dispatch priority. Default: `0`.
	@return Connection<Signature>
]=]
function Signal:ConnectAsync(fn, priority) end

--[=[
	@method ConnectIf
	@within Signal

	Registers a synchronous listener that only runs when `predicate(...)` returns
	`true`. The predicate receives the same arguments as the listener.

	```lua
	signal:ConnectIf(
	    function(player) return player.Team.Name == "Red" end,
	    function(player) onRedTeamPlayer(player) end
	)
	```

	@param predicate (...any) -> boolean -- Called with the fire arguments. Listener runs only when this returns `true`.
	@param fn Signature -- The callback to invoke when the predicate passes.
	@param priority number? -- Dispatch priority. Default: `0`.
	@return Connection<Signature>
]=]
function Signal:ConnectIf(predicate, fn, priority) end

--[=[
	@method ConnectIfAsync
	@within Signal

	Same as [Signal:ConnectIf] but runs `fn` in a pooled coroutine thread.

	@param predicate (...any) -> boolean -- Called with the fire arguments. Listener runs only when this returns `true`.
	@param fn Signature -- The callback to invoke in a pooled thread.
	@param priority number? -- Dispatch priority. Default: `0`.
	@return Connection<Signature>
]=]
function Signal:ConnectIfAsync(predicate, fn, priority) end

--[=[
	@method Once
	@within Signal

	Registers a listener that automatically disconnects after the first fire.

	```lua
	signal:Once(function(x) print("first fire:", x) end)
	```

	@param fn Signature -- The callback to invoke once.
	@param priority number? -- Dispatch priority. Default: `0`.
	@return Connection<Signature>
]=]
function Signal:Once(fn, priority) end

--[=[
	@method OnceAsync
	@within Signal

	Same as [Signal:Once] but runs `fn` in a pooled coroutine thread.

	@param fn Signature -- The callback to invoke once, in a pooled thread.
	@param priority number? -- Dispatch priority. Default: `0`.
	@return Connection<Signature>
]=]
function Signal:OnceAsync(fn, priority) end

--[=[
	@method OnceTimeout
	@within Signal

	Registers a once listener with a deadline. If the signal fires before
	`timeout` seconds, `fn` is called and the connection is removed. If the
	timeout expires first, the connection is silently removed and `fn` is
	**not** called.

	```lua
	buttonPressed:OnceTimeout(function()
	    openDoor()
	end, 3)
	```

	@param fn Signature -- The callback to invoke if the signal fires in time.
	@param timeout number -- Seconds to wait before silently disconnecting.
	@param priority number? -- Dispatch priority. Default: `0`.
	@return Connection<Signature>
]=]
function Signal:OnceTimeout(fn, timeout, priority) end

--[=[
	@method OnceAsyncTimeout
	@within Signal

	Same as [Signal:OnceTimeout] but runs `fn` in a pooled coroutine thread.

	@param fn Signature -- The callback to invoke in a pooled thread if the signal fires in time.
	@param timeout number -- Seconds to wait before silently disconnecting.
	@param priority number? -- Dispatch priority. Default: `0`.
	@return Connection<Signature>
]=]
function Signal:OnceAsyncTimeout(fn, timeout, priority) end

-- ─── Firing ───────────────────────────────────────────────────────────────────

--[=[
	@method Fire
	@within Signal

	Fires the signal. Sync listeners are called directly on the current
	coroutine; async listeners (`IsAsync = true`) are dispatched to pooled
	threads. This is the recommended default firing method.

	Has a fast path when `AsyncCount == 0` — skips all thread machinery.

	@param ... any -- Arguments forwarded to every listener.
]=]
function Signal:Fire(...) end

--[=[
	@method FireSync
	@within Signal

	Calls all listeners synchronously regardless of their `IsAsync` flag. The
	fastest firing mode. Use when all listeners are sync and re-entrance is not
	expected.

	@param ... any -- Arguments forwarded to every listener.
]=]
function Signal:FireSync(...) end

--[=[
	@method FireAsync
	@within Signal

	Dispatches every listener to a pooled coroutine thread. Guarantees the
	firing coroutine is never blocked, even by sync-registered listeners.

	@param ... any -- Arguments forwarded to every listener.
]=]
function Signal:FireAsync(...) end

--[=[
	@method FireDeferred
	@within Signal

	Schedules a [Signal:FireSync] on the next `task.defer` cycle. Use to break
	re-entrance or to guarantee the fire happens after the current frame.

	@param ... any -- Arguments forwarded to every listener.
]=]
function Signal:FireDeferred(...) end

--[=[
	@method FireSafe
	@within Signal

	Fires the signal with per-listener `pcall` protection and deep-copied table
	arguments. Errors are surfaced as `warn` output rather than propagating. Use
	when listeners are untrusted or arguments must not be mutated across
	listeners.

	@param ... any -- Arguments deep-copied and forwarded to every listener.
]=]
function Signal:FireSafe(...) end

-- ─── Waiting ──────────────────────────────────────────────────────────────────

--[=[
	@method Wait
	@within Signal

	Yields the current coroutine until the signal fires, then returns the fire
	arguments. Must be called from inside a coroutine or `task` context.

	If `timeout > 0` and the signal does not fire in time, the coroutine resumes
	with no return values.

	```lua
	local winner = roundEnded:Wait(60)
	if winner then
	    displayWinner(winner)
	else
	    displayDraw()
	end
	```

	@param timeout number -- Maximum seconds to wait. Pass `0` or omit for no timeout.
	@param priority number? -- Dispatch priority for the internal listener. Default: `0`.
	@return ...any -- The arguments the signal was fired with, or nothing on timeout.
]=]
function Signal:Wait(timeout, priority) end

--[=[
	@method WaitPriority
	@within Signal

	Yields until the signal fires. No timeout. The optional `priority` controls
	where the internal listener is inserted in the queue. Must be called from
	inside a coroutine or `task` context.

	@param priority number? -- Dispatch priority. Default: `0`.
	@return ...any -- The arguments the signal was fired with.
]=]
function Signal:WaitPriority(priority) end

-- ─── Utility ──────────────────────────────────────────────────────────────────

--[=[
	@method GetListenerCount
	@within Signal

	Returns the number of currently active connections.

	@return number
]=]
function Signal:GetListenerCount() end

--[=[
	@method HasListeners
	@within Signal

	Returns `true` if at least one connection is active.

	@return boolean
]=]
function Signal:HasListeners() end

--[=[
	@method DisconnectAll
	@within Signal

	Disconnects every active connection and returns all connection objects to
	the internal pool. The signal remains usable after this call.
]=]
function Signal:DisconnectAll() end

--[=[
	@method Destroy
	@within Signal

	Disconnects all listeners, disconnects any proxied `RBXScriptSignal`, and
	clears the signal table. Do not use the signal after calling this.
]=]
function Signal:Destroy() end

return Signal
