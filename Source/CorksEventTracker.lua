----------------------------------------------------------------
-- Global Variables
----------------------------------------------------------------

CorksEventTracker = {}

-- The Event Tracker window. One setting drives it: the Event Item Tag, text that's
-- in the event's drop messages and in its items' names (e.g. "Unhallowed";
-- several can be given, separated by commas). When a game message containing a
-- tag arrives, the artifact graphic shows over your head and the drop is
-- counted; while the count is 0 the backpack is checked for items with a tag in
-- their name, so drops from before the count started aren't missed. The count
-- is for this session only (it starts at 0 after logging in or reloading the
-- UI); the tag is saved.

-- The default UI already shows the artifact graphic for these (TextParsing.lua), so
-- they're counted here but don't show it a second time.
CorksEventTracker.DEFAULT_UI_ARTIFACT_IDS = {
	[1062317] = true,  -- "For your valor in combating the fallen beast, a special artifact has been bestowed on you."
	[502088]  = true,  -- "A special gift has been placed in your backpack."
	[1154530] = true,  -- "You notice the crest of Minax on your fallen foe's equipment..."
	[1154554] = true,  -- "You recover an artifact bearing the crest of Minax from the rubble."
}

-- Classic UO gump background (base gump art ID), or nil for the standard EC look.
-- The classic controls below are only used along with it.
CorksEventTracker.ClassicBackground = 83
-- Classic background for the entry box (base gump art ID), or nil for the EC box
CorksEventTracker.ClassicTextBox = 3000
-- Classic button art { normal, mouse over, pressed }, or nil for the EC button
CorksEventTracker.ClassicResetButton = { 4005, 4006, 4007 }
CorksEventTracker.ClassicResetEventButton = { 4017, 4018, 4019 }
-- How far below the gump's top edge the title sits (clears the classic border)
CorksEventTracker.TitleOffsetY = 8
-- Gump art loaded for the classic look, released on shutdown
CorksEventTracker.GumpArt = {}

-- Size; must match CorksEventTrackerWindow in the XML
CorksEventTracker.WIDTH = 420
CorksEventTracker.HEIGHT = 304
CorksEventTracker.TEXTBOX_WIDTH = 380
CorksEventTracker.TEXTBOX_HEIGHT = 30
-- How long the count and banner pulse after a drop (seconds)
CorksEventTracker.FLASH_SECONDS = 2.5

-- Text colors
CorksEventTracker.COLOR_OFF = { 130, 130, 130 }
CorksEventTracker.COLOR_COUNT = { 255, 200, 50 }

CorksEventTracker.Total = 0
CorksEventTracker.Loaded = false
-- Interface.TimeSinceLogin when the last drop arrived, nil before the first one
CorksEventTracker.LastDropTime = nil
-- Time since the "Last drop" and drops-per-hour text was redrawn
CorksEventTracker.LastDropTick = 0
-- Drops per hour: drops that came from game messages (not the backpack check)
-- since SessionStart, the Interface.TimeSinceLogin when counting started (UI
-- load, i.e. login or a reload, or Reset Count). Shown once counting has run
-- RATE_MIN_SECONDS, so one early drop doesn't read as a huge rate.
CorksEventTracker.SessionDrops = 0
CorksEventTracker.SessionStart = 0
CorksEventTracker.RATE_MIN_SECONDS = 300
-- Whether the count and banner are pulsing, and for how much longer
CorksEventTracker.Flashing = false
CorksEventTracker.FlashLeft = 0

-- The Event Item Tag. ItemText is what the user typed (saved); ItemPatterns is
-- it split at commas, lower-case. The backpack is rechecked every
-- ITEM_SCAN_SECONDS while the window is open and the count is 0.
CorksEventTracker.ITEM_SCAN_SECONDS = 3
-- Bags inside bags are followed this deep
CorksEventTracker.ITEM_SCAN_DEPTH = 6
CorksEventTracker.ItemText = L""
CorksEventTracker.ItemPatterns = {}
CorksEventTracker.ItemScanTick = 0
-- objectId -> lower-case name, so names are only looked up once
CorksEventTracker.ItemNames = {}

-- Event reward points, read from the event vendor's gump whenever it's open
-- (e.g. Treasures of the Unhallowed, gump 9313). Found by the cliloc of the
-- "Your Reward Points" line, whose parameter is the points, so any event
-- vendor using the same gump works.
CorksEventTracker.REWARD_POINTS_TID = 1159535
-- "Points from this event will expire: <date>"
CorksEventTracker.REWARD_EXPIRE_TID = 1159536
CorksEventTracker.REWARD_CHECK_SECONDS = 0.5
CorksEventTracker.RewardTick = 0
-- Saved: the last points seen, which event, and when they expire (nil until seen)
CorksEventTracker.RewardPoints = nil
CorksEventTracker.RewardEvent = ""
CorksEventTracker.RewardExpires = ""
-- Points at the first reading this session, for "+10 this session"
CorksEventTracker.RewardStart = nil

----------------------------------------------------------------
-- Saved settings
----------------------------------------------------------------

function CorksEventTracker.Load()
	if CorksEventTracker.Loaded then
		return
	end
	CorksEventTracker.Loaded = true

	-- In case this runs before Interface.lua's own call (it's safe to repeat)
	pcall(CorksEventTracker.MigrateSettings)

	CorksEventTracker.SetItemText(Interface.LoadWString("CorksEventTrackerItemName", L""))

	local points = Interface.LoadNumber("CorksEventTrackerRewardPoints", -1)
	if points >= 0 then
		CorksEventTracker.RewardPoints = points
	end
	CorksEventTracker.RewardEvent = WStringToString(Interface.LoadWString("CorksEventTrackerRewardEvent", L""))
	CorksEventTracker.RewardExpires = WStringToString(Interface.LoadWString("CorksEventTrackerRewardExpires", L""))

end

-- Event Tracker used to be called CorksDropAlerts, then CorksEventDrops.
-- Renames its saved settings (tag, reward points, open state, scale,
-- transparency) and saved window position from either old name to the
-- CorksEventTracker names, so nothing is lost. Settings of the old drop message
-- list (CorksDropAlertsCount, ...Text<n>, ...On<n>), which the Event Item Tag
-- replaced, are deleted. Called by Interface.lua before the window is created;
-- does nothing once there's nothing left to rename.
CorksEventTracker.OLD_PREFIXES = { "CorksDropAlerts", "CorksEventDrops" }
CorksEventTracker.NEW_PREFIX = "CorksEventTracker"

function CorksEventTracker.MigrateSettings()
	local new = CorksEventTracker.NEW_PREFIX
	-- The old prefix a name starts with, or nil
	local function oldPrefixOf(name)
		for _, old in ipairs(CorksEventTracker.OLD_PREFIXES) do
			if string.sub(name, 1, string.len(old)) == old then
				return old
			end
		end
		return nil
	end
	local function isOldMessageSetting(name, old)
		local rest = string.sub(name, string.len(old) + 1)
		return rest == "Count" or string.match(rest, "^Text%d+$") or string.match(rest, "^On%d+$")
	end
	-- Renames matching entries of one list of names in place (each value stays
	-- at the same index); returns the old names to delete instead
	local function renameIn(names)
		local remove = {}
		if type(names) ~= "table" then
			return remove
		end
		local present = {}
		for _, name in pairs(names) do
			present[name] = true
		end
		for i, name in pairs(names) do
			local old = type(name) == "string" and oldPrefixOf(name)
			if old then
				local newName = new .. string.sub(name, string.len(old) + 1)
				if isOldMessageSetting(name, old) or present[newName] then
					table.insert(remove, name)
				else
					names[i] = newName
					present[newName] = true
				end
			end
		end
		return remove
	end

	local vars = SystemData.Settings.Interface.UIVariables
	local remove = {}
	for _, list in ipairs({ "BoolNames", "NumberNames", "StringNames", "WStringNames", "ColorNames" }) do
		for _, name in ipairs(renameIn(vars[list])) do
			table.insert(remove, name)
		end
	end
	for _, name in ipairs(remove) do
		Interface.DeleteSetting(name)
	end

	-- The saved window position is kept by window name; a leftover old entry
	-- (when the new one already exists) is harmless and just stays unused
	local positions = SystemData.Settings.Interface.WindowPositions
	if positions then
		renameIn(positions.Names)
	end
end

----------------------------------------------------------------
-- Matching drops
----------------------------------------------------------------

-- Called for every journal line from Interface.NewChatText.
-- Only game messages count, so a player saying the tag won't show the graphic.
-- Some game messages arrive on other channels than SYSTEM, but they all carry a
-- TextID; text players type never does.
function CorksEventTracker.OnChatText()
	if not SystemData.Text then
		return
	end
	local isGameMessage = SystemData.TextChannelID == SystemData.ChatLogFilters.SYSTEM
		or (SystemData.TextID ~= nil and SystemData.TextID ~= 0)
	if not isGameMessage then
		return
	end

	CorksEventTracker.Load()
	local text = string.lower(WStringToString(SystemData.Text))
	if CorksEventTracker.NameMatches(text) then
		CorksEventTracker.Total = CorksEventTracker.Total + 1
		CorksEventTracker.LastDropTime = Interface.TimeSinceLogin
		CorksEventTracker.SessionDrops = CorksEventTracker.SessionDrops + 1
		if not CorksEventTracker.DEFAULT_UI_ARTIFACT_IDS[SystemData.TextID] then
			CenterScreenText.SendCenterScreenTexture("artifact")
		end
		CorksEventTracker.StartFlash()
		CorksEventTracker.Refresh()
	end
end

----------------------------------------------------------------
-- Window
----------------------------------------------------------------

function CorksEventTracker.Initialize()
	SnapUtils.SnappableWindows["CorksEventTrackerWindow"] = true
	WindowUtils.RestoreWindowPosition("CorksEventTrackerWindow", false)
	WindowUtils.LoadScale("CorksEventTrackerWindow")
	WindowUtils.SetWindowTitle("CorksEventTrackerWindow", L"Event Tracker")

	LabelSetText("CorksEventTrackerWindowItemLabel", L"Event Item Tag:")
	ButtonSetText("CorksEventTrackerWindowResetButton", L"Reset Count")
	ButtonSetText("CorksEventTrackerWindowResetEventButton", L"Reset Event")
	WindowSetShowing("CorksEventTrackerWindowResetClassic", false)
	WindowSetShowing("CorksEventTrackerWindowResetEventClassic", false)

	-- The artifact banner: the same art the default UI shows over your head
	DynamicImageSetTexture("CorksEventTrackerWindowBanner", "CST_Artifact", 0, 0)
	DynamicImageSetTextureDimensions("CorksEventTrackerWindowBanner", 220, 80)

	CorksEventTracker.Load()
	CorksEventTracker.Initialized = true
	TextEditBoxSetText("CorksEventTrackerWindowItemTextBox", CorksEventTracker.ItemText)

	-- Protected, so a problem with the art can never break the window
	CorksEventTracker.ButtonArt = {}
	local ok, err = pcall(CorksEventTracker.ApplyClassicControls)
	if not ok then
		CorksEventTracker.ReportArtError(err)
	end
	WindowSetDimensions("CorksEventTrackerWindow", CorksEventTracker.WIDTH, CorksEventTracker.HEIGHT)
	CorksEventTracker.ApplyClassicBackground(CorksEventTracker.HEIGHT)

	CorksEventTracker.ScanBackpack()
	CorksEventTracker.Refresh()
end

function CorksEventTracker.Shutdown()
	WindowUtils.SaveWindowPosition("CorksEventTrackerWindow")
	CorksGumpArt.ReleaseAll(CorksEventTracker.GumpArt)
end

function CorksEventTracker.ReportArtError(err)
	pcall(WindowUtils.ChatPrint, StringToWString("Event Tracker art: " .. tostring(err)), SystemData.ChatLogFilters.SYSTEM)
end

----------------------------------------------------------------
-- Classic look
----------------------------------------------------------------

-- Shows one piece of art in an image made by CorksGumpArt.Image
function CorksEventTracker.SetArt(image, piece)
	DynamicImageSetTexture(image, piece.tex, 0, 0)
	DynamicImageSetTextureDimensions(image, piece.w, piece.h)
	WindowSetDimensions(image, piece.w, piece.h)
end

-- The button and entry box, drawn once when the window opens. Each one keeps
-- its EC version when its art can't be loaded.
function CorksEventTracker.ApplyClassicControls()
	if not CorksEventTracker.ClassicBackground then
		return
	end
	CorksEventTracker.ApplyClassicButton("CorksEventTrackerWindowResetClassic", "CorksEventTrackerWindowResetButton",
		CorksEventTracker.ClassicResetButton, L"Reset Count", CorksEventTracker.OnReset)
	CorksEventTracker.ApplyClassicButton("CorksEventTrackerWindowResetEventClassic", "CorksEventTrackerWindowResetEventButton",
		CorksEventTracker.ClassicResetEventButton, L"Reset Event", CorksEventTracker.OnResetEvent)
	CorksEventTracker.ApplyClassicTextBox("CorksEventTrackerWindowItemTextBox")
end

-- holder is the classic button window, ecButton the EC button it replaces;
-- ids are { normal, mouse over, pressed } (the last two fall back to normal).
function CorksEventTracker.ApplyClassicButton(holder, ecButton, ids, text, action)
	if not ids then
		return
	end
	local owner = CorksEventTracker.GumpArt
	local normal = CorksGumpArt.Request(ids[1], owner)
	if not normal then
		return
	end
	local over = CorksGumpArt.Request(ids[2], owner) or normal
	local pressed = CorksGumpArt.Request(ids[3], owner) or normal

	local art = holder .. "Art"
	CorksGumpArt.Clear(art)
	local _, artHeight = WindowGetDimensions(art)
	local y = math.max(0, math.floor((artHeight - normal.h) / 2))
	local image = CorksGumpArt.Image(art, normal.tex, 0, y, normal.w, normal.h)
	LabelSetText(holder .. "Text", text)

	CorksEventTracker.ButtonArt[holder] = {
		image = image, normal = normal, over = over, pressed = pressed, action = action,
	}
	WindowSetShowing(ecButton, false)
	WindowSetShowing(holder, true)
end

-- Classic white entry box with black text, like Corks' Targeting. The art goes in
-- the box's <box>BG holder.
function CorksEventTracker.ApplyClassicTextBox(box)
	if not CorksEventTracker.ClassicTextBox then
		return
	end
	local holder = box .. "BG"
	CorksGumpArt.Clear(holder)
	if CorksGumpArt.Background(holder, CorksEventTracker.ClassicTextBox,
		CorksEventTracker.TEXTBOX_WIDTH, CorksEventTracker.TEXTBOX_HEIGHT, CorksEventTracker.GumpArt) then
		WindowSetShowing(holder .. "BG", false)
		WindowSetShowing(holder .. "Frame", false)
		TextEditBoxSetTextColor(box, 0, 0, 0)
	end
end

-- Draws the classic background, then lines up the art and the title
-- (CorksGumpArt.FinishClassic re-scales the whole window, which also fixes the
-- size of the classic controls made from Lua). Protected, so a problem with the
-- art can never break the window.
function CorksEventTracker.ApplyClassicBackground(height)
	if not CorksEventTracker.ClassicBackground then
		return
	end
	local ok, err = pcall(function()
		CorksGumpArt.ApplyClassic("CorksEventTrackerWindow", CorksEventTracker.ClassicBackground,
			CorksEventTracker.WIDTH, height, CorksEventTracker.GumpArt)
		CorksGumpArt.FinishClassic("CorksEventTrackerWindow", CorksEventTracker.TitleOffsetY)
	end)
	if not ok then
		CorksEventTracker.ReportArtError(err)
	end
end

function CorksEventTracker.OnClassicButtonDown()
	local state = CorksEventTracker.ButtonArt[SystemData.ActiveWindow.name]
	if state then
		state.down = true
		CorksEventTracker.SetArt(state.image, state.pressed)
	end
end

function CorksEventTracker.OnClassicButtonUp()
	local state = CorksEventTracker.ButtonArt[SystemData.ActiveWindow.name]
	if state then
		CorksEventTracker.SetArt(state.image, state.over)
		if state.down then
			state.down = false
			state.action()
		end
	end
end

function CorksEventTracker.OnClassicButtonOver()
	local state = CorksEventTracker.ButtonArt[SystemData.ActiveWindow.name]
	if state then
		CorksEventTracker.SetArt(state.image, state.over)
	end
end

function CorksEventTracker.OnClassicButtonOverEnd()
	local state = CorksEventTracker.ButtonArt[SystemData.ActiveWindow.name]
	if state then
		state.down = false
		CorksEventTracker.SetArt(state.image, state.normal)
	end
end

----------------------------------------------------------------
-- Drawing
----------------------------------------------------------------

-- A label takes its color when its text is set, so this sets the color first.
function CorksEventTracker.SetLabel(label, text, color)
	LabelSetTextColor(label, color[1], color[2], color[3])
	LabelSetText(label, text)
end

-- The header count. Event items already in the backpack are added to it only
-- while it's 0 (see ScanBackpack), so a drop is never counted twice.
function CorksEventTracker.UpdateTotal()
	LabelSetText("CorksEventTrackerWindowTotalCaption", L"Artifact Count:")
	LabelSetText("CorksEventTrackerWindowTotal", towstring(CorksEventTracker.Total))
end

function CorksEventTracker.FormatAgo(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then
		return seconds .. "s ago"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. "m ago"
	end
	return string.format("%dh %02dm ago", math.floor(seconds / 3600), math.floor(seconds / 60) % 60)
end

-- "Last drop: 4m ago" at the right of the expires line; "No drops yet" before the first drop
-- "4.2 / hr" at the right of the reward points line
function CorksEventTracker.UpdateDropRate()
	local D = CorksEventTracker
	local elapsed = (Interface.TimeSinceLogin or 0) - D.SessionStart
	local text = "-- / hr"
	if elapsed >= D.RATE_MIN_SECONDS then
		local rate = D.SessionDrops * 3600 / elapsed
		if rate < 10 then
			text = string.format("%.1f / hr", rate)
		else
			text = string.format("%d / hr", math.floor(rate + 0.5))
		end
	end
	LabelSetText("CorksEventTrackerWindowDropRate", StringToWString(text))
end

function CorksEventTracker.UpdateLastDrop()
	local text = L"No drops yet"
	if CorksEventTracker.LastDropTime then
		text = StringToWString("Last drop: "
			.. CorksEventTracker.FormatAgo(Interface.TimeSinceLogin - CorksEventTracker.LastDropTime))
	end
	LabelSetText("CorksEventTrackerWindowLastDrop", text)
end

function CorksEventTracker.Refresh()
	if not CorksEventTracker.Initialized or not DoesWindowNameExist("CorksEventTrackerWindow") then
		return
	end
	CorksEventTracker.UpdateTotal()
	CorksEventTracker.UpdateLastDrop()
	CorksEventTracker.UpdateDropRate()
	CorksEventTracker.UpdateRewardPoints()
end

----------------------------------------------------------------
-- Drop flash
----------------------------------------------------------------

CorksEventTracker.FLASH_WINDOWS = { "CorksEventTrackerWindowTotal", "CorksEventTrackerWindowBanner" }

-- Pulses the count and the banner when a drop arrives. Only while the window is
-- showing, as it doesn't update while it's closed.
function CorksEventTracker.StartFlash()
	if CorksEventTracker.Flashing then
		CorksEventTracker.StopFlash()
	end
	if not DoesWindowNameExist("CorksEventTrackerWindow") or not WindowGetShowing("CorksEventTrackerWindow") then
		return
	end
	CorksEventTracker.Flashing = true
	CorksEventTracker.FlashLeft = CorksEventTracker.FLASH_SECONDS
	for _, name in ipairs(CorksEventTracker.FLASH_WINDOWS) do
		WindowStartAlphaAnimation(name, Window.AnimationType.LOOP, 0.35, 1, 0.4, false, 0, 0)
	end
end

function CorksEventTracker.StopFlash()
	CorksEventTracker.Flashing = false
	if not DoesWindowNameExist("CorksEventTrackerWindow") then
		return
	end
	for _, name in ipairs(CorksEventTracker.FLASH_WINDOWS) do
		WindowStopAlphaAnimation(name)
		WindowSetAlpha(name, 1)
	end
end

----------------------------------------------------------------
-- Event Handlers
----------------------------------------------------------------

function CorksEventTracker.OnUpdate(timePassed)
	timePassed = timePassed or 0

	if CorksEventTracker.Flashing then
		CorksEventTracker.FlashLeft = CorksEventTracker.FlashLeft - timePassed
		if CorksEventTracker.FlashLeft <= 0 then
			CorksEventTracker.StopFlash()
		end
	end

	-- Keep "Last drop: 4m ago" current
	CorksEventTracker.LastDropTick = CorksEventTracker.LastDropTick + timePassed
	if CorksEventTracker.LastDropTick >= 1 then
		CorksEventTracker.LastDropTick = 0
		if CorksEventTracker.Initialized then
			CorksEventTracker.UpdateLastDrop()
			CorksEventTracker.UpdateDropRate()
		end
	end

	CorksEventTracker.ItemScanTick = CorksEventTracker.ItemScanTick + timePassed
	if CorksEventTracker.ItemScanTick >= CorksEventTracker.ITEM_SCAN_SECONDS then
		CorksEventTracker.ItemScanTick = 0
		if WindowGetShowing("CorksEventTrackerWindow") then
			CorksEventTracker.ScanBackpack()
		end
	end
end

function CorksEventTracker.OnReset()
	CorksEventTracker.Total = 0
	-- Starts the drops-per-hour over too, e.g. at the start of a farming run
	CorksEventTracker.SessionDrops = 0
	CorksEventTracker.SessionStart = Interface.TimeSinceLogin or 0
	CorksEventTracker.Refresh()
end

-- Starts over for a new event: clears the Event Item Tag, the event name, the
-- saved reward points and the count (with the drops per hour and last drop).
-- If the vendor's gump is still open its points are read again right away.
function CorksEventTracker.OnResetEvent()
	local D = CorksEventTracker

	D.SetItemText(L"")
	D.ItemNames = {}
	Interface.SaveWString("CorksEventTrackerItemName", L"")
	TextEditBoxSetText("CorksEventTrackerWindowItemTextBox", L"")

	D.RewardPoints = nil
	D.RewardEvent = ""
	D.RewardExpires = ""
	D.RewardStart = nil
	D.RewardSeen = nil
	Interface.DeleteSetting("CorksEventTrackerRewardPoints")
	Interface.DeleteSetting("CorksEventTrackerRewardEvent")
	Interface.DeleteSetting("CorksEventTrackerRewardExpires")

	D.LastDropTime = nil
	if D.Flashing then
		D.StopFlash()
	end
	D.OnReset()
end

function CorksEventTracker.OnItemTextClick()
	WindowAssignFocus("CorksEventTrackerWindowItemTextBox", true)
end

-- The tag stays in its box; an empty box stops the counting.
function CorksEventTracker.OnItemTextEnter()
	CorksEventTracker.SetItemText(TextEditBoxGetText("CorksEventTrackerWindowItemTextBox"))
	Interface.SaveWString("CorksEventTrackerItemName", CorksEventTracker.ItemText)
	TextEditBoxSetText("CorksEventTrackerWindowItemTextBox", CorksEventTracker.ItemText)
	WindowAssignFocus("CorksEventTrackerWindowItemTextBox", false)
	CorksEventTracker.ItemScanTick = 0
	CorksEventTracker.ScanBackpack()
	CorksEventTracker.Refresh()
end

function CorksEventTracker.OnItemTextEscape()
	TextEditBoxSetText("CorksEventTrackerWindowItemTextBox", CorksEventTracker.ItemText)
	WindowAssignFocus("CorksEventTrackerWindowItemTextBox", false)
end

----------------------------------------------------------------
-- Backpack items
----------------------------------------------------------------

-- Takes the typed text (wstring); several names can be given, split by commas.
function CorksEventTracker.SetItemText(text)
	local patterns = {}
	local parts = {}
	for part in string.gmatch(WStringToString(text or L""), "[^,]+") do
		part = string.gsub(part, "^%s*(.-)%s*$", "%1")
		if part ~= "" then
			table.insert(patterns, string.lower(part))
			table.insert(parts, part)
		end
	end
	CorksEventTracker.ItemPatterns = patterns
	CorksEventTracker.ItemText = StringToWString(table.concat(parts, ", "))
end

function CorksEventTracker.BackpackId()
	if ContainerWindow and ContainerWindow.PlayerBackpack and ContainerWindow.PlayerBackpack ~= 0 then
		return ContainerWindow.PlayerBackpack
	end
	local slot = WindowData.PlayerEquipmentSlot and WindowData.PlayerEquipmentSlot[EquipmentData.EQPOS_BACKPACK]
	if slot and slot.objectId and slot.objectId ~= 0 then
		return slot.objectId
	end
	return nil
end

-- The item's name in lower case, or nil while the client hasn't got it yet
-- (it's looked up again on the next scan).
function CorksEventTracker.ItemName(objectId)
	local name = CorksEventTracker.ItemNames[objectId]
	if name then
		return name
	end
	local wname = ItemProperties.GetObjectProperties(objectId, 1, "CorksEventTracker")
	if not wname or wname == L"" then
		return nil
	end
	name = string.lower(WStringToString(wname))
	CorksEventTracker.ItemNames[objectId] = name
	return name
end

-- How many items a name stands for: "5 Unhallowed Shards" is a stack of 5
function CorksEventTracker.ItemAmount(name)
	return tonumber(string.match(name, "^(%d+) ")) or 1
end

function CorksEventTracker.NameMatches(name)
	for _, pattern in ipairs(CorksEventTracker.ItemPatterns) do
		if string.find(name, pattern, 1, true) then
			return true
		end
	end
	return false
end

-- Adds up the matching items in a container and the bags in it. Only containers
-- the client has contents for are seen (in practice, ones opened this session).
function CorksEventTracker.CountIn(containerId, depth, seen)
	local registered = false
	if not WindowData.ContainerWindow[containerId] then
		RegisterWindowData(WindowData.ContainerWindow.Type, containerId)
		registered = true
	end
	local total = 0
	local data = WindowData.ContainerWindow[containerId]
	if data and data.ContainedItems then
		for i = 1, (data.numItems or 0) do
			local item = data.ContainedItems[i]
			if item and item.objectId then
				seen[item.objectId] = true
				local name = CorksEventTracker.ItemName(item.objectId)
				if name and CorksEventTracker.NameMatches(name) then
					total = total + CorksEventTracker.ItemAmount(name)
				end
				if depth < CorksEventTracker.ITEM_SCAN_DEPTH then
					total = total + CorksEventTracker.CountIn(item.objectId, depth + 1, seen)
				end
			end
		end
	end
	if registered and not (ContainerWindow and ContainerWindow.OpenContainers and ContainerWindow.OpenContainers[containerId]) then
		UnregisterWindowData(WindowData.ContainerWindow.Type, containerId)
	end
	return total
end

-- While the total is 0 (after logging in, a UI reload or Reset Count), counts
-- the event items already in the backpack and starts the total from them, so
-- drops that arrived before the count started aren't missed. Once the total is
-- above 0 only drop messages add to it, and the backpack isn't checked again.
-- Protected, so a problem reading the backpack can never break the window.
function CorksEventTracker.ScanBackpack()
	if not CorksEventTracker.Initialized or CorksEventTracker.Total > 0 then
		return
	end
	local count = nil
	if #CorksEventTracker.ItemPatterns > 0 then
		local ok, result = pcall(function()
			local backpack = CorksEventTracker.BackpackId()
			if not backpack then
				return nil
			end
			local seen = {}
			local total = CorksEventTracker.CountIn(backpack, 1, seen)
			-- Forget the names of items that have left the backpack
			for objectId in pairs(CorksEventTracker.ItemNames) do
				if not seen[objectId] then
					CorksEventTracker.ItemNames[objectId] = nil
				end
			end
			return total
		end)
		if ok then
			count = result
		end
	end
	if count and count > 0 then
		CorksEventTracker.Total = count
		CorksEventTracker.Refresh()
	end
end

----------------------------------------------------------------
-- Event reward points
----------------------------------------------------------------

-- A gump label parameter (wstring or string) as a plain string
function CorksEventTracker.ParamText(value)
	if type(value) == "string" then
		return value
	end
	local ok, text = pcall(WStringToString, value)
	if ok and type(text) == "string" then
		return text
	end
	return nil
end

-- Called every frame from Interface's update loop, so the points are read even
-- while the Event Tracker window is closed. Looks through the open server gumps
-- for the "Your Reward Points" line.
function CorksEventTracker.CheckRewardGump(timePassed)
	local D = CorksEventTracker
	D.RewardTick = D.RewardTick + (timePassed or 0)
	if D.RewardTick < D.REWARD_CHECK_SECONDS then
		return
	end
	D.RewardTick = 0
	if not GumpData or type(GumpData.Gumps) ~= "table" then
		return
	end
	for _, gump in pairs(GumpData.Gumps) do
		if type(gump) == "table" and type(gump.Labels) == "table" then
			local points, expires
			for _, label in pairs(gump.Labels) do
				if type(label) == "table" and type(label.tidParms) == "table" then
					local param = D.ParamText(label.tidParms[1])
					if label.tid == D.REWARD_POINTS_TID and param then
						-- "1,250" -> 1250
						points = tonumber((string.gsub(param, "[^%d]", "")))
					elseif label.tid == D.REWARD_EXPIRE_TID and param then
						-- "2027-02-01 04:00:00 EST" -> "2027-02-01"
						expires = string.match(param, "^(%S+)") or param
					end
				end
			end
			if points then
				-- The gump's title line is the event's name
				local title = gump.Labels[1]
				local eventName = title and type(title.tidParms) == "table" and D.ParamText(title.tidParms[1]) or ""
				D.RecordRewardPoints(points, eventName, expires or "")
				return
			end
		end
	end
end

function CorksEventTracker.RecordRewardPoints(points, eventName, expires)
	local D = CorksEventTracker
	D.Load()
	-- The first reading this session (or from a different event) is the start
	-- the session's gain is measured from
	if D.RewardStart == nil or eventName ~= D.RewardEvent then
		D.RewardStart = points
	end
	if points == D.RewardPoints and eventName == D.RewardEvent and expires == D.RewardExpires then
		D.RewardSeen = true
		return
	end
	D.RewardPoints = points
	D.RewardEvent = eventName
	D.RewardExpires = expires
	D.RewardSeen = true
	Interface.SaveNumber("CorksEventTrackerRewardPoints", points)
	Interface.SaveWString("CorksEventTrackerRewardEvent", StringToWString(eventName))
	Interface.SaveWString("CorksEventTrackerRewardExpires", StringToWString(expires))
	D.UpdateRewardPoints()
end

-- "Reward points: 1065 (+10 this session)", with "Expires 2027-02-01" on the
-- line under it (one line would run off the gump with 4-5 digit points)
function CorksEventTracker.UpdateRewardPoints()
	local D = CorksEventTracker
	if not D.Initialized or not DoesWindowNameExist("CorksEventTrackerWindow") then
		return
	end
	-- The event's name as the subtitle; blank until the vendor has been visited
	LabelSetText("CorksEventTrackerWindowEventName", StringToWString(D.RewardEvent or ""))

	local label = "CorksEventTrackerWindowRewardPoints"
	local expiresLabel = "CorksEventTrackerWindowRewardExpires"
	local expires = L""
	if D.RewardPoints and D.RewardExpires ~= "" then
		expires = StringToWString("Expires " .. D.RewardExpires)
	end
	LabelSetText(expiresLabel, expires)
	if not D.RewardPoints then
		D.SetLabel(label, L"Reward points: visit the event vendor", D.COLOR_OFF)
		return
	end
	local text = "Reward points: " .. D.RewardPoints
	if not D.RewardSeen then
		text = text .. " (last visit)"
	elseif D.RewardStart and D.RewardPoints ~= D.RewardStart then
		local gain = D.RewardPoints - D.RewardStart
		local sign = ""
		if gain > 0 then
			sign = "+"
		end
		text = text .. " (" .. sign .. gain .. " this session)"
	end
	D.SetLabel(label, StringToWString(text), D.COLOR_COUNT)
end

-- The window only opens when the user turns it on with the Event Tracker action.
-- Whether it's open is saved, so it opens again at login if it was open when the
-- client closed (Interface.lua reads the setting when it creates the window).
-- Drops are matched and counted while it's closed.

-- Open or close the window, creating it again if it was destroyed.
function CorksEventTracker.Toggle()
	local open = DoesWindowNameExist("CorksEventTrackerWindow") and WindowGetShowing("CorksEventTrackerWindow")
	CorksEventTracker.SetOpen(not open)
end

-- Right-click closes the window until the action opens it again.
function CorksEventTracker.OnClose()
	CorksEventTracker.SetOpen(false)
end

function CorksEventTracker.SetOpen(open)
	Interface.SaveBoolean("CorksEventTrackerWindowOpen", open)
	if not DoesWindowNameExist("CorksEventTrackerWindow") then
		if open then
			CreateWindow("CorksEventTrackerWindow", true)
		end
		return
	end
	WindowSetShowing("CorksEventTrackerWindow", open)
	if open then
		CorksEventTracker.Refresh()
	end
end
