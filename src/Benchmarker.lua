--!strict
--!optimize 2

--[[
	MIT License
	Copyright (c) 2026 VeDevelopment

	VeSignalBenchmark — Fire method vs listener-count performance profiler.

	Measures frame time, throughput, and overhead ratio across a configurable
	range of listener counts and listener profiles.

	HOW TO SET UP:
	  1. Place the VeSignal ModuleScript somewhere accessible (e.g. ReplicatedStorage)
	  2. Add an ObjectValue named "SignalReference" as a child of this script,
	     pointing at the VeSignal ModuleScript
	  3. Drop this ModuleScript into ServerScriptService
	  4. Require it, create a Benchmark instance, and call :Run()

	WHAT IS MEASURED:
	  • Frame time  (ms) — average Heartbeat wall-clock duration while firing N times per frame
	  • Throughput       — total signal fires processed per second
	  • Overhead ratio   — alternative fire method / baseline (FireSync) frame time

	USAGE:
	  local VeSignalBenchmark = require(ServerScriptService.VeSignalBenchmark)

	  local Benchmark = VeSignalBenchmark.new({
	      ListenerCounts = { 10, 100, 500, 1000 },
	      SampleFrames   = 120,
	      FiresPerFrame  = 50,
	  })

	  Benchmark:Run()
]]

-- ─── Identity ──────────────────────────────────────────────────────────────────

local Identity   = "VeSignalBenchmark"
local Benchmark  = {}
Benchmark.__type = Identity

-- ─── Services ──────────────────────────────────────────────────────────────────

local RunService = game:GetService("RunService")

-- ─── Module References ─────────────────────────────────────────────────────────

local SignalReference = script:WaitForChild("SignalReference", 10)
if not SignalReference then
	error("[" .. Identity .. "] Missing SignalReference ObjectValue as a child of this script.")
end

local SignalModule = (SignalReference :: ObjectValue).Value
if not SignalModule then
	error("[" .. Identity .. "] SignalReference ObjectValue has no Value set — point it at the VeSignal ModuleScript.")
end

-- ─── Types ─────────────────────────────────────────────────────────────────────

export type BenchmarkConfig = {
	--- Listener counts to test at each profile.
	ListenerCounts         : { number }?,
	--- Number of signal fires issued per Heartbeat frame during sampling.
	FiresPerFrame          : number?,
	--- Heartbeat frames to sample per (method × count × profile) cell.
	SampleFrames           : number?,
	--- Frames to wait after connecting listeners before sampling begins.
	WarmupFrames           : number?,
	--- Baseline fire method name used for ratio calculations.
	BaselineMethod         : string?,
}

export type ListenerProfile = {
	--- Display name shown in output.
	name        : string,
	--- Fraction of connections that are async (0 = all sync, 1 = all async).
	asyncRatio  : number,
	--- If true the benchmark uses :Once instead of :Connect (measures reconnect overhead).
	useOnce     : boolean?,
}

export type SampleResult = {
	methodName     : string,
	profile        : string,
	listenerCount  : number,
	avgFrameMs     : number,
	minFrameMs     : number,
	maxFrameMs     : number,
	stdDevMs       : number,
	throughput     : number,
}

export type ResultGroup = {
	[string]: SampleResult,   -- keyed by methodName
}

-- ─── Default Configuration ─────────────────────────────────────────────────────

local DEFAULT_CONFIG: BenchmarkConfig = {
	ListenerCounts = { 10, 50, 100, 250, 500, 1000, 2500, 5000 },
	FiresPerFrame  = 100,
	SampleFrames   = 120,
	WarmupFrames   = 30,
	BaselineMethod = "FireSync",
}

-- ─── Default Listener Profiles ─────────────────────────────────────────────────

local DEFAULT_PROFILES: { ListenerProfile } = {
	{
		name       = "All-sync listeners",
		asyncRatio = 0,
	},
	{
		name       = "Half async listeners",
		asyncRatio = 0.5,
	},
	{
		name       = "All-async listeners",
		asyncRatio = 1,
	},
	{
		name       = "Once listeners (reconnect)",
		asyncRatio = 0,
		useOnce    = true,
	},
}

-- ─── Fire Methods ──────────────────────────────────────────────────────────────
-- Each entry maps a display name to the method name called on the signal.
-- The order here controls the order results are printed.

local FIRE_METHODS: { { name: string, method: string } } = {
	{ name = "FireSync",     method = "FireSync"     },
	{ name = "Fire",         method = "Fire"         },
	{ name = "FireAsync",    method = "FireAsync"     },
	{ name = "FireDeferred", method = "FireDeferred"  },
	{ name = "FireSafe",     method = "FireSafe"      },
}

-- ─── Utility ───────────────────────────────────────────────────────────────────

local function FormatNumber(n: number, decimals: number): string
	local factor = 10 ^ decimals
	return tostring(math.round(n * factor) / factor)
end

-- ─── Connection Helpers ────────────────────────────────────────────────────────

--- Connects `count` listeners to `signal` according to the profile.
--- Returns the list of connections so they can be cleaned up.
local function ConnectListeners(
	signal        : any,
	count         : number,
	profile       : ListenerProfile
): { any }
	local connections: { any } = table.create(count)
	local asyncRatio = profile.asyncRatio
	local useOnce    = profile.useOnce

	local noop = function() end

	for i = 1, count do
		local isAsync = (i / count) <= asyncRatio

		local conn
		if useOnce then
			-- Once disconnects itself; we don't need to track it for cleanup.
			if isAsync then
				signal:OnceAsync(noop)
			else
				signal:Once(noop)
			end
		else
			if isAsync then
				conn = signal:ConnectAsync(noop)
			else
				conn = signal:Connect(noop)
			end
			connections[i] = conn
		end
	end

	return connections
end

--- Disconnects all connections returned by ConnectListeners.
local function DisconnectAll(connections: { any })
	for _, conn in connections do
		if conn and conn.Connected then
			conn:Disconnect()
		end
	end
end

-- ─── Sample Collection ─────────────────────────────────────────────────────────

--- Connects `listenerCount` listeners, warms up, then collects `SampleFrames`
--- wall-clock readings while firing the signal `FiresPerFrame` times each frame.
local function CollectSamples(
	Signal         : any,
	methodName     : string,
	fireMethod     : string,
	listenerCount  : number,
	profile        : ListenerProfile,
	Config         : BenchmarkConfig
): SampleResult

	local SampleFrames = Config.SampleFrames  :: number
	local WarmupFrames = Config.WarmupFrames  :: number
	local FiresPerFrame = Config.FiresPerFrame :: number

	-- Connect listeners according to the profile.
	local connections = ConnectListeners(Signal, listenerCount, profile)

	-- Let the scheduler settle before measuring.
	for _ = 1, WarmupFrames do
		RunService.Heartbeat:Wait()
	end

	-- If the profile uses Once, listeners self-disconnected during warmup —
	-- reconnect them fresh so the sample window has the right listener count.
	if profile.useOnce then
		for _ = 1, WarmupFrames * FiresPerFrame do
			-- drain any pending deferred fires from warmup
		end
		connections = ConnectListeners(Signal, listenerCount, profile)
	end

	local fireSignal = Signal[fireMethod]

	local Samples: { number } = table.create(SampleFrames)

	for i = 1, SampleFrames do
		-- For Once profiles, reconnect listeners each frame so they're always present.
		if profile.useOnce then
			connections = ConnectListeners(Signal, listenerCount, profile)
		end

		local T0 = os.clock()

		for _ = 1, FiresPerFrame do
			fireSignal(Signal)
		end

		Samples[i] = (os.clock() - T0) * 1000
		RunService.Heartbeat:Wait()
	end

	DisconnectAll(connections)

	-- ── Reduce ────────────────────────────────────────────────────────────────
	local Sum  = 0
	local MinV = math.huge
	local MaxV = -math.huge

	for _, V in Samples do
		Sum  += V
		MinV  = math.min(MinV, V)
		MaxV  = math.max(MaxV, V)
	end

	local Avg = Sum / SampleFrames

	local Variance = 0
	for _, V in Samples do
		local Delta = V - Avg
		Variance   += Delta * Delta
	end
	local StdDev = math.sqrt(Variance / SampleFrames)

	-- Throughput: (fires per frame × frames per second).
	local FPS        = 1000 / Avg
	local Throughput = FiresPerFrame * FPS

	return {
		methodName    = methodName,
		profile       = profile.name,
		listenerCount = listenerCount,
		avgFrameMs    = Avg,
		minFrameMs    = MinV,
		maxFrameMs    = MaxV,
		stdDevMs      = StdDev,
		throughput    = Throughput,
	}
end

-- ─── Printing Helpers ──────────────────────────────────────────────────────────

local SEPARATOR_HEAVY = string.rep("─", 80)
local SEPARATOR_LIGHT = string.rep("─", 80)

local function PrintHeader(Config: BenchmarkConfig)
	print("")
	print(SEPARATOR_HEAVY)
	print("  VeSignal  —  Fire Method Benchmark")
	print(string.format("  Samples per cell : %d frames",    Config.SampleFrames  :: number))
	print(string.format("  Fires per frame  : %d",           Config.FiresPerFrame :: number))
	print(string.format("  Baseline method  : %s",           Config.BaselineMethod :: string))
	print(SEPARATOR_HEAVY)
	print("  NOTE: frame time = wall-clock cost of FiresPerFrame signal fires per Heartbeat.")
	print("        Values are relative — run in an empty place for cleanest results.")
	print("")
end

local function PrintResult(Result: SampleResult)
	print(string.format(
		"  %-14s | %-26s | %5d listeners | avg %s ms  min %s  max %s  σ %s | %s fires/s",
		Result.methodName,
		Result.profile,
		Result.listenerCount,
		FormatNumber(Result.avgFrameMs, 3),
		FormatNumber(Result.minFrameMs, 3),
		FormatNumber(Result.maxFrameMs, 3),
		FormatNumber(Result.stdDevMs,   3),
		FormatNumber(Result.throughput, 0)
		))
end

local function PrintComparison(Baseline: SampleResult, Other: SampleResult)
	local Ratio  = Other.avgFrameMs / Baseline.avgFrameMs
	local Winner = if Ratio < 0.95 then Other.methodName .. " FASTER"
		elseif Ratio > 1.05 then Baseline.methodName .. " FASTER"
		else "ROUGHLY EQUAL"

	print(string.format(
		"    → %s / %s ratio: %sx  [%s]",
		Other.methodName,
		Baseline.methodName,
		FormatNumber(Ratio, 3),
		Winner
		))
end

local function PrintSummary(AllGroups: { { profile: string, count: number, results: ResultGroup } }, BaselineMethod: string)
	print("")
	print(SEPARATOR_HEAVY)
	print("  SUMMARY")
	print(SEPARATOR_LIGHT)
	print(string.format(
		"  %-28s  %-5s  %-14s  %-14s  %-8s",
		"Profile · Listeners", "Count", "Method", "avg ms", "vs " .. BaselineMethod
		))
	print(SEPARATOR_LIGHT)

	for _, Group in AllGroups do
		local Baseline = Group.results[BaselineMethod]

		for _, Entry in FIRE_METHODS do
			local Result = Group.results[Entry.name]
			if not Result then continue end

			local RatioStr = "n/a"
			if Baseline and Entry.name ~= BaselineMethod then
				local Ratio = Result.avgFrameMs / Baseline.avgFrameMs
				RatioStr = FormatNumber(Ratio, 3) .. "x"
			elseif Entry.name == BaselineMethod then
				RatioStr = "baseline"
			end

			print(string.format(
				"  %-24s ×%-5d  %-14s  %-14s  %-8s",
				Group.profile:sub(1, 24),
				Group.count,
				Entry.name,
				FormatNumber(Result.avgFrameMs, 3) .. " ms",
				RatioStr
				))
		end

		print(SEPARATOR_LIGHT)
	end

	print(string.format("  [%s] Done.", Identity))
	print("")
end

-- ─── Public API ────────────────────────────────────────────────────────────────

local BenchmarkMetatable = table.freeze({ __index = Benchmark })

--- Runs the full benchmark suite across all configured profiles and listener counts.
--- Blocks the calling coroutine until complete — wrap in task.spawn if needed.
function Benchmark.Run(self: any)
	assert(not self._Ran, "[" .. Identity .. "] Run() called more than once on the same instance.")
	self._Ran = true

	local Config        = self._Config
	local Signal        = self._Signal
	local Profiles      = self._Profiles
	local BaselineMethod = Config.BaselineMethod :: string

	local AllGroups: { { profile: string, count: number, results: ResultGroup } } = {}

	task.wait(2)
	PrintHeader(Config)

	local ListenerCounts = Config.ListenerCounts :: { number }

	for _, Profile in Profiles do
		print(string.format("── Profile: %s ──", Profile.name))

		for _, Count in ListenerCounts do
			local ResultGroup: ResultGroup = {}
			local BaselineResult: SampleResult? = nil

			for _, Entry in FIRE_METHODS do
				local sig = Signal.new()

				local Result = CollectSamples(
					sig,
					Entry.name,
					Entry.method,
					Count,
					Profile,
					Config
				)

				sig:Destroy()
				task.wait(0.05)

				ResultGroup[Entry.name] = Result
				PrintResult(Result)

				if Entry.name == BaselineMethod then
					BaselineResult = Result
				elseif BaselineResult then
					PrintComparison(BaselineResult, Result)
				end
			end

			table.insert(AllGroups, {
				profile = Profile.name,
				count   = Count,
				results = ResultGroup,
			})

			print("")
			task.wait(0.1)
		end
	end

	PrintSummary(AllGroups, BaselineMethod)
end

-- ─── Factory ───────────────────────────────────────────────────────────────────

local Factory = {}
Factory.__type = Identity

--- Creates a new Benchmark instance.
---
--- @param UserConfig    BenchmarkConfig?      Overrides for the default config.
--- @param UserProfiles  { ListenerProfile }?  Replace all profiles if supplied.
---
--- @return Benchmark
function Factory.new(UserConfig: BenchmarkConfig?, UserProfiles: { ListenerProfile }?): any
	local Signal = require(SignalModule)

	local ResolvedConfig: BenchmarkConfig = {}

	for Key, DefaultValue in DEFAULT_CONFIG :: any do
		local Override = (UserConfig :: any) and (UserConfig :: any)[Key]
		;(ResolvedConfig :: any)[Key] = if Override ~= nil then Override else DefaultValue
	end

	local ResolvedProfiles = UserProfiles or DEFAULT_PROFILES

	local Instance = setmetatable({
		_Config   = ResolvedConfig,
		_Profiles = ResolvedProfiles,
		_Signal   = Signal,
		_Ran      = false,
	}, BenchmarkMetatable)

	return Instance
end

-- ─── Module Return ─────────────────────────────────────────────────────────────

local ModuleMetatable = table.freeze({
	__index = function(_, Key: string)
		warn(string.format("[%s] Attempted to access nil key '%s'", Identity, tostring(Key)))
	end,
	__newindex = function(_, Key: string, Value: any)
		error(string.format(
			"[%s] Attempted to write to protected key '%s' = '%s'",
			Identity, tostring(Key), tostring(Value)
			), 2)
	end,
})

return setmetatable(Factory, ModuleMetatable)