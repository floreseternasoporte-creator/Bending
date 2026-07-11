--[[
	IntroSequenceServer.lua
	ServerScriptService

	PURPOSE (Phase 1 — Intro / Loading only):
	Minimal server-side orchestration for the cinematic intro sequence.
	
	This script:
	1. Guarantees the "IntroReady" RemoteEvent exists in ReplicatedStorage
	2. Fires that RemoteEvent once each player's character has fully loaded
	3. Ensures the client's loading bar has a real server-ready signal to wait on
	
	All UI and animations are client-side (IntroSequenceClient.lua).
	This keeps gameplay logic separate from presentation.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ============================================================
-- 1. CREATE REMOTEVENT IF IT DOESN'T EXIST
-- ============================================================

local introReadyEvent = ReplicatedStorage:FindFirstChild("IntroReady")
if not introReadyEvent then
	introReadyEvent = Instance.new("RemoteEvent")
	introReadyEvent.Name = "IntroReady"
	introReadyEvent.Parent = ReplicatedStorage
end

-- ============================================================
-- 2. CHARACTER READY DETECTION
-- ============================================================

local function onCharacterAdded(player: Player, character: Model)
	-- Wait for humanoid to confirm the character is fully functional
	local humanoid = character:WaitForChild("Humanoid", 10)
	
	if humanoid then
		-- Brief delay to ensure everything is truly ready
		task.wait(0.1)
		introReadyEvent:FireClient(player)
	end
end

local function onPlayerAdded(player: Player)
	-- Hook existing character if present (handles rapid joins in Studio)
	if player.Character then
		onCharacterAdded(player, player.Character)
	end
	
	-- Hook future character spawns (respawns, etc.)
	player.CharacterAdded:Connect(function(character)
		onCharacterAdded(player, character)
	end)
end

-- ============================================================
-- 3. SETUP LISTENERS
-- ============================================================

-- Connect for players joining after this script starts
Players.PlayerAdded:Connect(onPlayerAdded)

-- Handle any players already in-game (Studio testing / hot reloads)
for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
