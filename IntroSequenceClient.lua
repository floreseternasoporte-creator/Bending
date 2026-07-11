--[[
	IntroSequenceClient.lua
	StarterPlayerScripts

	PURPOSE (Phase 1 — Intro / Loading only):
	Builds and plays the full cinematic intro sequence:

		1. Music starts immediately on join
		2. Black welcome screen with fade-in animation
		3. Epic loading screen with custom-drawn element icons (properly spaced)
		4. Element title cards
		5. WATERBENDING SHOWCASE — player's own avatar appears center-screen
		   inside a viewport, performs a Katara-style waterbending pose with
		   real water particles orbiting and streaming between the hands
		   (Avatar: The Last Airbender intro homage)
		6. Creator credit screen
		7. Logo reveal
		8. Cleanup -> player gains control

	v3 CHANGELOG:
	- Fixed everything overlapping: loading screen ring/title/subtitle/
	  progress bar/skip button now each have their own vertical band with
	  real breathing room between them.
	- Replaced the old generic circle "orbs" with hand-built vector icons
	  for each element (a water droplet, a lightning bolt, a flame, a
	  mountain/earth glyph) drawn from primitives — no emoji/unicode glyphs
	  anywhere in this file.
	- Added the new player-avatar Waterbending phase (see PHASE 4 below).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")
local RunService = game:GetService("RunService")

local localPlayer = Players.LocalPlayer
local playerGui = localPlayer:WaitForChild("PlayerGui")

-- ============================================================
-- CONFIG
-- ============================================================

local MUSIC_ID = "rbxassetid://88724470380452"
local MUSIC_VOLUME = 0.5

local COLORS = {
	Background = Color3.fromRGB(5, 5, 10),
	BackgroundDark = Color3.fromRGB(0, 0, 0),
	TextPrimary = Color3.fromRGB(240, 240, 245),
	TextDim = Color3.fromRGB(120, 120, 140),
	Accent = Color3.fromRGB(100, 200, 255),
	Water = Color3.fromRGB(70, 160, 255),
	WaterDeep = Color3.fromRGB(30, 90, 180),
	Lightning = Color3.fromRGB(180, 120, 255),
	Fire = Color3.fromRGB(255, 100, 50),
	Earth = Color3.fromRGB(200, 160, 100),
	RingGlow = Color3.fromRGB(100, 220, 200),
}

local FONT_TITLE = Enum.Font.FredokaOne
local FONT_BODY = Enum.Font.GothamMedium
local FONT_SUBTITLE = Enum.Font.Gotham

-- ============================================================
-- ROOT GUI
-- ============================================================

local existing = playerGui:FindFirstChild("IntroSequenceGui")
if existing then
	existing:Destroy()
end

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "IntroSequenceGui"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true
screenGui.DisplayOrder = 100
screenGui.Parent = playerGui

local backdrop = Instance.new("Frame")
backdrop.Name = "Backdrop"
backdrop.Size = UDim2.fromScale(1, 1)
backdrop.Position = UDim2.fromScale(0, 0)
backdrop.BackgroundColor3 = COLORS.BackgroundDark
backdrop.BorderSizePixel = 0
backdrop.ZIndex = 1
backdrop.Parent = screenGui

-- ============================================================
-- MUSIC
-- ============================================================

local musicSound = Instance.new("Sound")
musicSound.Name = "IntroMusic"
musicSound.SoundId = MUSIC_ID
musicSound.Volume = MUSIC_VOLUME
musicSound.Looped = true
musicSound.Parent = SoundService
musicSound:Play()

-- ============================================================
-- SERVER-READY LISTENER
-- ============================================================

local serverReady = false

local introReadyEvent = ReplicatedStorage:WaitForChild("IntroReady", 10)

if introReadyEvent then
	local serverReadyConnection
	serverReadyConnection = introReadyEvent.OnClientEvent:Connect(function()
		serverReady = true
		if serverReadyConnection then
			serverReadyConnection:Disconnect()
		end
	end)
else
	serverReady = true
end

-- ============================================================
-- HELPERS
-- ============================================================

local function tween(instance: Instance, duration: number, props: { [string]: any }, style: Enum.EasingStyle?, direction: Enum.EasingDirection?)
	local info = TweenInfo.new(duration, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local t = TweenService:Create(instance, info, props)
	t:Play()
	return t
end

local function fadeIn(instance, duration, targetTransparency)
	targetTransparency = targetTransparency or 0
	if instance:IsA("TextLabel") or instance:IsA("TextButton") then
		instance.TextTransparency = 1
		tween(instance, duration, { TextTransparency = targetTransparency })
	elseif instance:IsA("ImageLabel") or instance:IsA("ImageButton") then
		instance.ImageTransparency = 1
		tween(instance, duration, { ImageTransparency = targetTransparency })
	elseif instance:IsA("Frame") then
		instance.BackgroundTransparency = 1
		tween(instance, duration, { BackgroundTransparency = targetTransparency })
	end
end

local function makeLabel(props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Font = props.Font or FONT_BODY
	label.TextColor3 = props.TextColor3 or COLORS.TextPrimary
	label.TextScaled = props.TextScaled ~= false
	label.Text = props.Text or ""
	label.Size = props.Size or UDim2.fromScale(0.5, 0.1)
	label.Position = props.Position or UDim2.fromScale(0.25, 0.45)
	label.ZIndex = props.ZIndex or 5
	label.TextTransparency = props.TextTransparency or 0
	label.Parent = props.Parent
	if props.Constrain then
		local constraint = Instance.new("UITextSizeConstraint")
		constraint.MaxTextSize = props.MaxTextSize or 72
		constraint.Parent = label
	end
	return label
end

local function makeFrame(parent, size, position, anchor, color, transparency, zindex)
	local f = Instance.new("Frame")
	f.Size = size
	f.Position = position
	f.AnchorPoint = anchor or Vector2.new(0, 0)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.BorderSizePixel = 0
	f.ZIndex = zindex or 5
	f.Parent = parent
	return f
end

-- ============================================================
-- HAND-BUILT ELEMENT ICONS
-- Each icon is drawn from primitive Frames (rotated rectangles/circles)
-- rather than emoji/unicode glyphs, so they read clearly at any size and
-- match the game's own color language instead of relying on font glyphs.
-- ============================================================

-- WATER: a teardrop made from a rotated square (top) + circle (bottom)
local function drawWaterIcon(parent, color, size)
	local holder = Instance.new("Frame")
	holder.Size = size
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 7
	holder.Parent = parent

	local point = Instance.new("Frame")
	point.Size = UDim2.fromScale(0.55, 0.55)
	point.AnchorPoint = Vector2.new(0.5, 0.5)
	point.Position = UDim2.fromScale(0.5, 0.28)
	point.Rotation = 45
	point.BackgroundColor3 = color
	point.BorderSizePixel = 0
	point.ZIndex = 7
	point.Parent = holder
	local pointCorner = Instance.new("UICorner")
	pointCorner.CornerRadius = UDim.new(0.15, 0)
	pointCorner.Parent = point

	local bulb = Instance.new("Frame")
	bulb.Size = UDim2.fromScale(0.85, 0.85)
	bulb.AnchorPoint = Vector2.new(0.5, 0.5)
	bulb.Position = UDim2.fromScale(0.5, 0.58)
	bulb.BackgroundColor3 = color
	bulb.BorderSizePixel = 0
	bulb.ZIndex = 7
	bulb.Parent = holder
	local bulbCorner = Instance.new("UICorner")
	bulbCorner.CornerRadius = UDim.new(1, 0)
	bulbCorner.Parent = bulb

	return holder
end

-- LIGHTNING: a zig-zag bolt built from three angled bars
local function drawLightningIcon(parent, color, size)
	local holder = Instance.new("Frame")
	holder.Size = size
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 7
	holder.Parent = parent

	local barTop = Instance.new("Frame")
	barTop.Size = UDim2.fromScale(0.22, 0.62)
	barTop.AnchorPoint = Vector2.new(0.5, 0.5)
	barTop.Position = UDim2.fromScale(0.58, 0.28)
	barTop.Rotation = 22
	barTop.BackgroundColor3 = color
	barTop.BorderSizePixel = 0
	barTop.ZIndex = 7
	barTop.Parent = holder
	local c1 = Instance.new("UICorner")
	c1.CornerRadius = UDim.new(0.3, 0)
	c1.Parent = barTop

	local barMid = Instance.new("Frame")
	barMid.Size = UDim2.fromScale(0.6, 0.24)
	barMid.AnchorPoint = Vector2.new(0.5, 0.5)
	barMid.Position = UDim2.fromScale(0.48, 0.52)
	barMid.Rotation = -18
	barMid.BackgroundColor3 = color
	barMid.BorderSizePixel = 0
	barMid.ZIndex = 7
	barMid.Parent = holder
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0.3, 0)
	c2.Parent = barMid

	local barBottom = Instance.new("Frame")
	barBottom.Size = UDim2.fromScale(0.22, 0.62)
	barBottom.AnchorPoint = Vector2.new(0.5, 0.5)
	barBottom.Position = UDim2.fromScale(0.4, 0.74)
	barBottom.Rotation = 22
	barBottom.BackgroundColor3 = color
	barBottom.BorderSizePixel = 0
	barBottom.ZIndex = 7
	barBottom.Parent = holder
	local c3 = Instance.new("UICorner")
	c3.CornerRadius = UDim.new(0.3, 0)
	c3.Parent = barBottom

	return holder
end

-- FIRE: a flame silhouette built from two stacked, offset teardrops
local function drawFireIcon(parent, color, size)
	local holder = Instance.new("Frame")
	holder.Size = size
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 7
	holder.Parent = parent

	local outer = Instance.new("Frame")
	outer.Size = UDim2.fromScale(0.75, 0.9)
	outer.AnchorPoint = Vector2.new(0.5, 1)
	outer.Position = UDim2.fromScale(0.5, 0.95)
	outer.BackgroundColor3 = color
	outer.BorderSizePixel = 0
	outer.ZIndex = 7
	outer.Parent = holder
	local outerCorner = Instance.new("UICorner")
	outerCorner.CornerRadius = UDim.new(0.5, 0)
	outerCorner.Parent = outer

	local tip = Instance.new("Frame")
	tip.Size = UDim2.fromScale(0.4, 0.5)
	tip.AnchorPoint = Vector2.new(0.5, 1)
	tip.Position = UDim2.fromScale(0.5, 0.55)
	tip.BackgroundColor3 = color
	tip.BorderSizePixel = 0
	tip.ZIndex = 7
	tip.Parent = holder
	local tipCorner = Instance.new("UICorner")
	tipCorner.CornerRadius = UDim.new(0.5, 0)
	tipCorner.Parent = tip

	local core = Instance.new("Frame")
	core.Size = UDim2.fromScale(0.32, 0.4)
	core.AnchorPoint = Vector2.new(0.5, 1)
	core.Position = UDim2.fromScale(0.5, 0.85)
	core.BackgroundColor3 = COLORS.BackgroundDark
	core.BackgroundTransparency = 0.35
	core.BorderSizePixel = 0
	core.ZIndex = 8
	core.Parent = holder
	local coreCorner = Instance.new("UICorner")
	coreCorner.CornerRadius = UDim.new(0.5, 0)
	coreCorner.Parent = core

	return holder
end

-- EARTH: a stacked mountain silhouette from two triangular wedges
local function drawEarthIcon(parent, color, size)
	local holder = Instance.new("Frame")
	holder.Size = size
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 7
	holder.Parent = parent

	local peakBack = Instance.new("Frame")
	peakBack.Size = UDim2.fromScale(0.5, 0.5)
	peakBack.AnchorPoint = Vector2.new(0.5, 1)
	peakBack.Position = UDim2.fromScale(0.68, 0.82)
	peakBack.Rotation = 45
	peakBack.BackgroundColor3 = color
	peakBack.BackgroundTransparency = 0.25
	peakBack.BorderSizePixel = 0
	peakBack.ZIndex = 6
	peakBack.Parent = holder
	local c1 = Instance.new("UICorner")
	c1.CornerRadius = UDim.new(0.1, 0)
	c1.Parent = peakBack

	local peakFront = Instance.new("Frame")
	peakFront.Size = UDim2.fromScale(0.62, 0.62)
	peakFront.AnchorPoint = Vector2.new(0.5, 1)
	peakFront.Position = UDim2.fromScale(0.42, 0.88)
	peakFront.Rotation = 45
	peakFront.BackgroundColor3 = color
	peakFront.BorderSizePixel = 0
	peakFront.ZIndex = 7
	peakFront.Parent = holder
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(0.1, 0)
	c2.Parent = peakFront

	local ground = Instance.new("Frame")
	ground.Size = UDim2.fromScale(1, 0.14)
	ground.AnchorPoint = Vector2.new(0.5, 1)
	ground.Position = UDim2.fromScale(0.5, 0.92)
	ground.BackgroundColor3 = color
	ground.BorderSizePixel = 0
	ground.ZIndex = 7
	ground.Parent = holder
	local c3 = Instance.new("UICorner")
	c3.CornerRadius = UDim.new(0.3, 0)
	c3.Parent = ground

	return holder
end

-- ============================================================
-- PHASE 1: WELCOME SCREEN
-- ============================================================

local function runWelcomeScreen()
	local container = Instance.new("Frame")
	container.Name = "WelcomeScreen"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.ZIndex = 5
	container.Parent = backdrop

	local welcomeLabel = makeLabel({
		Parent = container,
		Text = "WELCOME",
		Font = FONT_TITLE,
		TextColor3 = COLORS.TextPrimary,
		Size = UDim2.fromScale(0.8, 0.2),
		Position = UDim2.fromScale(0.1, 0.38),
		Constrain = true,
		MaxTextSize = 120,
		TextTransparency = 1,
	})

	local topLine = makeFrame(container, UDim2.new(0, 0, 0, 2), UDim2.fromScale(0.5, 0.34), Vector2.new(0.5, 0), COLORS.Accent, 0, 4)
	local bottomLine = makeFrame(container, UDim2.new(0, 0, 0, 2), UDim2.fromScale(0.5, 0.6), Vector2.new(0.5, 0), COLORS.Accent, 0, 4)

	local continueButton = Instance.new("TextButton")
	continueButton.Name = "ContinueButton"
	continueButton.Size = UDim2.fromScale(0.18, 0.07)
	continueButton.Position = UDim2.fromScale(0.5, 0.78)
	continueButton.AnchorPoint = Vector2.new(0.5, 0)
	continueButton.BackgroundColor3 = COLORS.BackgroundDark
	continueButton.BackgroundTransparency = 0.3
	continueButton.BorderSizePixel = 0
	continueButton.Font = FONT_BODY
	continueButton.Text = "CONTINUE"
	continueButton.TextColor3 = COLORS.TextPrimary
	continueButton.TextScaled = true
	continueButton.ZIndex = 6
	continueButton.Parent = container
	continueButton.TextTransparency = 1
	continueButton.BackgroundTransparency = 1

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = continueButton

	local stroke = Instance.new("UIStroke")
	stroke.Color = COLORS.Accent
	stroke.Thickness = 2
	stroke.Transparency = 1
	stroke.Parent = continueButton

	-- Animations
	tween(welcomeLabel, 1.5, { TextTransparency = 0 })
	tween(topLine, 1, { Size = UDim2.new(0, 300, 0, 2) })
	tween(bottomLine, 1, { Size = UDim2.new(0, 300, 0, 2) })
	task.wait(0.6)
	tween(continueButton, 1, { TextTransparency = 0, BackgroundTransparency = 0.3 })
	tween(stroke, 1, { Transparency = 0 })

	continueButton.MouseEnter:Connect(function()
		tween(continueButton, 0.2, { BackgroundTransparency = 0 })
		tween(stroke, 0.2, { Transparency = 0.2 })
	end)
	continueButton.MouseLeave:Connect(function()
		tween(continueButton, 0.2, { BackgroundTransparency = 0.3 })
		tween(stroke, 0.2, { Transparency = 0 })
	end)

	local clicked = false
	continueButton.MouseButton1Click:Connect(function()
		clicked = true
	end)

	repeat
		task.wait()
	until clicked

	tween(welcomeLabel, 0.8, { TextTransparency = 1 })
	tween(continueButton, 0.8, { TextTransparency = 1, BackgroundTransparency = 1 })
	tween(stroke, 0.8, { Transparency = 1 })
	tween(topLine, 0.8, { Size = UDim2.new(0, 0, 0, 2) })
	tween(bottomLine, 0.8, { Size = UDim2.new(0, 0, 0, 2) })
	task.wait(0.85)
	container:Destroy()
end

-- ============================================================
-- PHASE 2: LOADING SCREEN
-- Layout is now split into clearly separated vertical bands so nothing
-- overlaps:
--   0.06 - 0.16   Title
--   0.16 - 0.22   Subtitle
--   0.24 - 0.62   Ring + 4 element icons (self-contained square block)
--   0.66 - 0.72   Progress label
--   0.80 - 0.87   Skip button
-- ============================================================

local function createElementSlot(parent, elementName, color, position, drawFn)
	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromOffset(64, 64)
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = position
	holder.BackgroundColor3 = Color3.fromRGB(10, 10, 14)
	holder.BackgroundTransparency = 0.15
	holder.ZIndex = 6
	holder.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = holder

	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = color
	ringStroke.Thickness = 2.5
	ringStroke.Transparency = 0.2
	ringStroke.Parent = holder

	-- The icon sits slightly inset so it never touches the ring edge
	local iconArea = Instance.new("Frame")
	iconArea.Size = UDim2.fromScale(0.56, 0.56)
	iconArea.AnchorPoint = Vector2.new(0.5, 0.5)
	iconArea.Position = UDim2.fromScale(0.5, 0.5)
	iconArea.BackgroundTransparency = 1
	iconArea.ZIndex = 7
	iconArea.Parent = holder

	drawFn(iconArea, color, UDim2.fromScale(1, 1))

	-- Name label sits BELOW the whole slot with its own dedicated space,
	-- anchored from the slot's bottom edge, so it can never overlap the
	-- icon above it or a neighboring label beside it.
	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(0, 130, 0, 20)
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	nameLabel.Position = UDim2.new(0.5, 0, 1, 10)
	nameLabel.Font = FONT_BODY
	nameLabel.Text = elementName
	nameLabel.TextColor3 = color
	nameLabel.TextScaled = true
	nameLabel.TextTransparency = 1
	nameLabel.ZIndex = 6
	nameLabel.Parent = holder

	local constraint = Instance.new("UITextSizeConstraint")
	constraint.MaxTextSize = 16
	constraint.Parent = nameLabel

	return { holder = holder, nameLabel = nameLabel, ringStroke = ringStroke }
end

local function runLoadingScreen(skipBindable: BindableEvent)
	local container = Instance.new("Frame")
	container.Name = "LoadingScreen"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.ZIndex = 5
	container.Parent = backdrop

	-- Title band
	local titleMain = makeLabel({
		Parent = container,
		Text = "THE ELEMENTS",
		Font = FONT_TITLE,
		TextColor3 = COLORS.TextPrimary,
		Size = UDim2.fromScale(0.8, 0.09),
		Position = UDim2.fromScale(0.1, 0.07),
		Constrain = true,
		MaxTextSize = 100,
		TextTransparency = 1,
	})

	local titleSub = makeLabel({
		Parent = container,
		Text = "AWAKENING",
		Font = FONT_SUBTITLE,
		TextColor3 = COLORS.Accent,
		Size = UDim2.fromScale(0.6, 0.04),
		Position = UDim2.fromScale(0.2, 0.175),
		Constrain = true,
		MaxTextSize = 32,
		TextTransparency = 1,
	})

	-- Ring block: a self-contained square region, vertically centered in
	-- its own band (0.24 to 0.66), well clear of the title above and the
	-- progress label below.
	local ringHolder = Instance.new("Frame")
	ringHolder.Name = "RingHolder"
	ringHolder.Size = UDim2.fromOffset(300, 300)
	ringHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	ringHolder.Position = UDim2.fromScale(0.5, 0.44)
	ringHolder.BackgroundTransparency = 1
	ringHolder.ZIndex = 5
	ringHolder.Parent = container

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.Size = UDim2.fromOffset(150, 150)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.ZIndex = 5
	ring.Parent = ringHolder

	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring

	local ringGradient = Instance.new("UIGradient")
	ringGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.Water),
		ColorSequenceKeypoint.new(0.33, COLORS.Lightning),
		ColorSequenceKeypoint.new(0.66, COLORS.Fire),
		ColorSequenceKeypoint.new(1, COLORS.Water),
	})
	ringGradient.Rotation = 0
	ringGradient.Parent = ring

	local ringStroke = Instance.new("UIStroke")
	ringStroke.Thickness = 5
	ringStroke.Color = COLORS.TextPrimary
	ringStroke.Transparency = 0.2
	ringStroke.Parent = ring

	local strokeGradient = ringGradient:Clone()
	strokeGradient.Parent = ringStroke
	ring.BackgroundTransparency = 1

	-- Four element slots placed at the CORNERS of the ring holder square,
	-- well outside the ring itself (radius ~150px) so icons never overlap
	-- the ring or each other. Each slot is 64px with 10px label gap below.
	local waterSlot = createElementSlot(ringHolder, "WATER", COLORS.Water, UDim2.fromScale(0.5, 0.02), drawWaterIcon)
	local lightningSlot = createElementSlot(ringHolder, "LIGHTNING", COLORS.Lightning, UDim2.fromScale(0.98, 0.5), drawLightningIcon)
	local fireSlot = createElementSlot(ringHolder, "FIRE", COLORS.Fire, UDim2.fromScale(0.5, 0.98), drawFireIcon)
	local earthSlot = createElementSlot(ringHolder, "EARTH", COLORS.Earth, UDim2.fromScale(0.02, 0.5), drawEarthIcon)

	-- Correct anchor points so slots sit fully outside their edge rather
	-- than being clipped by the holder bounds.
	waterSlot.holder.AnchorPoint = Vector2.new(0.5, 1)
	lightningSlot.holder.AnchorPoint = Vector2.new(0, 0.5)
	fireSlot.holder.AnchorPoint = Vector2.new(0.5, 0)
	earthSlot.holder.AnchorPoint = Vector2.new(1, 0.5)

	-- Spinning animation
	local spinTween = TweenService:Create(
		ringGradient,
		TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1, false),
		{ Rotation = 360 }
	)
	spinTween:Play()
	local spinTweenStroke = TweenService:Create(
		strokeGradient,
		TweenInfo.new(8, Enum.EasingStyle.Linear, Enum.EasingDirection.In, -1, false),
		{ Rotation = 360 }
	)
	spinTweenStroke:Play()

	-- Gentle pulse for each element slot (scale breathing, not overlapping neighbors)
	local slots = { waterSlot, lightningSlot, fireSlot, earthSlot }
	local pulsing = true
	local pulseConn
	pulseConn = RunService.Heartbeat:Connect(function()
		if not pulsing then
			pulseConn:Disconnect()
			return
		end
		local s = 1 + math.sin(tick() * 2.2) * 0.045
		for _, slot in ipairs(slots) do
			slot.ringStroke.Thickness = 2.5 * s
		end
	end)

	for _, slot in ipairs(slots) do
		tween(slot.nameLabel, 1, { TextTransparency = 0 })
	end

	-- Progress band (0.68 - 0.74), clear of the ring above
	local progressLabel = makeLabel({
		Parent = container,
		Text = "INITIALIZING... 0%",
		Font = FONT_BODY,
		TextColor3 = COLORS.TextPrimary,
		Size = UDim2.fromScale(0.7, 0.045),
		Position = UDim2.fromScale(0.15, 0.735),
		Constrain = true,
		MaxTextSize = 26,
		TextTransparency = 1,
	})

	-- Skip button band (0.85 - 0.91), fully clear of progress label
	local skipButton = Instance.new("TextButton")
	skipButton.Name = "SkipButton"
	skipButton.Size = UDim2.fromScale(0.14, 0.05)
	skipButton.Position = UDim2.fromScale(0.5, 0.87)
	skipButton.AnchorPoint = Vector2.new(0.5, 0)
	skipButton.BackgroundColor3 = COLORS.BackgroundDark
	skipButton.BackgroundTransparency = 0.4
	skipButton.BorderSizePixel = 0
	skipButton.Font = FONT_BODY
	skipButton.Text = "SKIP"
	skipButton.TextColor3 = COLORS.TextDim
	skipButton.TextScaled = true
	skipButton.ZIndex = 6
	skipButton.Parent = container
	skipButton.TextTransparency = 1
	skipButton.BackgroundTransparency = 0.4

	local skipCorner = Instance.new("UICorner")
	skipCorner.CornerRadius = UDim.new(0, 4)
	skipCorner.Parent = skipButton

	local skipStroke = Instance.new("UIStroke")
	skipStroke.Color = COLORS.TextDim
	skipStroke.Thickness = 1.5
	skipStroke.Transparency = 1
	skipStroke.Parent = skipButton

	-- Fade in elements (staggered so it reads clearly)
	fadeIn(titleMain, 1)
	task.wait(0.15)
	fadeIn(titleSub, 0.8)
	task.wait(0.35)
	fadeIn(progressLabel, 0.8)
	task.wait(0.4)
	fadeIn(skipButton, 0.8)
	tween(skipStroke, 0.8, { Transparency = 0.5 })

	skipButton.MouseEnter:Connect(function()
		tween(skipButton, 0.2, { BackgroundTransparency = 0.2, TextTransparency = 0 })
	end)
	skipButton.MouseLeave:Connect(function()
		tween(skipButton, 0.2, { BackgroundTransparency = 0.4, TextTransparency = 1 })
	end)

	skipButton.MouseButton1Click:Connect(function()
		skipBindable:Fire()
	end)

	-- Progress driver
	local skipped = false
	local minDuration = 3.5
	local elapsed = 0
	local step = 0.1

	local skipConn = skipBindable.Event:Connect(function()
		skipped = true
	end)

	while elapsed < minDuration or not serverReady do
		if skipped then
			break
		end
		task.wait(step)
		elapsed += step

		local pct = math.clamp(math.floor((elapsed / minDuration) * 100), 0, 99)
		if serverReady then
			pct = 100
		end
		progressLabel.Text = string.format("INITIALIZING... %d%%", pct)

		if elapsed > 10 then
			break
		end
	end

	progressLabel.Text = "INITIALIZING... 100%"
	skipConn:Disconnect()
	pulsing = false
	spinTween:Cancel()
	spinTweenStroke:Cancel()

	task.wait(0.5)

	-- Fade out
	tween(titleMain, 0.8, { TextTransparency = 1 })
	tween(titleSub, 0.8, { TextTransparency = 1 })
	tween(progressLabel, 0.8, { TextTransparency = 1 })
	tween(skipButton, 0.8, { TextTransparency = 1, BackgroundTransparency = 1 })
	tween(skipStroke, 0.8, { Transparency = 1 })
	tween(ringStroke, 0.8, { Transparency = 1 })
	for _, slot in ipairs(slots) do
		tween(slot.nameLabel, 0.8, { TextTransparency = 1 })
		tween(slot.ringStroke, 0.8, { Transparency = 1 })
		tween(slot.holder, 0.8, { BackgroundTransparency = 1 })
	end

	task.wait(0.85)
	container:Destroy()
end

-- ============================================================
-- PHASE 3: ELEMENT TITLE CARDS
-- ============================================================

local function runElementCard(name: string, color: Color3)
	local container = Instance.new("Frame")
	container.Name = name .. "Card"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.ZIndex = 5
	container.Parent = backdrop

	local glowBg = Instance.new("Frame")
	glowBg.Size = UDim2.fromScale(1, 1)
	glowBg.BackgroundColor3 = color
	glowBg.BackgroundTransparency = 1
	glowBg.ZIndex = 1
	glowBg.Parent = container

	local topBar = makeFrame(container, UDim2.new(0, 0, 0, 6), UDim2.fromScale(0, 0.4), Vector2.new(0, 0), color, 0, 4)
	local bottomBar = makeFrame(container, UDim2.new(0, 0, 0, 6), UDim2.fromScale(1, 0.58), Vector2.new(1, 0), color, 0, 4)

	local nameLabel = makeLabel({
		Parent = container,
		Text = string.upper(name),
		Font = FONT_TITLE,
		TextColor3 = color,
		Size = UDim2.fromScale(0.9, 0.16),
		Position = UDim2.fromScale(0.05, 0.44),
		Constrain = true,
		MaxTextSize = 130,
		TextTransparency = 1,
	})

	task.wait(0.2)
	tween(topBar, 0.6, { Size = UDim2.new(0, 500, 0, 6) })
	task.wait(0.15)
	tween(bottomBar, 0.6, { Size = UDim2.new(0, 500, 0, 6) })
	task.wait(0.1)
	tween(nameLabel, 0.8, { TextTransparency = 0 })
	tween(glowBg, 0.8, { BackgroundTransparency = 0.92 })

	task.wait(1.2)

	tween(nameLabel, 0.6, { TextTransparency = 1 })
	tween(topBar, 0.6, { Size = UDim2.new(0, 0, 0, 6) })
	tween(bottomBar, 0.6, { Size = UDim2.new(0, 0, 0, 6) })
	tween(glowBg, 0.6, { BackgroundTransparency = 1 })

	task.wait(0.65)
	container:Destroy()
end

local function runElementsIntro()
	runElementCard("WATER", COLORS.Water)
	task.wait(1.2)
	runElementCard("LIGHTNING", COLORS.Lightning)
	task.wait(1.2)
	runElementCard("FIRE", COLORS.Fire)
	task.wait(1.2)
	runElementCard("EARTH", COLORS.Earth)
end

-- ============================================================
-- PHASE 4: WATERBENDING SHOWCASE (NEW)
--
-- Loads the player's OWN avatar into a ViewportFrame centered on screen,
-- exactly like the character silhouette in the Avatar: The Last Airbender
-- intro. The avatar plays a hand-authored waterbending pose sequence:
--   1. Idle, arms relaxed
--   2. Arms rise and cross in front of chest (gathering stance)
--   3. Arms sweep outward and up in a wide circular arc (drawing the water)
--   4. Arms come together in front, cupped (compressing the water sphere)
--   5. One arm extends forward, water "release" pose, weight shifts into
--      a low stance (mirrors the final push/stance frame in the reference)
-- Real water particles (ParticleEmitter) stream from the hands and orbit
-- between them throughout, matching the swirling water shown in the
-- reference clip.
-- ============================================================

-- Collects the Motor6D joints we need to animate a humanoid rig (R15 or R6 safe)
local function getBendingJoints(character)
	local joints = {}

	local rightUpperArm = character:FindFirstChild("RightUpperArm") or character:FindFirstChild("Right Arm")
	local leftUpperArm = character:FindFirstChild("LeftUpperArm") or character:FindFirstChild("Left Arm")
	local upperTorso = character:FindFirstChild("UpperTorso") or character:FindFirstChild("Torso")

	if not (rightUpperArm and leftUpperArm and upperTorso) then
		return nil
	end

	local function motorFor(part)
		for _, child in ipairs(part:GetChildren()) do
			if child:IsA("Motor6D") then
				return child
			end
		end
		return nil
	end

	joints.RightShoulder = motorFor(rightUpperArm)
	joints.LeftShoulder = motorFor(leftUpperArm)

	return joints
end

-- Returns the world CFrame offset for a hand attachment point (approx
-- position at the end of the lower arm / hand), used to anchor particle
-- emitters that "stream" from the hands.
local function getHandAttachPart(character, side: string)
	local handPart = character:FindFirstChild(side .. "Hand")
	if handPart then
		return handPart
	end
	local lowerArm = character:FindFirstChild(side .. "LowerArm")
	if lowerArm then
		return lowerArm
	end
	-- R6 fallback
	return character:FindFirstChild(side == "Right" and "Right Arm" or "Left Arm")
end

local function createWaterEmitter(parent)
	local attachment = Instance.new("Attachment")
	attachment.Name = "WaterAttach"
	attachment.Parent = parent

	local emitter = Instance.new("ParticleEmitter")
	emitter.Name = "WaterParticles"
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(COLORS.Water, COLORS.WaterDeep)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.5, 0.35),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	emitter.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.8, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	emitter.Lifetime = NumberRange.new(0.5, 0.9)
	emitter.Rate = 45
	emitter.Speed = NumberRange.new(2, 4)
	emitter.SpreadAngle = Vector2.new(25, 25)
	emitter.Rotation = NumberRange.new(0, 360)
	emitter.RotSpeed = NumberRange.new(-90, 90)
	emitter.LightEmission = 0.4
	emitter.LightInfluence = 0
	emitter.Acceleration = Vector3.new(0, -2, 0)
	emitter.Parent = attachment

	return attachment, emitter
end

-- A slowly orbiting water ring between the two hands, built from many
-- small particle bursts along a circular path using a swirl emitter.
local function createOrbitingWaterRing(parent)
	local ringPart = Instance.new("Part")
	ringPart.Name = "WaterRingCore"
	ringPart.Size = Vector3.new(0.2, 0.2, 0.2)
	ringPart.Transparency = 1
	ringPart.CanCollide = false
	ringPart.Anchored = true
	ringPart.Massless = true
	ringPart.Parent = parent

	local swirl = Instance.new("ParticleEmitter")
	swirl.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	swirl.Color = ColorSequence.new(COLORS.Water, COLORS.RingGlow)
	swirl.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.5, 0.4),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	swirl.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	swirl.Lifetime = NumberRange.new(0.6, 1)
	swirl.Rate = 60
	swirl.Speed = NumberRange.new(0.5, 1.5)
	swirl.SpreadAngle = Vector2.new(180, 180)
	swirl.LightEmission = 0.5
	swirl.Parent = ringPart

	return ringPart, swirl
end

local function runWaterbendingShowcase()
	local character = localPlayer.Character or localPlayer.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return -- safety: skip this phase if we truly can't find a character
	end

	local container = Instance.new("Frame")
	container.Name = "WaterbendingShowcase"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.ZIndex = 5
	container.Parent = backdrop

	-- Ambient tinted glow band behind the avatar, echoing the reference
	-- clip's warm background band behind the silhouette (kept subtle,
	-- not a literal copy).
	local glow = Instance.new("Frame")
	glow.Size = UDim2.fromScale(1, 0.42)
	glow.Position = UDim2.fromScale(0, 0.3)
	glow.BackgroundColor3 = COLORS.WaterDeep
	glow.BackgroundTransparency = 1
	glow.ZIndex = 2
	glow.Parent = container

	-- Element glyph label in the background (top area, own band, doesn't
	-- collide with the viewport or the caption below)
	local elementLabel = makeLabel({
		Parent = container,
		Text = "WATER",
		Font = FONT_TITLE,
		TextColor3 = COLORS.Water,
		Size = UDim2.fromScale(0.9, 0.1),
		Position = UDim2.fromScale(0.05, 0.08),
		Constrain = true,
		MaxTextSize = 70,
		TextTransparency = 1,
	})

	-- ViewportFrame: dedicated square band in the vertical middle of the
	-- screen (0.2 to 0.82), clear of the title above and caption below.
	local viewport = Instance.new("ViewportFrame")
	viewport.Name = "AvatarViewport"
	viewport.Size = UDim2.fromScale(0.7, 0.58)
	viewport.Position = UDim2.fromScale(0.15, 0.2)
	viewport.BackgroundTransparency = 1
	viewport.ZIndex = 3
	viewport.Parent = container

	local vpCamera = Instance.new("Camera")
	vpCamera.FieldOfView = 45
	viewport.CurrentCamera = vpCamera
	vpCamera.Parent = viewport

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport

	-- Clone the player's actual character for display; the live character
	-- stays untouched so the player isn't frozen/edited during the intro.
	local displayModel = character:Clone()
	displayModel.Name = "AvatarDisplay"

	-- Strip scripts from the clone so nothing (movement, tools, etc.) runs
	for _, obj in ipairs(displayModel:GetDescendants()) do
		if obj:IsA("Script") or obj:IsA("LocalScript") then
			obj:Destroy()
		end
	end

	local displayHumanoid = displayModel:FindFirstChildOfClass("Humanoid")
	if displayHumanoid then
		displayHumanoid.PlatformStand = true
		displayHumanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	end

	local rootPart = displayModel:FindFirstChild("HumanoidRootPart")
	displayModel.Parent = worldModel

	if rootPart then
		rootPart.Anchored = true
		rootPart.CFrame = CFrame.new(0, 0, 0)
	end

	-- Rim light so the clone reads clearly against the dark backdrop
	local keyLight = Instance.new("PointLight")
	keyLight.Parent = rootPart or worldModel
	keyLight.Range = 20
	keyLight.Brightness = 2
	keyLight.Color = COLORS.Water

	-- Frame the camera on the model, roughly chest/head height, slight
	-- low angle to feel heroic (matches the reference's slightly
	-- low, centered hero framing).
	local function frameCamera()
		if not rootPart then
			return
		end
		local focusPoint = rootPart.Position + Vector3.new(0, 1.2, 0)
		local camPos = focusPoint + Vector3.new(0, 0.2, 6.5)
		vpCamera.CFrame = CFrame.lookAt(camPos, focusPoint)
	end
	frameCamera()

	-- Locate shoulder joints for the bending animation
	local joints = getBendingJoints(displayModel)

	-- Water particle emitters attached to both hands, plus an orbiting
	-- swirl anchored between them.
	local rightHandPart = getHandAttachPart(displayModel, "Right")
	local leftHandPart = getHandAttachPart(displayModel, "Left")

	local rightAttach, rightEmitter
	local leftAttach, leftEmitter
	if rightHandPart then
		rightAttach, rightEmitter = createWaterEmitter(rightHandPart)
		rightEmitter.Enabled = false
	end
	if leftHandPart then
		leftAttach, leftEmitter = createWaterEmitter(leftHandPart)
		leftEmitter.Enabled = false
	end

	local ringPart, ringSwirl
	if rootPart then
		ringPart, ringSwirl = createOrbitingWaterRing(worldModel)
		ringSwirl.Enabled = false
	end

	-- Caption band, safely below the viewport
	local caption = makeLabel({
		Parent = container,
		Text = "MASTER THE FLOW",
		Font = FONT_SUBTITLE,
		TextColor3 = COLORS.TextDim,
		Size = UDim2.fromScale(0.8, 0.05),
		Position = UDim2.fromScale(0.1, 0.86),
		Constrain = true,
		MaxTextSize = 26,
		TextTransparency = 1,
	})

	-- Fade everything in
	tween(glow, 1, { BackgroundTransparency = 0.85 })
	tween(elementLabel, 1, { TextTransparency = 0 })
	tween(caption, 1, { TextTransparency = 0.3 })
	task.wait(0.4)

	-- ---- POSE SEQUENCE (mirrors the reference clip's beats) ----
	-- Each pose is a target C0 offset added on top of the joint's
	-- original C0, applied to both shoulders (mirrored for the left).
	if joints and joints.RightShoulder and joints.LeftShoulder then
		local rightOriginal = joints.RightShoulder.C0
		local leftOriginal = joints.LeftShoulder.C0

		local function poseShoulders(rightCF, leftCF, duration)
			local infoR = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			TweenService:Create(joints.RightShoulder, infoR, { C0 = rightOriginal * rightCF }):Play()
			TweenService:Create(joints.LeftShoulder, infoR, { C0 = leftOriginal * leftCF }):Play()
		end

		-- BEAT 1 (~0.0s reference): idle, arms relaxed at sides — this is
		-- already the rig's default pose, so we simply hold briefly.
		task.wait(0.3)

		-- BEAT 2 (~0.6s reference): arms rise and cross in front of the
		-- chest, elbows bent — "gathering" stance before the water draws in.
		poseShoulders(
			CFrame.Angles(math.rad(-70), 0, math.rad(-20)),
			CFrame.Angles(math.rad(-70), 0, math.rad(20)),
			0.7
		)
		if rightEmitter then rightEmitter.Enabled = true end
		if leftEmitter then leftEmitter.Enabled = true end
		if ringSwirl then ringSwirl.Enabled = true end
		task.wait(0.8)

		-- BEAT 3 (~1.6s reference): arms sweep outward and up in a wide
		-- circular arc, drawing the water out and around — the big
		-- "wingspan" pose from the clip.
		poseShoulders(
			CFrame.Angles(math.rad(-160), 0, math.rad(-75)),
			CFrame.Angles(math.rad(-160), 0, math.rad(75)),
			0.9
		)

		-- Orbit the water ring around the torso while arms are spread,
		-- following the sweep.
		local orbitRunning = true
		if ringPart and rootPart then
			local orbitTime = 0
			local orbitConn
			orbitConn = RunService.Heartbeat:Connect(function(dt)
				if not orbitRunning or not ringPart.Parent then
					if orbitConn then orbitConn:Disconnect() end
					return
				end
				orbitTime += dt
				local angle = orbitTime * 3.4
				local offset = Vector3.new(math.cos(angle) * 1.6, 1.1 + math.sin(angle * 1.7) * 0.15, math.sin(angle) * 1.6)
				ringPart.CFrame = rootPart.CFrame * CFrame.new(offset)
			end)
		end

		task.wait(1.0)

		-- BEAT 4 (~2.4s reference): arms come back together in front of
		-- the chest, cupped — compressing the water into a sphere between
		-- the palms.
		poseShoulders(
			CFrame.Angles(math.rad(-90), math.rad(-25), math.rad(-45)),
			CFrame.Angles(math.rad(-90), math.rad(25), math.rad(45)),
			0.7
		)
		task.wait(0.8)

		-- BEAT 5 (final reference pose): weight shifts into a low forward
		-- stance, right arm extends forward/up in the release/push pose,
		-- left arm pulls back — matching the final wide stance frame.
		poseShoulders(
			CFrame.Angles(math.rad(-130), math.rad(-10), math.rad(10)),
			CFrame.Angles(math.rad(-40), math.rad(15), math.rad(60)),
			0.8
		)
		frameCamera()

		task.wait(1.6)

		orbitRunning = false
	else
		-- Fallback: no rig joints found (unusual rig type) — just hold
		-- the water effects on for a beat so the phase still reads.
		if rightEmitter then rightEmitter.Enabled = true end
		if leftEmitter then leftEmitter.Enabled = true end
		if ringSwirl then ringSwirl.Enabled = true end
		task.wait(3.2)
	end

	-- Fade out
	if rightEmitter then rightEmitter.Enabled = false end
	if leftEmitter then leftEmitter.Enabled = false end
	if ringSwirl then ringSwirl.Enabled = false end

	tween(caption, 0.6, { TextTransparency = 1 })
	tween(elementLabel, 0.6, { TextTransparency = 1 })
	tween(glow, 0.6, { BackgroundTransparency = 1 })

	task.wait(0.65)

	displayModel:Destroy()
	container:Destroy()
end

-- ============================================================
-- PHASE 5: CREATOR CREDIT
-- ============================================================

local function runCreatorCredit()
	local container = Instance.new("Frame")
	container.Name = "CreatorCredit"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.ZIndex = 5
	container.Parent = backdrop

	local smallLabel = makeLabel({
		Parent = container,
		Text = "CREATED BY",
		Font = FONT_BODY,
		TextColor3 = COLORS.TextDim,
		Size = UDim2.fromScale(0.6, 0.06),
		Position = UDim2.fromScale(0.2, 0.4),
		Constrain = true,
		MaxTextSize = 28,
		TextTransparency = 1,
	})

	local nameLabel = makeLabel({
		Parent = container,
		Text = "NarayanXX",
		Font = FONT_TITLE,
		TextColor3 = COLORS.Accent,
		Size = UDim2.fromScale(0.9, 0.15),
		Position = UDim2.fromScale(0.05, 0.48),
		Constrain = true,
		MaxTextSize = 100,
		TextTransparency = 1,
	})

	local leftAccent = makeFrame(container, UDim2.new(0, 0, 0, 3), UDim2.fromScale(0.5, 0.43), Vector2.new(1, 0), COLORS.Accent, 0, 4)
	local rightAccent = makeFrame(container, UDim2.new(0, 0, 0, 3), UDim2.fromScale(0.5, 0.43), Vector2.new(0, 0), COLORS.Accent, 0, 4)

	tween(smallLabel, 0.7, { TextTransparency = 0 })
	task.wait(0.3)
	tween(leftAccent, 0.6, { Size = UDim2.new(0, 150, 0, 3) })
	tween(rightAccent, 0.6, { Size = UDim2.new(0, 150, 0, 3) })
	task.wait(0.2)
	tween(nameLabel, 0.9, { TextTransparency = 0 })

	task.wait(2)

	tween(smallLabel, 0.6, { TextTransparency = 1 })
	tween(nameLabel, 0.6, { TextTransparency = 1 })
	tween(leftAccent, 0.6, { Size = UDim2.new(0, 0, 0, 3) })
	tween(rightAccent, 0.6, { Size = UDim2.new(0, 0, 0, 3) })

	task.wait(0.65)
	container:Destroy()
end

-- ============================================================
-- PHASE 6: LOGO SCREEN
-- ============================================================

local function runLogoScreen()
	local container = Instance.new("Frame")
	container.Name = "LogoScreen"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.ZIndex = 5
	container.Parent = backdrop

	local bgPulse = Instance.new("Frame")
	bgPulse.Size = UDim2.fromScale(1, 1)
	bgPulse.BackgroundColor3 = COLORS.Accent
	bgPulse.BackgroundTransparency = 1
	bgPulse.ZIndex = 1
	bgPulse.Parent = container

	local logoLabel = makeLabel({
		Parent = container,
		Text = "THE ELEMENTS",
		Font = FONT_TITLE,
		TextColor3 = COLORS.TextPrimary,
		Size = UDim2.fromScale(0.9, 0.18),
		Position = UDim2.fromScale(0.05, 0.4),
		Constrain = true,
		MaxTextSize = 120,
		TextTransparency = 1,
	})

	local underline1 = makeFrame(container, UDim2.new(0, 0, 0, 4), UDim2.fromScale(0.25, 0.62), Vector2.new(0.5, 0), COLORS.Water, 0, 5)
	local underline2 = makeFrame(container, UDim2.new(0, 0, 0, 4), UDim2.fromScale(0.5, 0.66), Vector2.new(0.5, 0), COLORS.Lightning, 0, 5)
	local underline3 = makeFrame(container, UDim2.new(0, 0, 0, 4), UDim2.fromScale(0.75, 0.62), Vector2.new(0.5, 0), COLORS.Fire, 0, 5)

	tween(logoLabel, 1.2, { TextTransparency = 0 })
	tween(bgPulse, 1.2, { BackgroundTransparency = 0.9 })
	task.wait(0.5)
	tween(underline1, 0.7, { Size = UDim2.new(0, 120, 0, 4) })
	task.wait(0.2)
	tween(underline2, 0.7, { Size = UDim2.new(0, 120, 0, 4) })
	task.wait(0.2)
	tween(underline3, 0.7, { Size = UDim2.new(0, 120, 0, 4) })

	task.wait(2.2)

	tween(logoLabel, 0.8, { TextTransparency = 1 })
	tween(underline1, 0.8, { Size = UDim2.new(0, 0, 0, 4) })
	tween(underline2, 0.8, { Size = UDim2.new(0, 0, 0, 4) })
	tween(underline3, 0.8, { Size = UDim2.new(0, 0, 0, 4) })
	tween(bgPulse, 0.8, { BackgroundTransparency = 1 })

	task.wait(0.85)
	container:Destroy()
end

-- ============================================================
-- MASTER SEQUENCE
-- ============================================================

local function runFullSequence()
	local skipBindable = Instance.new("BindableEvent")

	runWelcomeScreen()
	runLoadingScreen(skipBindable)
	runElementsIntro()
	runWaterbendingShowcase()
	runCreatorCredit()
	runLogoScreen()

	skipBindable:Destroy()

	tween(backdrop, 1, { BackgroundTransparency = 1 })
	task.wait(1.05)
	screenGui:Destroy()
	musicSound:Stop()
	musicSound:Destroy()
end

runFullSequence()
