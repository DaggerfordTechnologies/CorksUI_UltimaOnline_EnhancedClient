----------------------------------------------------------------
-- Global Variables
----------------------------------------------------------------

CorksEventDrops = {}

-- The Event Drops window. One setting drives it: the Event Item Tag, text that's
-- in the event's drop messages and in its items' names (e.g. "Unhallowed";
-- several can be given, separated by commas). When a game message containing a
-- tag arrives, the artifact graphic shows over your head and the drop is
-- counted; while the count is 0 the backpack is checked for items with a tag in
-- their name, so drops from before the count started aren't missed. The count
-- is for this session only (it starts at 0 after logging in or reloading the
-- UI); the tag is saved.

-- The default UI already shows the artifact graphic for these (TextParsing.lua), so
-- they're counted here but don't show it a second time.
CorksEventDrops.DEFAULT_UI_ARTIFACT_IDS = {
	[1062317] = true,  -- "For your valor in combating the fallen beast, a special artifact has been bestowed on you."
	[502088]  = true,  -- "A special gift has been placed in your backpack."
	[1154530] = true,  -- "You notice the crest of Minax on your fallen foe's equipment..."
	[1154554] = true,  -- "You recover an artifact bearing the crest of Minax from the rubble."
}

-- Classic UO gump background (base gump art ID), or nil for the standard EC look.
-- The classic controls below are only used along with it.
CorksEventDrops.ClassicBackground = 83
-- Classic background for the entry box (base gump art ID), or nil for the EC box
CorksEventDrops.ClassicTextBox = 3000
-- Classic button art { normal, mouse over, pressed }, or nil for the EC button
CorksEventDrops.ClassicResetButton = { 4005, 4006, 4007 }
-- How far below the gump's top edge the title sits (clears the classic border)
CorksEventDrops.TitleOffsetY = 8
-- Gump art loaded for the classic look, released on shutdown
CorksEventDrops.GumpArt = {}

-- Size; must match CorksEventDropsWindow in the XML
CorksEventDrops.WIDTH = 420
CorksEventDrops.HEIGHT = 284
CorksEventDrops.TEXTBOX_WIDTH = 380
CorksEventDrops.TEXTBOX_HEIGHT = 30
-- How long the count and banner pulse after a drop (seconds)
CorksEventDrops.FLASH_SECONDS = 2.5

-- Text colors
CorksEventDrops.COLOR_OFF = { 130, 130, 130 }
CorksEventDrops.COLOR_COUNT = { 255, 200, 50 }

CorksEventDrops.Total = 0
CorksEventDrops.Loaded = false
-- Interface.TimeSinceLogin when the last drop arrived, nil before the first one
CorksEventDrops.LastDropTime = nil
-- Whether the count and banner are pulsing, and for how much longer
CorksEventDrops.Flashing = false
CorksEventDrops.FlashLeft = 0
-- Time since the "Last drop" line was redrawn
CorksEventDrops.LastDropTick = 0

-- The Event Item Tag. ItemText is what the user typed (saved); ItemPatterns is
-- it split at commas, lower-case. The backpack is rechecked every
-- ITEM_SCAN_SECONDS while the window is open and the count is 0.
CorksEventDrops.ITEM_SCAN_SECONDS = 3
-- Bags inside bags are followed this deep
CorksEventDrops.ITEM_SCAN_DEPTH = 6
CorksEventDrops.ItemText = L""
CorksEventDrops.ItemPatterns = {}
CorksEventDrops.ItemScanTick = 0
-- objectId -> lower-case name, so names are only looked up once
CorksEventDrops.ItemNames = {}

-- Event reward points, read from the event vendor's gump whenever it's open
-- (e.g. Treasures of the Unhallowed, gump 9313). Found by the cliloc of the
-- "Your Reward Points" line, whose parameter is the points, so any event
-- vendor using the same gump works.
CorksEventDrops.REWARD_POINTS_TID = 1159535
-- "Points from this event will expire: <date>"
CorksEventDrops.REWARD_EXPIRE_TID = 1159536
CorksEventDrops.REWARD_CHECK_SECONDS = 0.5
CorksEventDrops.RewardTick = 0
-- Saved: the last points seen, which event, and when they expire (nil until seen)
CorksEventDrops.RewardPoints = nil
CorksEventDrops.RewardEvent = ""
CorksEventDrops.RewardExpires = ""
-- Points at the first reading this session, for "+10 this session"
CorksEventDrops.RewardStart = nil

----------------------------------------------------------------
-- Saved settings
----------------------------------------------------------------

function CorksEventDrops.Load()
	if CorksEventDrops.Loaded then
		return
	end
	CorksEventDrops.Loaded = true

	-- In case this runs before Interface.lua's own call (it's safe to repeat)
	pcall(CorksEventDrops.MigrateSettings)

	CorksEventDrops.SetItemText(Interface.LoadWString("CorksEventDropsItemName", L""))

	local points = Interface.LoadNumber("CorksEventDropsRewardPoints", -1)
	if points >= 0 then
		CorksEventDrops.RewardPoints = points
	end
	CorksEventDrops.RewardEvent = WStringToString(Interface.LoadWString("CorksEventDropsRewardEvent", L""))
	CorksEventDrops.RewardExpires = WStringToString(Interface.LoadWString("CorksEventDropsRewardExpires", L""))

end

-- Event Drops used to be called CorksDropAlerts. Renames its saved settings
-- (tag, reward points, open state, scale, transparency) and saved window
-- position to the CorksEventDrops names, so nothing is lost. Settings of the
-- old drop message list (CorksDropAlertsCount, ...Text<n>, ...On<n>), which the
-- Event Item Tag replaced, are deleted. Called by Interface.lua before the
-- window is created; does nothing once there's nothing left to rename.
CorksEventDrops.OLD_PREFIX = "CorksDropAlerts"
CorksEventDrops.NEW_PREFIX = "CorksEventDrops"

function CorksEventDrops.MigrateSettings()
	local old, new = CorksEventDrops.OLD_PREFIX, CorksEventDrops.NEW_PREFIX
	local function isOldMessageSetting(name)
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
			if type(name) == "string" and string.sub(name, 1, string.len(old)) == old then
				local newName = new .. string.sub(name, string.len(old) + 1)
				if isOldMessageSetting(name) or present[newName] then
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
function CorksEventDrops.OnChatText()
	if not SystemData.Text then
		return
	end
	local isGameMessage = SystemData.TextChannelID == SystemData.ChatLogFilters.SYSTEM
		or (SystemData.TextID ~= nil and SystemData.TextID ~= 0)
	if not isGameMessage then
		return
	end

	CorksEventDrops.Load()
	local text = string.lower(WStringToString(SystemData.Text))
	if CorksEventDrops.NameMatches(text) then
		CorksEventDrops.Total = CorksEventDrops.Total + 1
		CorksEventDrops.LastDropTime = Interface.TimeSinceLogin
		if not CorksEventDrops.DEFAULT_UI_ARTIFACT_IDS[SystemData.TextID] then
			CenterScreenText.SendCenterScreenTexture("artifact")
		end
		CorksEventDrops.StartFlash()
		CorksEventDrops.Refresh()
	end
end

----------------------------------------------------------------
-- Window
----------------------------------------------------------------

function CorksEventDrops.Initialize()
	SnapUtils.SnappableWindows["CorksEventDropsWindow"] = true
	WindowUtils.RestoreWindowPosition("CorksEventDropsWindow", false)
	WindowUtils.LoadScale("CorksEventDropsWindow")
	WindowUtils.SetWindowTitle("CorksEventDropsWindow", L"Event Drops")

	LabelSetText("CorksEventDropsWindowItemLabel", L"Event Item Tag:")
	ButtonSetText("CorksEventDropsWindowResetButton", L"Reset Count")
	WindowSetShowing("CorksEventDropsWindowResetClassic", false)

	-- The artifact banner: the same art the default UI shows over your head
	DynamicImageSetTexture("CorksEventDropsWindowBanner", "CST_Artifact", 0, 0)
	DynamicImageSetTextureDimensions("CorksEventDropsWindowBanner", 220, 80)

	CorksEventDrops.Load()
	CorksEventDrops.Initialized = true
	TextEditBoxSetText("CorksEventDropsWindowItemTextBox", CorksEventDrops.ItemText)

	-- Protected, so a problem with the art can never break the window
	CorksEventDrops.ButtonArt = {}
	local ok, err = pcall(CorksEventDrops.ApplyClassicControls)
	if not ok then
		CorksEventDrops.ReportArtError(err)
	end
	WindowSetDimensions("CorksEventDropsWindow", CorksEventDrops.WIDTH, CorksEventDrops.HEIGHT)
	CorksEventDrops.ApplyClassicBackground(CorksEventDrops.HEIGHT)

	CorksEventDrops.ScanBackpack()
	CorksEventDrops.Refresh()
end

function CorksEventDrops.Shutdown()
	WindowUtils.SaveWindowPosition("CorksEventDropsWindow")
	CorksGumpArt.ReleaseAll(CorksEventDrops.GumpArt)
end

function CorksEventDrops.ReportArtError(err)
	pcall(WindowUtils.ChatPrint, StringToWString("Event Drops art: " .. tostring(err)), SystemData.ChatLogFilters.SYSTEM)
end

----------------------------------------------------------------
-- Classic look
----------------------------------------------------------------

-- Shows one piece of art in an image made by CorksGumpArt.Image
function CorksEventDrops.SetArt(image, piece)
	DynamicImageSetTexture(image, piece.tex, 0, 0)
	DynamicImageSetTextureDimensions(image, piece.w, piece.h)
	WindowSetDimensions(image, piece.w, piece.h)
end

-- The button and entry box, drawn once when the window opens. Each one keeps
-- its EC version when its art can't be loaded.
function CorksEventDrops.ApplyClassicControls()
	if not CorksEventDrops.ClassicBackground then
		return
	end
	CorksEventDrops.ApplyClassicButton("CorksEventDropsWindowResetClassic", "CorksEventDropsWindowResetButton",
		CorksEventDrops.ClassicResetButton, L"Reset Count", CorksEventDrops.OnReset)
	CorksEventDrops.ApplyClassicTextBox("CorksEventDropsWindowItemTextBox")
end

-- holder is the classic button window, ecButton the EC button it replaces;
-- ids are { normal, mouse over, pressed } (the last two fall back to normal).
function CorksEventDrops.ApplyClassicButton(holder, ecButton, ids, text, action)
	if not ids then
		return
	end
	local owner = CorksEventDrops.GumpArt
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

	CorksEventDrops.ButtonArt[holder] = {
		image = image, normal = normal, over = over, pressed = pressed, action = action,
	}
	WindowSetShowing(ecButton, false)
	WindowSetShowing(holder, true)
end

-- Classic white entry box with black text, like Corks' Targeting. The art goes in
-- the box's <box>BG holder.
function CorksEventDrops.ApplyClassicTextBox(box)
	if not CorksEventDrops.ClassicTextBox then
		return
	end
	local holder = box .. "BG"
	CorksGumpArt.Clear(holder)
	if CorksGumpArt.Background(holder, CorksEventDrops.ClassicTextBox,
		CorksEventDrops.TEXTBOX_WIDTH, CorksEventDrops.TEXTBOX_HEIGHT, CorksEventDrops.GumpArt) then
		WindowSetShowing(holder .. "BG", false)
		WindowSetShowing(holder .. "Frame", false)
		TextEditBoxSetTextColor(box, 0, 0, 0)
	end
end

-- Draws the classic background, then lines up the art and the title
-- (CorksGumpArt.FinishClassic re-scales the whole window, which also fixes the
-- size of the classic controls made from Lua). Protected, so a problem with the
-- art can never break the window.
function CorksEventDrops.ApplyClassicBackground(height)
	if not CorksEventDrops.ClassicBackground then
		return
	end
	local ok, err = pcall(function()
		CorksGumpArt.ApplyClassic("CorksEventDropsWindow", CorksEventDrops.ClassicBackground,
			CorksEventDrops.WIDTH, height, CorksEventDrops.GumpArt)
		CorksGumpArt.FinishClassic("CorksEventDropsWindow", CorksEventDrops.TitleOffsetY)
	end)
	if not ok then
		CorksEventDrops.ReportArtError(err)
	end
end

function CorksEventDrops.OnClassicButtonDown()
	local state = CorksEventDrops.ButtonArt[SystemData.ActiveWindow.name]
	if state then
		state.down = true
		CorksEventDrops.SetArt(state.image, state.pressed)
	end
end

function CorksEventDrops.OnClassicButtonUp()
	local state = CorksEventDrops.ButtonArt[SystemData.ActiveWindow.name]
	if state then
		CorksEventDrops.SetArt(state.image, state.over)
		if state.down then
			state.down = false
			state.action()
		end
	end
end

function CorksEventDrops.OnClassicButtonOver()
	local state = CorksEventDrops.ButtonArt[SystemData.ActiveWindow.name]
	if state then
		CorksEventDrops.SetArt(state.image, state.over)
	end
end

function CorksEventDrops.OnClassicButtonOverEnd()
	local state = CorksEventDrops.ButtonArt[SystemData.ActiveWindow.name]
	if state then
		state.down = false
		CorksEventDrops.SetArt(state.image, state.normal)
	end
end

----------------------------------------------------------------
-- Drawing
----------------------------------------------------------------

-- A label takes its color when its text is set, so this sets the color first.
function CorksEventDrops.SetLabel(label, text, color)
	LabelSetTextColor(label, color[1], color[2], color[3])
	LabelSetText(label, text)
end

function CorksEventDrops.FormatAgo(seconds)
	seconds = math.max(0, math.floor(seconds))
	if seconds < 60 then
		return seconds .. "s ago"
	elseif seconds < 3600 then
		return math.floor(seconds / 60) .. "m ago"
	end
	return string.format("%dh %02dm ago", math.floor(seconds / 3600), math.floor(seconds / 60) % 60)
end

-- The header count. Event items already in the backpack are added to it only
-- while it's 0 (see ScanBackpack), so a drop is never counted twice.
function CorksEventDrops.UpdateTotal()
	LabelSetText("CorksEventDropsWindowTotalCaption", L"Event Item Count:")
	LabelSetText("CorksEventDropsWindowTotal", towstring(CorksEventDrops.Total))
end

function CorksEventDrops.UpdateLastDrop()
	local text = "No drops yet"
	if #CorksEventDrops.ItemPatterns == 0 then
		text = "Set an Event Item Tag below"
	elseif CorksEventDrops.LastDropTime then
		text = "Last drop: " .. CorksEventDrops.FormatAgo(Interface.TimeSinceLogin - CorksEventDrops.LastDropTime)
	end
	LabelSetText("CorksEventDropsWindowLastDrop", StringToWString(text))
end

function CorksEventDrops.Refresh()
	if not CorksEventDrops.Initialized or not DoesWindowNameExist("CorksEventDropsWindow") then
		return
	end
	CorksEventDrops.UpdateTotal()
	CorksEventDrops.UpdateLastDrop()
	CorksEventDrops.UpdateRewardPoints()
end

----------------------------------------------------------------
-- Drop flash
----------------------------------------------------------------

CorksEventDrops.FLASH_WINDOWS = { "CorksEventDropsWindowTotal", "CorksEventDropsWindowBanner" }

-- Pulses the count and the banner when a drop arrives. Only while the window is
-- showing, as it doesn't update while it's closed.
function CorksEventDrops.StartFlash()
	if CorksEventDrops.Flashing then
		CorksEventDrops.StopFlash()
	end
	if not DoesWindowNameExist("CorksEventDropsWindow") or not WindowGetShowing("CorksEventDropsWindow") then
		return
	end
	CorksEventDrops.Flashing = true
	CorksEventDrops.FlashLeft = CorksEventDrops.FLASH_SECONDS
	for _, name in ipairs(CorksEventDrops.FLASH_WINDOWS) do
		WindowStartAlphaAnimation(name, Window.AnimationType.LOOP, 0.35, 1, 0.4, false, 0, 0)
	end
end

function CorksEventDrops.StopFlash()
	CorksEventDrops.Flashing = false
	if not DoesWindowNameExist("CorksEventDropsWindow") then
		return
	end
	for _, name in ipairs(CorksEventDrops.FLASH_WINDOWS) do
		WindowStopAlphaAnimation(name)
		WindowSetAlpha(name, 1)
	end
end

----------------------------------------------------------------
-- Event Handlers
----------------------------------------------------------------

function CorksEventDrops.OnUpdate(timePassed)
	timePassed = timePassed or 0

	if CorksEventDrops.Flashing then
		CorksEventDrops.FlashLeft = CorksEventDrops.FlashLeft - timePassed
		if CorksEventDrops.FlashLeft <= 0 then
			CorksEventDrops.StopFlash()
		end
	end

	-- Keep "Last drop: 4m ago" current
	CorksEventDrops.LastDropTick = CorksEventDrops.LastDropTick + timePassed
	if CorksEventDrops.LastDropTick >= 1 then
		CorksEventDrops.LastDropTick = 0
		if CorksEventDrops.Initialized then
			CorksEventDrops.UpdateLastDrop()
		end
	end

	CorksEventDrops.ItemScanTick = CorksEventDrops.ItemScanTick + timePassed
	if CorksEventDrops.ItemScanTick >= CorksEventDrops.ITEM_SCAN_SECONDS then
		CorksEventDrops.ItemScanTick = 0
		if WindowGetShowing("CorksEventDropsWindow") then
			CorksEventDrops.ScanBackpack()
		end
	end
end

function CorksEventDrops.OnReset()
	CorksEventDrops.Total = 0
	CorksEventDrops.Refresh()
end

function CorksEventDrops.OnItemTextClick()
	WindowAssignFocus("CorksEventDropsWindowItemTextBox", true)
end

-- The tag stays in its box; an empty box stops the counting.
function CorksEventDrops.OnItemTextEnter()
	CorksEventDrops.SetItemText(TextEditBoxGetText("CorksEventDropsWindowItemTextBox"))
	Interface.SaveWString("CorksEventDropsItemName", CorksEventDrops.ItemText)
	TextEditBoxSetText("CorksEventDropsWindowItemTextBox", CorksEventDrops.ItemText)
	WindowAssignFocus("CorksEventDropsWindowItemTextBox", false)
	CorksEventDrops.ItemScanTick = 0
	CorksEventDrops.ScanBackpack()
	CorksEventDrops.Refresh()
end

function CorksEventDrops.OnItemTextEscape()
	TextEditBoxSetText("CorksEventDropsWindowItemTextBox", CorksEventDrops.ItemText)
	WindowAssignFocus("CorksEventDropsWindowItemTextBox", false)
end

----------------------------------------------------------------
-- Backpack items
----------------------------------------------------------------

-- Takes the typed text (wstring); several names can be given, split by commas.
function CorksEventDrops.SetItemText(text)
	local patterns = {}
	local parts = {}
	for part in string.gmatch(WStringToString(text or L""), "[^,]+") do
		part = string.gsub(part, "^%s*(.-)%s*$", "%1")
		if part ~= "" then
			table.insert(patterns, string.lower(part))
			table.insert(parts, part)
		end
	end
	CorksEventDrops.ItemPatterns = patterns
	CorksEventDrops.ItemText = StringToWString(table.concat(parts, ", "))
end

function CorksEventDrops.BackpackId()
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
function CorksEventDrops.ItemName(objectId)
	local name = CorksEventDrops.ItemNames[objectId]
	if name then
		return name
	end
	local wname = ItemProperties.GetObjectProperties(objectId, 1, "CorksEventDrops")
	if not wname or wname == L"" then
		return nil
	end
	name = string.lower(WStringToString(wname))
	CorksEventDrops.ItemNames[objectId] = name
	return name
end

-- How many items a name stands for: "5 Unhallowed Shards" is a stack of 5
function CorksEventDrops.ItemAmount(name)
	return tonumber(string.match(name, "^(%d+) ")) or 1
end

function CorksEventDrops.NameMatches(name)
	for _, pattern in ipairs(CorksEventDrops.ItemPatterns) do
		if string.find(name, pattern, 1, true) then
			return true
		end
	end
	return false
end

-- Adds up the matching items in a container and the bags in it. Only containers
-- the client has contents for are seen (in practice, ones opened this session).
function CorksEventDrops.CountIn(containerId, depth, seen)
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
				local name = CorksEventDrops.ItemName(item.objectId)
				if name and CorksEventDrops.NameMatches(name) then
					total = total + CorksEventDrops.ItemAmount(name)
				end
				if depth < CorksEventDrops.ITEM_SCAN_DEPTH then
					total = total + CorksEventDrops.CountIn(item.objectId, depth + 1, seen)
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
function CorksEventDrops.ScanBackpack()
	if not CorksEventDrops.Initialized or CorksEventDrops.Total > 0 then
		return
	end
	local count = nil
	if #CorksEventDrops.ItemPatterns > 0 then
		local ok, result = pcall(function()
			local backpack = CorksEventDrops.BackpackId()
			if not backpack then
				return nil
			end
			local seen = {}
			local total = CorksEventDrops.CountIn(backpack, 1, seen)
			-- Forget the names of items that have left the backpack
			for objectId in pairs(CorksEventDrops.ItemNames) do
				if not seen[objectId] then
					CorksEventDrops.ItemNames[objectId] = nil
				end
			end
			return total
		end)
		if ok then
			count = result
		end
	end
	if count and count > 0 then
		CorksEventDrops.Total = count
		CorksEventDrops.Refresh()
	end
end

----------------------------------------------------------------
-- Event reward points
----------------------------------------------------------------

-- A gump label parameter (wstring or string) as a plain string
function CorksEventDrops.ParamText(value)
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
-- while the Event Drops window is closed. Looks through the open server gumps
-- for the "Your Reward Points" line.
function CorksEventDrops.CheckRewardGump(timePassed)
	local D = CorksEventDrops
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

function CorksEventDrops.RecordRewardPoints(points, eventName, expires)
	local D = CorksEventDrops
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
	Interface.SaveNumber("CorksEventDropsRewardPoints", points)
	Interface.SaveWString("CorksEventDropsRewardEvent", StringToWString(eventName))
	Interface.SaveWString("CorksEventDropsRewardExpires", StringToWString(expires))
	D.UpdateRewardPoints()
end

-- "Reward points: 1065 (+10 this session)", with "Expires 2027-02-01" on the
-- line under it (one line would run off the gump with 4-5 digit points)
function CorksEventDrops.UpdateRewardPoints()
	local D = CorksEventDrops
	if not D.Initialized or not DoesWindowNameExist("CorksEventDropsWindow") then
		return
	end
	local label = "CorksEventDropsWindowRewardPoints"
	local expiresLabel = "CorksEventDropsWindowRewardExpires"
	local expires = L""
	if D.RewardPoints and D.RewardExpires ~= "" then
		expires = StringToWString("Expires " .. D.RewardExpires)
	end
	LabelSetText(expiresLabel, expires)
	if not D.RewardPoints then
		D.SetLabel(label, L"Reward points: open the event vendor to read them", D.COLOR_OFF)
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

-- The window only opens when the user turns it on with the Event Drops action.
-- Whether it's open is saved, so it opens again at login if it was open when the
-- client closed (Interface.lua reads the setting when it creates the window).
-- Drops are matched and counted while it's closed.

-- Open or close the window, creating it again if it was destroyed.
function CorksEventDrops.Toggle()
	local open = DoesWindowNameExist("CorksEventDropsWindow") and WindowGetShowing("CorksEventDropsWindow")
	CorksEventDrops.SetOpen(not open)
end

-- Right-click closes the window until the action opens it again.
function CorksEventDrops.OnClose()
	CorksEventDrops.SetOpen(false)
end

function CorksEventDrops.SetOpen(open)
	Interface.SaveBoolean("CorksEventDropsWindowOpen", open)
	if not DoesWindowNameExist("CorksEventDropsWindow") then
		if open then
			CreateWindow("CorksEventDropsWindow", true)
		end
		return
	end
	WindowSetShowing("CorksEventDropsWindow", open)
	if open then
		CorksEventDrops.Refresh()
	end
end

-- Event Drops used to be called CorksDropAlerts. Hotbar buttons copy the action's
-- text when they're placed, so a button made before the rename still runs
-- "script CorksDropAlerts.Toggle()"; this keeps those working. Once every Event
-- Drops hotbar button has been dragged on again from the Actions window, this
-- line can be removed.
CorksDropAlerts = CorksEventDrops
