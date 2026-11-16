----------------------------------------------------------------
-- Gear Watcher Setup: settings for the Gear Watcher's repair alert and list.
-- Opened from the Setup button on the Gear Watcher. The settings themselves live
-- in CorksDurabilityGump (Get / Set), which saves and applies them.
----------------------------------------------------------------

CorksGearWatcherSetup = {}

CorksGearWatcherSetup.WINDOW = "CorksGearWatcherSetup"
-- Size, as in the XML
CorksGearWatcherSetup.WIDTH = 340
CorksGearWatcherSetup.HEIGHT = 470

-- Same classic background as the Gear Watcher, or nil for the standard EC look
CorksGearWatcherSetup.ClassicBackground = 2620
CorksGearWatcherSetup.TitleOffsetY = 8
-- Gump art loaded for the classic background, released on shutdown
CorksGearWatcherSetup.GumpArt = {}

-- Controls (the part of the window name after CorksGearWatcherSetup) and the
-- setting each one changes
CorksGearWatcherSetup.CHECKS = {
	{ row = "Popup", key = "PopupOn", text = "Show the Repair popup" },
	{ row = "Chat",  key = "ChatOn",  text = "Name the item in chat" },
}
CorksGearWatcherSetup.SLIDERS = {
	{ row = "Alert",      key = "AlertPercent", text = "Alert at or below" },
	{ row = "Hide",       key = "HideAbove",    text = "Hide items above" },
	{ row = "Green",      key = "Green",        text = "Green above" },
	{ row = "Yellow",     key = "Yellow",       text = "Yellow above" },
	{ row = "Orange",     key = "Orange",       text = "Orange above" },
	{ row = "DarkOrange", key = "DarkOrange",   text = "Dark orange above" },
}
-- "Show durability as" choices; value is the Format setting
CorksGearWatcherSetup.FORMATS = {
	{ row = "FormatPoints",  value = 1, text = "11 / 50" },
	{ row = "FormatPercent", value = 2, text = "22%" },
	{ row = "FormatBoth",    value = 3, text = "Both" },
}

-- A check box's pressed flag only changes after its click handler, so clicks are
-- applied on the next update
CorksGearWatcherSetup.ChecksDirty = false
CorksGearWatcherSetup.PendingFormat = nil
-- Set while Lua moves a slider, so its OnSlide isn't taken as the player's
CorksGearWatcherSetup.Syncing = false

----------------------------------------------------------------
-- Functions
----------------------------------------------------------------

function CorksGearWatcherSetup.Initialize()
	local S = CorksGearWatcherSetup
	local W = S.WINDOW
	WindowUtils.RestoreWindowPosition(W)
	WindowUtils.LoadScale(W)
	WindowUtils.SetWindowTitle(W, L"Gear Watcher Setup")

	LabelSetText(W .. "AlertHeading", L"Repair alert")
	LabelSetText(W .. "ListHeading", L"Gear Watcher list")
	LabelSetText(W .. "FormatHeading", L"Show durability as:")
	LabelSetText(W .. "ColorHeading", L"Colour levels")
	LabelSetText(W .. "Note", L"Red at or below the dark orange level. The alert shows once for each item, and again after that item is repaired and wears down.")

	for _, check in ipairs(S.CHECKS) do
		ButtonSetCheckButtonFlag(W .. check.row .. "Button", true)
		LabelSetText(W .. check.row .. "Label", StringToWString(check.text))
	end
	for _, choice in ipairs(S.FORMATS) do
		ButtonSetCheckButtonFlag(W .. choice.row .. "Button", true)
		LabelSetText(W .. choice.row .. "Label", StringToWString(choice.text))
	end
	for _, slider in ipairs(S.SLIDERS) do
		local name = W .. slider.row .. "Name"
		-- Colour level names in their own colour
		local color = CorksDurabilityGump.COLORS[slider.key]
		if color then
			LabelSetTextColor(name, color[1], color[2], color[3])
		end
		LabelSetText(name, StringToWString(slider.text))
	end

	S.ApplyClassicLook()
	S.Refresh()
end

function CorksGearWatcherSetup.Shutdown()
	WindowUtils.SaveWindowPosition(CorksGearWatcherSetup.WINDOW)
	CorksGumpArt.ReleaseAll(CorksGearWatcherSetup.GumpArt)
end

-- Draws the classic background (protected, so a problem with the art can never
-- stop the settings working)
function CorksGearWatcherSetup.ApplyClassicLook()
	local S = CorksGearWatcherSetup
	if not S.ClassicBackground then
		return
	end
	local ok, err = pcall(function()
		if CorksGumpArt.ApplyClassic(S.WINDOW, S.ClassicBackground, S.WIDTH, S.HEIGHT, S.GumpArt) then
			CorksGumpArt.FinishClassic(S.WINDOW, S.TitleOffsetY)
		end
	end)
	if not ok then
		pcall(WindowUtils.ChatPrint, StringToWString("Gear Watcher Setup background: " .. tostring(err)), SystemData.ChatLogFilters.SYSTEM)
	end
end

-- Slider position (0..1) for a setting's value, and back
function CorksGearWatcherSetup.ToPosition(key, value)
	local setting = CorksDurabilityGump.SETTINGS[key]
	return (value - setting.min) / (setting.max - setting.min)
end

function CorksGearWatcherSetup.FromPosition(key, position)
	local setting = CorksDurabilityGump.SETTINGS[key]
	return setting.min + math.floor(position * (setting.max - setting.min) + 0.5)
end

-- The text beside a slider
function CorksGearWatcherSetup.ValueText(key, value)
	if key == "HideAbove" and value >= 100 then
		return "None"
	end
	return value .. "%"
end

-- Shows one slider's setting: the slider position and the value beside it
function CorksGearWatcherSetup.ShowSlider(slider)
	local S = CorksGearWatcherSetup
	local row = S.WINDOW .. slider.row
	local value = CorksDurabilityGump.Get(slider.key)
	S.Syncing = true
	pcall(SliderBarSetCurrentPosition, row .. "Slider", S.ToPosition(slider.key, value))
	S.Syncing = false
	LabelSetText(row .. "Value", StringToWString(S.ValueText(slider.key, value)))
end

-- Shows the current settings
function CorksGearWatcherSetup.Refresh()
	local S = CorksGearWatcherSetup
	local W = S.WINDOW
	if not DoesWindowNameExist(W) then
		return
	end
	for _, check in ipairs(S.CHECKS) do
		ButtonSetPressedFlag(W .. check.row .. "Button", CorksDurabilityGump.Get(check.key))
	end
	S.ShowFormat()
	for _, slider in ipairs(S.SLIDERS) do
		S.ShowSlider(slider)
	end
end

-- Ticks only the chosen "Show durability as" box
function CorksGearWatcherSetup.ShowFormat()
	local S = CorksGearWatcherSetup
	local format = CorksDurabilityGump.Get("Format")
	for _, choice in ipairs(S.FORMATS) do
		ButtonSetPressedFlag(S.WINDOW .. choice.row .. "Button", choice.value == format)
	end
end

-- The row a control belongs to: "CorksGearWatcherSetupAlertSlider" -> "Alert"
function CorksGearWatcherSetup.RowOf(windowName, suffix)
	local W = CorksGearWatcherSetup.WINDOW
	return string.match(windowName or "", "^" .. W .. "(.-)" .. suffix .. "$")
end

----------------------------------------------------------------
-- Event Handlers
----------------------------------------------------------------

function CorksGearWatcherSetup.OnUpdate(timePassed)
	local S = CorksGearWatcherSetup
	if S.ChecksDirty then
		S.ChecksDirty = false
		for _, check in ipairs(S.CHECKS) do
			local on = ButtonGetPressedFlag(S.WINDOW .. check.row .. "Button")
			if on ~= CorksDurabilityGump.Get(check.key) then
				CorksDurabilityGump.Set(check.key, on)
			end
		end
	end
	if S.PendingFormat then
		CorksDurabilityGump.Set("Format", S.PendingFormat)
		S.PendingFormat = nil
		-- Put every box right, including re-ticking one that was clicked off
		S.ShowFormat()
	end
end

function CorksGearWatcherSetup.OnCheckButton()
	CorksGearWatcherSetup.ChecksDirty = true
end

-- Clicking the text toggles its check box too
function CorksGearWatcherSetup.OnCheckLabel()
	local button = string.gsub(SystemData.ActiveWindow.name, "Label$", "Button")
	ButtonSetPressedFlag(button, not ButtonGetPressedFlag(button))
	CorksGearWatcherSetup.ChecksDirty = true
end

-- A "Show durability as" box or its text was clicked
function CorksGearWatcherSetup.OnFormatClick()
	local S = CorksGearWatcherSetup
	local name = SystemData.ActiveWindow.name
	local row = S.RowOf(name, "Button") or S.RowOf(name, "Label")
	for _, choice in ipairs(S.FORMATS) do
		if choice.row == row then
			S.PendingFormat = choice.value
		end
	end
end

function CorksGearWatcherSetup.OnSlide()
	local S = CorksGearWatcherSetup
	if S.Syncing then
		return
	end
	local sliderName = SystemData.ActiveWindow.name
	local row = S.RowOf(sliderName, "Slider")
	for _, slider in ipairs(S.SLIDERS) do
		if slider.row == row then
			local wanted = S.FromPosition(slider.key, SliderBarGetCurrentPosition(sliderName))
			local kept = CorksDurabilityGump.Set(slider.key, wanted)
			if kept ~= wanted then
				-- Held back (a colour level can't pass its neighbours): move the slider back
				S.ShowSlider(slider)
			else
				LabelSetText(S.WINDOW .. row .. "Value", StringToWString(S.ValueText(slider.key, kept)))
			end
			return
		end
	end
end

-- Right-click closes the window
function CorksGearWatcherSetup.OnClose()
	CorksGearWatcherSetup.SetOpen(false)
end

-- Whether the window is showing (the repair alert waits while it is)
function CorksGearWatcherSetup.IsOpen()
	local W = CorksGearWatcherSetup.WINDOW
	return DoesWindowNameExist(W) and WindowGetShowing(W) or false
end

-- Open or close the window; it's only created the first time it's opened
function CorksGearWatcherSetup.Toggle()
	CorksGearWatcherSetup.SetOpen(not CorksGearWatcherSetup.IsOpen())
end

function CorksGearWatcherSetup.SetOpen(open)
	local W = CorksGearWatcherSetup.WINDOW
	if not DoesWindowNameExist(W) then
		if open then
			CreateWindow(W, true)
		end
		return
	end
	if not open then
		-- Catch a click made just before closing
		CorksGearWatcherSetup.OnUpdate(0)
	end
	WindowSetShowing(W, open)
	if open then
		CorksGearWatcherSetup.Refresh()
	end
end
