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

	v4 CHANGELOG:
	- Root cause of the "everything is stacked on top of each other"
	  overlap bug: earlier versions mixed UDim2.fromOffset (fixed pixel)
	  sizes for the loading-screen ring/icons with UDim2.fromScale
	  (percentage) sizes for everything else. On any resolution that
	  wasn't the exact one this was eyeballed at, the fixed-pixel block
	  would balloon or shrink independently of the scale-based bands
	  around it and crash straight into the title/progress text.
	  Fixed by driving every critical size off `vmin()`, a helper that
	  scales against the SMALLER screen dimension, so the ring block,
	  icon slots, connector bars, and underlines all shrink/grow together
	  with the screen instead of drifting apart from the text bands.
	- Widened every vertical band's margins so there is generous, visible
	  breathing room between title / ring / progress / skip everywhere,
	  not just the bare minimum.
	- Logo screen's three underline bars now use a UIListLayout instead
	  of manual absolute X positions, so they can never overlap each
	  other on narrow screens.
	- Redesigned the 4 hand-built element icons with an extra
	  highlight/glow pass each (shine on the water droplet, soft outer
	  glow behind the lightning bolt, hot tip on the flame, faceted
	  highlight on the earth glyph) so they read as deliberately designed
	  icons instead of flat silhouettes.
	- Waterbending showcase (PHASE 4) rewritten to actually move the
	  whole body, not just the shoulders: added rig detection (R15/R6),
	  waist and hip/knee joints, a 4-beat pose sequence matched frame-by-
	  frame against the Avatar: The Last Airbender intro reference clip
	  (channel stance -> gather overhead -> twisting sweep into a lunge ->
	  frozen low-lunge release), a comet-style water Trail on the lead
	  hand during the sweep, and cinematic camera moves for each beat.

	v5 CHANGELOG (fixes the "everything after EARTH goes black / creator
	credit is gone" report):
	- Root cause of the black screen: a ViewportFrame renders its OWN
	  isolated 3D scene and does NOT inherit the game's Lighting service.
	  Ambient/LightColor default to pure black, so the cloned avatar was
	  rendering as a black silhouette on the black backdrop -- invisible,
	  not broken. Now sets Viewport.Ambient/LightColor/LightDirection
	  explicitly so the avatar is actually lit and visible.
	- Hardened the character lookup: it used to block on
	  `CharacterAdded:Wait()`, which hangs forever if the character had
	  already spawned before that line ran -- silently freezing the
	  entire rest of the intro (creator credit + logo included). Now
	  bounded to an 8s max wait.
	- The whole waterbending showcase body now runs inside `pcall`, and
	  every phase in the master sequence (welcome/loading/elements/
	  waterbending/credit/logo) is run through a `runPhase` wrapper that
	  pcalls it and logs+continues on error, so one broken phase can
	  never again take the rest of the intro down with it.
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
-- RESOLUTION-SAFE SIZING
--
-- Everything that needs a fixed pixel footprint (the loading ring,
-- element icon slots, connector bars, underlines...) is sized off the
-- SMALLER screen dimension instead of a hardcoded pixel value. That way
-- a phone in portrait, a tiny docked Studio test window, and a 4K
-- desktop all get a proportionally identical layout instead of the
-- fixed-pixel block drifting out of its scale-based band and crashing
-- into neighboring text.
-- ============================================================

local viewportSize = workspace.CurrentCamera.ViewportSize

local function vmin(fraction: number): number
	return math.min(viewportSize.X, viewportSize.Y) * fraction
end

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

	-- Shine highlight: a small bright crescent on the upper-left of the
	-- bulb so the droplet reads as glossy/wet rather than a flat blob.
	local shine = Instance.new("Frame")
	shine.Size = UDim2.fromScale(0.22, 0.14)
	shine.AnchorPoint = Vector2.new(0.5, 0.5)
	shine.Position = UDim2.fromScale(0.36, 0.48)
	shine.Rotation = -25
	shine.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.65)
	shine.BackgroundTransparency = 0.15
	shine.BorderSizePixel = 0
	shine.ZIndex = 8
	shine.Parent = bulb
	local shineCorner = Instance.new("UICorner")
	shineCorner.CornerRadius = UDim.new(1, 0)
	shineCorner.Parent = shine

	return holder
end

-- LIGHTNING: a zig-zag bolt built from three angled bars, with a larger,
-- softer, more-transparent duplicate of each bar behind it for a glow.
local function drawLightningIcon(parent, color, size)
	local holder = Instance.new("Frame")
	holder.Size = size
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 7
	holder.Parent = parent

	local glowColor = color:Lerp(Color3.new(1, 1, 1), 0.2)
	local function addGlow(barSize, barPos, rotation)
		local glow = Instance.new("Frame")
		glow.Size = UDim2.new(barSize.X.Scale * 1.5, 0, barSize.Y.Scale * 1.35, 0)
		glow.AnchorPoint = Vector2.new(0.5, 0.5)
		glow.Position = barPos
		glow.Rotation = rotation
		glow.BackgroundColor3 = glowColor
		glow.BackgroundTransparency = 0.65
		glow.BorderSizePixel = 0
		glow.ZIndex = 6
		glow.Parent = holder
		local glowCorner = Instance.new("UICorner")
		glowCorner.CornerRadius = UDim.new(0.4, 0)
		glowCorner.Parent = glow
	end

	addGlow(UDim2.fromScale(0.22, 0.62), UDim2.fromScale(0.58, 0.28), 22)
	addGlow(UDim2.fromScale(0.6, 0.24), UDim2.fromScale(0.48, 0.52), -18)
	addGlow(UDim2.fromScale(0.22, 0.62), UDim2.fromScale(0.4, 0.74), 22)

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

	-- Hot tip: a small bright yellow-white ember at the very top of the
	-- flame so it reads as a real fire rather than a flat orange blob.
	local hotTip = Instance.new("Frame")
	hotTip.Size = UDim2.fromScale(0.16, 0.2)
	hotTip.AnchorPoint = Vector2.new(0.5, 1)
	hotTip.Position = UDim2.fromScale(0.5, 0.62)
	hotTip.BackgroundColor3 = Color3.fromRGB(255, 235, 180)
	hotTip.BackgroundTransparency = 0.1
	hotTip.BorderSizePixel = 0
	hotTip.ZIndex = 9
	hotTip.Parent = holder
	local hotTipCorner = Instance.new("UICorner")
	hotTipCorner.CornerRadius = UDim.new(0.5, 0)
	hotTipCorner.Parent = hotTip

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

	-- Faceted highlight: a small lighter wedge on the front peak's
	-- upper-left face so the mountain reads as a cut rock facet instead
	-- of a flat silhouette.
	local facet = Instance.new("Frame")
	facet.Size = UDim2.fromScale(0.22, 0.3)
	facet.AnchorPoint = Vector2.new(0.5, 1)
	facet.Position = UDim2.fromScale(0.36, 0.72)
	facet.Rotation = 45
	facet.BackgroundColor3 = color:Lerp(Color3.new(1, 1, 1), 0.45)
	facet.BackgroundTransparency = 0.2
	facet.BorderSizePixel = 0
	facet.ZIndex = 8
	facet.Parent = holder
	local facetCorner = Instance.new("UICorner")
	facetCorner.CornerRadius = UDim.new(0.15, 0)
	facetCorner.Parent = facet

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
	tween(topLine, 1, { Size = UDim2.new(0, vmin(0.32), 0, 2) })
	tween(bottomLine, 1, { Size = UDim2.new(0, vmin(0.32), 0, 2) })
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
-- Layout is split into clearly separated vertical bands, each with a
-- comfortable margin to its neighbors, so nothing overlaps:
--   0.04  - 0.115  Title
--   0.135 - 0.17   Subtitle
--   ~0.35 - ~0.65  Ring + 4 element icons (self-contained square block,
--                  actual size driven by vmin() so it never grows/shrinks
--                  out of proportion to the bands around it)
--   0.78  - 0.82   Progress label
--   0.885 - 0.93   Skip button
-- ============================================================

local function createElementSlot(parent, elementName, color, position, drawFn)
	-- Every dimension here comes from vmin() rather than a fixed pixel
	-- value, so the whole slot (icon + label) shrinks and grows in lockstep
	-- with the ring block around it on any screen size. Kept deliberately
	-- compact (relative to the ring block) so the slot+label pair never
	-- reaches far enough beyond the ring's own band to crowd the title or
	-- progress text, even on extreme (very short/wide) viewports.
	local slotSize = vmin(0.075)
	local labelGap = vmin(0.018)
	local labelWidth = vmin(0.14)
	local labelHeight = vmin(0.026)

	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromOffset(slotSize, slotSize)
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
	nameLabel.Size = UDim2.fromOffset(labelWidth, labelHeight)
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	nameLabel.Position = UDim2.new(0.5, 0, 1, labelGap)
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

	-- Title band: 0.04 - 0.115
	local titleMain = makeLabel({
		Parent = container,
		Text = "THE ELEMENTS",
		Font = FONT_TITLE,
		TextColor3 = COLORS.TextPrimary,
		Size = UDim2.fromScale(0.8, 0.075),
		Position = UDim2.fromScale(0.1, 0.04),
		Constrain = true,
		MaxTextSize = 100,
		TextTransparency = 1,
	})

	-- Subtitle band: 0.135 - 0.17 (well clear of the title above)
	local titleSub = makeLabel({
		Parent = container,
		Text = "AWAKENING",
		Font = FONT_SUBTITLE,
		TextColor3 = COLORS.Accent,
		Size = UDim2.fromScale(0.6, 0.035),
		Position = UDim2.fromScale(0.2, 0.135),
		Constrain = true,
		MaxTextSize = 32,
		TextTransparency = 1,
	})

	-- Ring block: a self-contained square region sized off vmin() (the
	-- smaller screen dimension) instead of a fixed pixel box, centered
	-- in its own band with generous clearance from the title above and
	-- the progress label below on every aspect ratio.
	local ringHolderSize = vmin(0.3)
	local ringHolder = Instance.new("Frame")
	ringHolder.Name = "RingHolder"
	ringHolder.Size = UDim2.fromOffset(ringHolderSize, ringHolderSize)
	ringHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	ringHolder.Position = UDim2.fromScale(0.5, 0.5)
	ringHolder.BackgroundTransparency = 1
	ringHolder.ZIndex = 5
	ringHolder.Parent = container

	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.Size = UDim2.fromScale(0.5, 0.5)
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

	-- Four element slots placed at the edges of the ring holder square,
	-- inset well inward from the corners (0.15 / 0.85, not 0.02 / 0.98)
	-- so the slot + its label sit comfortably inside the ring block's own
	-- band and never reach far enough out to touch the title or progress
	-- text above/below, even on extreme (very short/wide) viewports.
	local waterSlot = createElementSlot(ringHolder, "WATER", COLORS.Water, UDim2.fromScale(0.5, 0.15), drawWaterIcon)
	local lightningSlot = createElementSlot(ringHolder, "LIGHTNING", COLORS.Lightning, UDim2.fromScale(0.85, 0.5), drawLightningIcon)
	local fireSlot = createElementSlot(ringHolder, "FIRE", COLORS.Fire, UDim2.fromScale(0.5, 0.85), drawFireIcon)
	local earthSlot = createElementSlot(ringHolder, "EARTH", COLORS.Earth, UDim2.fromScale(0.15, 0.5), drawEarthIcon)

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

	-- Progress band: 0.78 - 0.82, clear of the ring above
	local progressLabel = makeLabel({
		Parent = container,
		Text = "INITIALIZING... 0%",
		Font = FONT_BODY,
		TextColor3 = COLORS.TextPrimary,
		Size = UDim2.fromScale(0.7, 0.04),
		Position = UDim2.fromScale(0.15, 0.78),
		Constrain = true,
		MaxTextSize = 26,
		TextTransparency = 1,
	})

	-- Skip button band: 0.885 - 0.93, fully clear of the progress label
	local skipButton = Instance.new("TextButton")
	skipButton.Name = "SkipButton"
	skipButton.Size = UDim2.fromScale(0.14, 0.045)
	skipButton.Position = UDim2.fromScale(0.5, 0.885)
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
	tween(topBar, 0.6, { Size = UDim2.new(0, vmin(0.55), 0, 6) })
	task.wait(0.15)
	tween(bottomBar, 0.6, { Size = UDim2.new(0, vmin(0.55), 0, 6) })
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
-- PHASE 4: WATERBENDING SHOWCASE
--
-- AVATAR DETECTION: this phase does not use a generic/placeholder model.
-- It grabs whatever character the LOCAL PLAYER is actually wearing right
-- now (localPlayer.Character), clones it, detects whether it's an R15 or
-- R6 rig, and finds whichever of the shoulder/waist/hip/knee joints that
-- specific rig actually has. Any avatar the player is wearing works —
-- nothing is hardcoded to one body. Only WATER gets this full showcase
-- for now; LIGHTNING/FIRE/EARTH stay as the plain title cards above.
--
-- The pose sequence below was built by stepping through the Avatar: The
-- Last Airbender intro reference clip (~2.8s) frame by frame and
-- matching each beat:
--   Beat 0 (~0.0s ref): idle silhouette, arms relaxed at the sides.
--   Beat 1 (~0.5s ref): arms rise out to the sides, elbows bent, palms
--                       forward — the "channeling" stance.
--   Beat 2 (~1.0s ref): arms draw up and in, crossing near the chest/
--                       head — gathering the water overhead.
--   Beat 3 (~1.6s ref): torso twists, the back leg steps into a lunge,
--                       and the arms sweep down and out in a wide arc —
--                       this is where the reference's dramatic water
--                       streak/swoosh happens, so a comet-style Trail
--                       fires on the lead hand here.
--   Beat 4 (~2.2s+ ref): frozen deep low lunge — front knee bent hard,
--                       back leg extended, torso leaned forward, lead
--                       arm thrust low/forward, other arm pulled back —
--                       the final hero freeze-frame of the clip.
-- Real water particles stream from both hands throughout, and an
-- orbiting swirl circles the torso while the water is being gathered.
-- ============================================================

-- Roblox's two common rig skeletons name their joints differently
-- (R15: "RightShoulder"/"Waist"/"RightHip"/"RightKnee"; R6: "Right
-- Shoulder"/"Right Hip", no waist or knees). Detecting which one we're
-- dealing with lets the rest of the animation ask for the right names
-- instead of guessing.
local function detectRigType(character): string?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local ok, rigType = pcall(function()
			return humanoid.RigType
		end)
		if ok and rigType == Enum.HumanoidRigType.R15 then
			return "R15"
		elseif ok and rigType == Enum.HumanoidRigType.R6 then
			return "R6"
		end
	end
	-- Fallback: infer from parts present, in case RigType is unavailable
	if character:FindFirstChild("UpperTorso") then
		return "R15"
	elseif character:FindFirstChild("Torso") then
		return "R6"
	end
	return nil
end

-- Finds the first Motor6D anywhere under `character` whose Name matches
-- one of the given candidates (covers both R15 and R6 naming).
local function findJointByNames(character, names): Motor6D?
	for _, jointName in ipairs(names) do
		local found = character:FindFirstChild(jointName, true)
		if found and found:IsA("Motor6D") then
			return found
		end
	end
	return nil
end

-- Collects every joint we might be able to animate on this specific rig.
-- Only the shoulders are required; waist/hips/knees are used opportunistically
-- if the rig has them (R15 does, R6 doesn't have a waist or knees) so the
-- pose still reads as a full-body lunge on R15 and gracefully falls back to
-- an arms-only pose on R6 or any unusual rig.
local function getBendingJoints(character)
	local joints = {
		RightShoulder = findJointByNames(character, { "RightShoulder", "Right Shoulder" }),
		LeftShoulder = findJointByNames(character, { "LeftShoulder", "Left Shoulder" }),
		Waist = findJointByNames(character, { "Waist" }),
		RightHip = findJointByNames(character, { "RightHip", "Right Hip" }),
		LeftHip = findJointByNames(character, { "LeftHip", "Left Hip" }),
		RightKnee = findJointByNames(character, { "RightKnee" }),
		LeftKnee = findJointByNames(character, { "LeftKnee" }),
	}

	if not (joints.RightShoulder and joints.LeftShoulder) then
		return nil
	end

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

-- A comet-style water streak that follows the lead hand during the sweep
-- and release beats. Built from two Attachments spaced slightly apart on
-- the same hand part -- a Trail naturally interpolates a ribbon between
-- them as the hand moves, so the "épico" swoosh from the reference clip
-- comes for free from the pose tween itself, with no manual per-frame
-- particle code needed.
local function createHandTrail(handPart, color: Color3): Trail?
	if not handPart then
		return nil
	end

	local attachment0 = Instance.new("Attachment")
	attachment0.Name = "TrailAttach0"
	attachment0.Position = Vector3.new(0, 0.05, 0)
	attachment0.Parent = handPart

	local attachment1 = Instance.new("Attachment")
	attachment1.Name = "TrailAttach1"
	attachment1.Position = Vector3.new(0, -0.35, 0)
	attachment1.Parent = handPart

	local trail = Instance.new("Trail")
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Color = ColorSequence.new(color:Lerp(Color3.new(1, 1, 1), 0.5), color)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.7, 0.55),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.45
	trail.MinLength = 0.02
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	trail.LightEmission = 0.6
	trail.Enabled = false
	trail.Parent = handPart

	return trail
end

local function runWaterbendingShowcase()
	-- AVATAR DETECTION: always the local player's own live character,
	-- never a stand-in model. If it hasn't spawned yet we wait for it,
	-- but with a hard timeout -- `CharacterAdded:Wait()` would hang
	-- forever if the character had already spawned (and the event
	-- already fired) before this line ran, which would silently freeze
	-- the ENTIRE rest of the intro (credit + logo screens included).
	local character = localPlayer.Character
	if not character then
		local waited = 0
		local conn
		conn = localPlayer.CharacterAdded:Connect(function(newCharacter)
			character = newCharacter
		end)
		while not character and waited < 8 do
			task.wait(0.1)
			waited += 0.1
		end
		if conn then
			conn:Disconnect()
		end
	end
	if not character then
		return -- safety: skip this phase if we truly can't find a character
	end
	local humanoid = character:WaitForChild("Humanoid", 5)
	if not humanoid then
		return -- safety: skip this phase if we truly can't find a character
	end

	-- The whole showcase body runs inside pcall: this is a lot of
	-- Instance/Viewport/joint code touching the player's live avatar, and
	-- if any single call on it errors (an unusual rig, a stripped part,
	-- etc.) it must NOT take down the rest of the intro sequence with it.
	-- `container` and `displayModel` are declared out here so cleanup
	-- below always runs, whether the phase finished normally or errored.
	local container: Frame? = nil
	local displayModel: Model? = nil

	local ok, err = pcall(function()
	container = Instance.new("Frame")
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

	-- A ViewportFrame renders its own isolated little 3D scene -- it does
	-- NOT inherit the game's Lighting service settings. Left unset,
	-- Ambient/LightColor both default to pure black, so the avatar would
	-- render as a solid black silhouette (indistinguishable from the
	-- black backdrop behind it) no matter how well-lit the pose or
	-- particles are. This is what was actually causing the "black
	-- screen" -- the showcase WAS running, it just had no light to see
	-- it by.
	viewport.Ambient = Color3.fromRGB(130, 135, 145)
	viewport.LightColor = Color3.fromRGB(255, 250, 240)
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.3)

	local worldModel = Instance.new("WorldModel")
	worldModel.Parent = viewport

	-- Clone the player's actual character for display; the live character
	-- stays untouched so the player isn't frozen/edited during the intro.
	displayModel = character:Clone()
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

	-- Detect the rig type up front (R15 vs R6) so we know what to expect
	-- from getBendingJoints below -- this is the explicit "auto-detect the
	-- player's avatar/rig" step.
	local rigType = detectRigType(displayModel)

	local rootPart = displayModel:FindFirstChild("HumanoidRootPart")
	displayModel.Parent = worldModel

	if rootPart then
		rootPart.Anchored = true
		-- Facing is reset to a known, fixed orientation so every pose and
		-- sweep direction below is deterministic regardless of which way
		-- the player happened to be facing in the world.
		rootPart.CFrame = CFrame.new(0, 0, 0)
	end

	-- Rim light so the clone reads clearly against the dark backdrop
	local keyLight = Instance.new("PointLight")
	keyLight.Parent = rootPart or worldModel
	keyLight.Range = 20
	keyLight.Brightness = 2
	keyLight.Color = COLORS.Water

	-- Base hero framing: chest/head height, slight low angle.
	local function frameCamera()
		if not rootPart then
			return
		end
		local focusPoint = rootPart.Position + Vector3.new(0, 1.2, 0)
		local camPos = focusPoint + Vector3.new(0, 0.2, 6.5)
		vpCamera.CFrame = CFrame.lookAt(camPos, focusPoint)
	end
	frameCamera()

	-- Tweens the viewport camera to a new shot over `duration` seconds.
	-- Safe to call even though rootPart is static -- only the camera moves.
	local function cameraShot(camOffset: Vector3, focusOffset: Vector3, duration: number)
		if not rootPart then
			return
		end
		local focusPoint = rootPart.Position + focusOffset
		local camPos = rootPart.Position + camOffset
		local targetCFrame = CFrame.lookAt(camPos, focusPoint)
		TweenService:Create(vpCamera, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { CFrame = targetCFrame }):Play()
	end

	-- Locate whichever bending-relevant joints this specific rig actually
	-- has (shoulders always; waist/hips/knees only on rigs that have them).
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

	-- Comet-style swoosh trail on the lead (right) hand for the sweep and
	-- final release beats -- matches the water streak visible in the
	-- reference clip during the twisting motion.
	local rightTrail = createHandTrail(rightHandPart, COLORS.Water)

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

	-- ---- POSE SEQUENCE ----
	-- poseBody tweens every joint present in `targets` (a table of
	-- jointName -> CFrame offset) from its captured original C0 to
	-- original * offset, all in parallel over `duration` seconds. Joints
	-- the current rig doesn't have (e.g. Waist/Knees on R6) are simply
	-- absent from `joints` and skipped -- this is what makes the same
	-- code produce a full-body lunge on R15 and a clean arms-only pose on
	-- R6 without branching on rig type everywhere.
	if joints then
		local originals = {}
		for jointName, motor in pairs(joints) do
			originals[jointName] = motor.C0
		end

		local function poseBody(targets, duration: number)
			local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
			for jointName, offsetCFrame in pairs(targets) do
				local motor = joints[jointName]
				if motor then
					TweenService:Create(motor, info, { C0 = originals[jointName] * offsetCFrame }):Play()
				end
			end
		end

		-- BEAT 0 (~0.0s ref): idle silhouette, arms relaxed -- the rig's
		-- default pose, so we just hold briefly before starting.
		task.wait(0.3)

		-- BEAT 1 (~0.5s ref): arms rise out to the sides, elbows bent,
		-- palms forward -- the "channeling" stance that opens the clip's
		-- movement.
		poseBody({
			RightShoulder = CFrame.Angles(math.rad(-80), 0, math.rad(-65)),
			LeftShoulder = CFrame.Angles(math.rad(-80), 0, math.rad(65)),
		}, 0.6)
		task.wait(0.65)

		-- BEAT 2 (~1.0s ref): arms draw up and in, crossing near the
		-- chest/head -- gathering the water overhead. Water starts flowing
		-- and the orbiting ring spins up here.
		poseBody({
			RightShoulder = CFrame.Angles(math.rad(-165), 0, math.rad(-15)),
			LeftShoulder = CFrame.Angles(math.rad(-165), 0, math.rad(15)),
			Waist = CFrame.Angles(math.rad(-8), 0, 0),
		}, 0.7)
		if rightEmitter then rightEmitter.Enabled = true end
		if leftEmitter then leftEmitter.Enabled = true end
		if ringSwirl then ringSwirl.Enabled = true end
		cameraShot(Vector3.new(-0.8, 0.6, 6.0), Vector3.new(0, 1.6, 0), 0.9)
		task.wait(0.85)

		-- Orbit the water ring around the torso from here through the end
		-- of the sequence, following the gathering/sweep/release beats.
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

		-- BEAT 3 (~1.6s ref): the "épico" moment -- torso twists, the
		-- back leg steps into a lunge, and both arms sweep down and out
		-- in a wide arc as the water is thrown. The lead-hand Trail turns
		-- on right as the sweep starts so it catches the whole arc.
		if rightTrail then rightTrail.Enabled = true end
		poseBody({
			RightShoulder = CFrame.Angles(math.rad(-40), math.rad(-30), math.rad(-100)),
			LeftShoulder = CFrame.Angles(math.rad(-100), math.rad(20), math.rad(70)),
			Waist = CFrame.Angles(math.rad(15), math.rad(-25), 0),
			RightHip = CFrame.Angles(math.rad(-35), math.rad(-10), 0),
			LeftHip = CFrame.Angles(math.rad(20), math.rad(10), 0),
			RightKnee = CFrame.Angles(math.rad(45), 0, 0),
		}, 0.75)
		cameraShot(Vector3.new(1.6, 0.1, 5.4), Vector3.new(0.3, 1.1, 0), 0.75)
		task.wait(0.8)

		-- BEAT 4 (final ref pose): frozen deep low lunge held for the
		-- "epic" beat -- front knee bent hard, back leg extended, torso
		-- leaned forward, lead arm thrust low/forward, other arm pulled
		-- back. This is the pose the sequence ends and holds on.
		poseBody({
			RightShoulder = CFrame.Angles(math.rad(10), math.rad(-15), math.rad(-80)),
			LeftShoulder = CFrame.Angles(math.rad(-110), math.rad(25), math.rad(85)),
			Waist = CFrame.Angles(math.rad(22), math.rad(-30), 0),
			RightHip = CFrame.Angles(math.rad(-55), math.rad(-15), 0),
			LeftHip = CFrame.Angles(math.rad(35), math.rad(15), 0),
			RightKnee = CFrame.Angles(math.rad(70), 0, 0),
			LeftKnee = CFrame.Angles(math.rad(10), 0, 0),
		}, 0.7)
		if rightTrail then rightTrail.Enabled = false end
		cameraShot(Vector3.new(0.4, -0.15, 4.6), Vector3.new(0.15, 1.0, 0), 0.7)

		-- Hold the freeze-frame -- this is the dramatic beat the whole
		-- sequence builds to, so it gets the longest single hold.
		task.wait(1.75)

		orbitRunning = false
	else
		-- Fallback: no rig joints found at all (unusual/custom rig) --
		-- just hold the water effects on for a beat so the phase still
		-- reads instead of erroring out.
		if rightEmitter then rightEmitter.Enabled = true end
		if leftEmitter then leftEmitter.Enabled = true end
		if ringSwirl then ringSwirl.Enabled = true end
		task.wait(3.2)
	end

	-- Fade out
	if rightEmitter then rightEmitter.Enabled = false end
	if leftEmitter then leftEmitter.Enabled = false end
	if ringSwirl then ringSwirl.Enabled = false end
	if rightTrail then rightTrail.Enabled = false end

	tween(caption, 0.6, { TextTransparency = 1 })
	tween(elementLabel, 0.6, { TextTransparency = 1 })
	tween(glow, 0.6, { BackgroundTransparency = 1 })

	task.wait(0.65)
	end) -- end pcall

	if not ok then
		warn("[IntroSequenceClient] Waterbending showcase hit an error and was skipped:", err)
	end

	-- Cleanup always runs, whether the showcase finished cleanly or hit
	-- an error partway through -- this guarantees the rest of the intro
	-- (creator credit, logo) is never left blocked behind a broken
	-- WATER showcase.
	if displayModel then
		displayModel:Destroy()
	end
	if container then
		container:Destroy()
	end
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
	tween(leftAccent, 0.6, { Size = UDim2.new(0, vmin(0.18), 0, 3) })
	tween(rightAccent, 0.6, { Size = UDim2.new(0, vmin(0.18), 0, 3) })
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

	-- The three underline bars sit in a single-row UIListLayout instead of
	-- three manually-positioned frames. A list layout can never let its
	-- children overlap each other -- it always lays them out in a row
	-- with the given padding between them -- which is what previously
	-- broke on narrow screens (the three fixed 120px-wide bars, spaced by
	-- fixed percentage X positions, physically overlapped once the
	-- screen got narrower than ~480px).
	local underlineRow = Instance.new("Frame")
	underlineRow.Name = "UnderlineRow"
	underlineRow.Size = UDim2.fromScale(0.9, 0.05)
	underlineRow.Position = UDim2.fromScale(0.5, 0.64)
	underlineRow.AnchorPoint = Vector2.new(0.5, 0)
	underlineRow.BackgroundTransparency = 1
	underlineRow.ZIndex = 5
	underlineRow.Parent = container

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.FillDirection = Enum.FillDirection.Horizontal
	rowLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	rowLayout.Padding = UDim.new(0, vmin(0.03))
	rowLayout.Parent = underlineRow

	local underline1 = makeFrame(underlineRow, UDim2.new(0, 0, 0, 4), UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5), COLORS.Water, 0, 5)
	local underline2 = makeFrame(underlineRow, UDim2.new(0, 0, 0, 4), UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5), COLORS.Lightning, 0, 5)
	local underline3 = makeFrame(underlineRow, UDim2.new(0, 0, 0, 4), UDim2.fromScale(0, 0.5), Vector2.new(0, 0.5), COLORS.Fire, 0, 5)

	tween(logoLabel, 1.2, { TextTransparency = 0 })
	tween(bgPulse, 1.2, { BackgroundTransparency = 0.9 })
	task.wait(0.5)
	tween(underline1, 0.7, { Size = UDim2.new(0, vmin(0.14), 0, 4) })
	task.wait(0.2)
	tween(underline2, 0.7, { Size = UDim2.new(0, vmin(0.14), 0, 4) })
	task.wait(0.2)
	tween(underline3, 0.7, { Size = UDim2.new(0, vmin(0.14), 0, 4) })

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

-- Runs a single phase inside pcall so that if it errors, the phase's own
-- content just gets skipped instead of taking every phase after it down
-- with it (this is what let a single broken phase silently swallow the
-- creator credit and logo screens that come after it).
local function runPhase(name: string, phaseFn, ...)
	local ok, err = pcall(phaseFn, ...)
	if not ok then
		warn(("[IntroSequenceClient] Phase '%s' hit an error and was skipped: %s"):format(name, tostring(err)))
	end
end

local function runFullSequence()
	local skipBindable = Instance.new("BindableEvent")

	runPhase("Welcome", runWelcomeScreen)
	runPhase("Loading", runLoadingScreen, skipBindable)
	runPhase("ElementsIntro", runElementsIntro)
	runPhase("WaterbendingShowcase", runWaterbendingShowcase)
	runPhase("CreatorCredit", runCreatorCredit)
	runPhase("LogoScreen", runLogoScreen)

	skipBindable:Destroy()

	tween(backdrop, 1, { BackgroundTransparency = 1 })
	task.wait(1.05)
	screenGui:Destroy()
	musicSound:Stop()
	musicSound:Destroy()
end

runFullSequence()
