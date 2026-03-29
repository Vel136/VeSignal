---
sidebar_position: 1
---

# Use Cases

Practical patterns for the most common VeSignal use-cases.

---

## Basic Events

The simplest use: a custom event that any script can listen to.

```lua
-- In a shared module
local Signal = require(ReplicatedStorage.VeSignal)

local GameEvents = {}
GameEvents.onRoundEnd  = Signal.new() :: Signal.Signal<(winner: string) -> ()>
GameEvents.onPlayerDie = Signal.new() :: Signal.Signal<(player: Player) -> ()>

return GameEvents
```

```lua
-- In any listener script
GameEvents.onRoundEnd:Connect(function(winner)
    showWinScreen(winner)
end)
```

---

## Once — React to Something One Time

Use `Once` when you only care about the first occurrence.

```lua
-- Show a welcome message the first time the player enters a zone
zone.onEntered:Once(function(player)
    showTutorialPrompt(player)
end)
```

---

## OnceTimeout — With a Deadline

Use `OnceTimeout` when an event is expected but you need a fallback if it doesn't happen in time.

```lua
-- Wait up to 3 seconds for the player to press the button
buttonPressed:OnceTimeout(function()
    openDoor()
end, 3)

-- If 3 seconds pass with no press, the connection silently clears
-- and openDoor is never called
```

---

## ConnectIf — Filter at the Source

Use `ConnectIf` to avoid boilerplate guards inside your callback.

```lua
-- Without ConnectIf
onPlayerAction:Connect(function(player, action)
    if player.Team.Name ~= "Red" then return end
    handleRedAction(player, action)
end)

-- With ConnectIf
onPlayerAction:ConnectIf(
    function(player) return player.Team.Name == "Red" end,
    handleRedAction
)
```

---

## ConnectAsync — Non-Blocking Listeners

Use `ConnectAsync` when a listener needs to yield (network calls, animations, delays) without blocking other listeners or the firing script.

```lua
onDamage:ConnectAsync(function(victim, amount)
    -- Safe to yield here
    task.wait(0.1)
    playHitAnimation(victim)
    task.wait(0.4)
    playRecoveryAnimation(victim)
end)
```

---

## Priority — Control Execution Order

Listeners execute in descending priority order (highest first). Default is `0`.

```lua
-- Validation runs before effects
onAbilityUsed:Connect(validateAbility,  10)   -- first
onAbilityUsed:Connect(applyEffect,       0)   -- second
onAbilityUsed:Connect(logToAnalytics,   -5)   -- last
```

---

## Signal.any — React to Whichever Fires First

Useful when multiple sources can trigger the same response.

```lua
local playerDied = Signal.any(
    characterDied,
    fallDamageKilled,
    poisonKilled
)

playerDied:Connect(function(player)
    respawnPlayer(player)
end)

-- Clean up when done
playerDied:Destroy()
```

---

## Signal.all — Wait for Multiple Conditions

Useful for initialization sequences that require several systems to be ready.

```lua
local ready = Signal.all(assetsLoaded, playerDataLoaded, mapGenerated)

ready:Once(function()
    -- All three have fired — safe to start
    startGame()
end)
```

---

## Wait — Yield Until an Event

Use `Wait` inside a `task.spawn` or coroutine to pause until a signal fires.

```lua
task.spawn(function()
    local winner = roundEnded:Wait(60)  -- timeout after 60 seconds
    if winner then
        displayWinner(winner)
    else
        displayDraw()
    end
end)
```

---

## Wrapping Roblox Events

Proxy a `RBXScriptSignal` into VeSignal to use the full API (priorities, async listeners, combinators, etc.) on native Roblox events.

```lua
local onTouch = Signal.wrap(workspace.Part.Touched)

onTouch:ConnectIf(
    function(hit) return hit.Parent:FindFirstChild("Humanoid") ~= nil end,
    function(hit) onCharacterTouch(hit.Parent) end
)
```

Destroying the wrapper also disconnects the underlying Roblox connection.

---

## FireSafe — Untrusted Listeners

Use `FireSafe` when listeners come from user-provided code or when arguments must not be mutated across listeners.

```lua
-- Each listener gets a fresh copy of the event data
-- Errors in any listener are warned, not propagated
pluginEvent:FireSafe({ action = "reload", config = currentConfig })
```
