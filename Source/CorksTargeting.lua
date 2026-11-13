
----------------------------------------------------------------
-- Global Variables
----------------------------------------------------------------

CorksTargeting = {}

CorksTargeting.nxt = 1
CorksTargeting.Initialized = false

-- Notoriety filter settings (default all enabled)
-- Index matches NameColor.Notoriety: 1=None, 2=Innocent(Blue), 3=Friend(Green), 4=CanAttack(Grey), 5=Criminal(Grey), 6=Enemy(Orange), 7=Murderer(Red), 8=Invulnerable(Yellow)
CorksTargeting.NotorietyFilter = {}
CorksTargeting.PlayersOnly = false
CorksTargeting.IgnoreSummons = false

-- Furthest a target can be, in tiles (default 21 matches the old hardcoded limit)
CorksTargeting.MaxDistanceMin = 1
CorksTargeting.MaxDistanceMax = 24
CorksTargeting.MaxDistance = 21

-- Name filter: comma separated, case-insensitive partial matches (empty = no filter)
CorksTargeting.NameFilterText = L""
CorksTargeting.NameFilters = {}

CorksTargeting.NotorietyLabels = {
	[2] = L"Innocent (Blue)",
	[3] = L"Friend (Green)",
	[4] = L"Attackable (Grey)",
	[6] = L"Enemy (Orange)",
	[7] = L"Murderer (Red)",
	[8] = L"Invulnerable (Yellow)",
}

-- Checkboxes shown, in order. Criminal (5) has no checkbox of its own: both greys
-- look the same, so the Grey checkbox (4) controls Criminal too.
CorksTargeting.NotorietyShown = { 2, 3, 4, 6, 7, 8 }

-- Classic UO gump background (base gump art ID), or nil for the standard EC look
CorksTargeting.ClassicBackground = 2620
-- Classic background for the Target Text box (base gump art ID), or nil for the EC box
CorksTargeting.ClassicTextBox = 3000
-- Gump art loaded for the classic background, released on shutdown
CorksTargeting.GumpArt = {}

-- Layout spacing (row height is set by the CorksTargetingCheckRow template)
CorksTargeting.RowGap = 2
CorksTargeting.SectionGap = 12

----------------------------------------------------------------
-- Functions
----------------------------------------------------------------

function CorksTargeting.Initialize()
	SnapUtils.SnappableWindows["CorksTargetingWindow"] = true
	WindowUtils.RestoreWindowPosition("CorksTargetingWindow", false)
	WindowUtils.LoadScale("CorksTargetingWindow")

	-- Load saved settings into memory
	for i = 2, 8 do
		CorksTargeting.NotorietyFilter[i] = Interface.LoadBoolean("CorksTargetingNoto" .. i, true)
	end
	CorksTargeting.NotorietyFilter[5] = CorksTargeting.NotorietyFilter[4]
	CorksTargeting.PlayersOnly = Interface.LoadBoolean("CorksTargetingPlayersOnly", false)
	CorksTargeting.IgnoreSummons = Interface.LoadBoolean("CorksTargetingIgnoreSummons", false)
	CorksTargeting.MaxDistance = CorksTargeting.ClampDistance(Interface.LoadNumber("CorksTargetingMaxDistance", 21))

	-- Create filter checkboxes
	local previous = nil
	for _, i in ipairs(CorksTargeting.NotorietyShown) do
		local templateName = "CorksNotoCheck_" .. i
		CreateWindowFromTemplate(templateName, "CorksTargetingCheckRow", "CorksTargetingWindowScrollChild")
		CorksTargeting.MatchWindowScale(templateName)
		ButtonSetCheckButtonFlag(templateName .. "Button", true)
		LabelSetText(templateName .. "Label", CorksTargeting.NotorietyLabels[i])

		-- Color the label to match the notoriety
		NameColor.UpdateLabelNameColor(templateName .. "Label", i)

		ButtonSetPressedFlag(templateName .. "Button", CorksTargeting.NotorietyFilter[i])

		if previous == nil then
			WindowAddAnchor(templateName, "topleft", "CorksTargetingWindowScrollChild", "topleft", 10, 5)
		else
			WindowAddAnchor(templateName, "bottomleft", previous, "topleft", 0, CorksTargeting.RowGap)
		end
		previous = templateName
	end

	-- Create Players Only checkbox
	local playersTemplate = "CorksPlayersOnlyCheck"
	CreateWindowFromTemplate(playersTemplate, "CorksTargetingCheckRow", "CorksTargetingWindowScrollChild")
	CorksTargeting.MatchWindowScale(playersTemplate)
	ButtonSetCheckButtonFlag(playersTemplate .. "Button", true)
	LabelSetText(playersTemplate .. "Label", L"Players Only")
	LabelSetTextColor(playersTemplate .. "Label", 255, 255, 255)
	ButtonSetPressedFlag(playersTemplate .. "Button", CorksTargeting.PlayersOnly)
	WindowAddAnchor(playersTemplate, "bottomleft", "CorksNotoCheck_8", "topleft", 0, CorksTargeting.SectionGap)

	-- Create Ignore Summons checkbox
	local summonsTemplate = "CorksIgnoreSummonsCheck"
	CreateWindowFromTemplate(summonsTemplate, "CorksTargetingCheckRow", "CorksTargetingWindowScrollChild")
	CorksTargeting.MatchWindowScale(summonsTemplate)
	ButtonSetCheckButtonFlag(summonsTemplate .. "Button", true)
	LabelSetText(summonsTemplate .. "Label", L"Ignore Summons")
	LabelSetTextColor(summonsTemplate .. "Label", 255, 255, 255)
	ButtonSetPressedFlag(summonsTemplate .. "Button", CorksTargeting.IgnoreSummons)
	WindowAddAnchor(summonsTemplate, "bottomleft", playersTemplate, "topleft", 0, CorksTargeting.RowGap)

	WindowUtils.SetWindowTitle("CorksTargetingWindow", L"Corks' Targeting")
	CorksTargeting.Initialized = true

	-- Name filter last, and protected, so it can never break the rest of the window
	local ok, err = pcall(CorksTargeting.InitNameFilter, summonsTemplate)
	if not ok then
		CorksTargeting.ReportError("init", err)
	end

	ok, err = pcall(CorksTargeting.InitMaxDistance)
	if not ok then
		pcall(WindowUtils.ChatPrint, StringToWString("Corks' Targeting max distance: " .. tostring(err)), SystemData.ChatLogFilters.SYSTEM)
	end

	ok, err = pcall(CorksTargeting.ApplyClassicLook)
	if not ok then
		pcall(WindowUtils.ChatPrint, StringToWString("Corks' Targeting background: " .. tostring(err)), SystemData.ChatLogFilters.SYSTEM)
	end

	-- Re-apply the gump's current scale to the whole window, as the mouse-wheel
	-- resize does: the classic art made above only lines up once that happens.
	-- Same value as already set, so the title (fitted at this scale) is unchanged.
	WindowSetScale("CorksTargetingWindow", WindowGetScale("CorksTargetingWindow"))
end

-- Draws the classic background and hides the inner black panel so it shows through.
-- The size must match CorksTargetingWindow in the XML.
function CorksTargeting.ApplyClassicLook()
	if not CorksTargeting.ClassicBackground then
		return
	end
	if CorksGumpArt.ApplyClassic("CorksTargetingWindow", CorksTargeting.ClassicBackground, 230, 404, CorksTargeting.GumpArt) then
		WindowSetShowing("CorksTargetingWindowContentBackground", false)
		WindowSetShowing("CorksTargetingWindowContentFrame", false)
	end
	CorksTargeting.ApplyClassicTextBox()
end

-- Classic white entry box with black text, drawn in the box's border holder
-- (size must match CorksNameFilterBoxBG in the XML).
function CorksTargeting.ApplyClassicTextBox()
	if not CorksTargeting.ClassicTextBox then
		return
	end
	local holder = "CorksNameFilterBoxBG"
	if CorksGumpArt.Background(holder, CorksTargeting.ClassicTextBox, 170, 34, CorksTargeting.GumpArt) then
		WindowSetShowing(holder .. "BG", false)
		WindowSetShowing(holder .. "Frame", false)
		TextEditBoxSetTextColor("CorksNameFilterBox", 0, 0, 0)
		WindowSetScale(holder, WindowGetScale("CorksTargetingWindow"))
	end
end

-- Windows created from Lua after the saved scale was applied start at normal size,
-- so give them the gump's current scale (the mouse-wheel resize scales them too).
function CorksTargeting.MatchWindowScale(windowName)
	WindowSetScale(windowName, WindowGetScale("CorksTargetingWindow"))
end

function CorksTargeting.InitNameFilter(anchorTo)
	LabelSetText("CorksNameFilterLabel", L"Target Text:")
	LabelSetTextColor("CorksNameFilterLabel", 255, 255, 255)
	WindowClearAnchors("CorksNameFilterLabel")
	WindowAddAnchor("CorksNameFilterLabel", "bottomleft", anchorTo, "topleft", 0, CorksTargeting.SectionGap)
	WindowClearAnchors("CorksNameFilterBox")
	WindowAddAnchor("CorksNameFilterBox", "bottomleft", "CorksNameFilterLabel", "topleft", 5, 8)
	WindowClearAnchors("CorksNameFilterBoxBG")
	WindowAddAnchor("CorksNameFilterBoxBG", "topleft", "CorksNameFilterBox", "topleft", -5, -5)

	-- Saved value is optional; a failed load just means an empty filter
	local ok, saved = pcall(Interface.LoadWString, "CorksTargetingNameFilter", L"")
	if ok then
		CorksTargeting.SetNameFilter(saved)
	end
	TextEditBoxSetText("CorksNameFilterBox", CorksTargeting.NameFilterText)
end

----------------------------------------------------------------
-- Max distance slider
----------------------------------------------------------------

function CorksTargeting.ClampDistance(value)
	value = math.floor((tonumber(value) or 21) + 0.5)
	if value < CorksTargeting.MaxDistanceMin then
		return CorksTargeting.MaxDistanceMin
	elseif value > CorksTargeting.MaxDistanceMax then
		return CorksTargeting.MaxDistanceMax
	end
	return value
end

function CorksTargeting.InitMaxDistance()
	LabelSetTextColor("CorksMaxDistanceLabel", 255, 255, 255)
	WindowClearAnchors("CorksMaxDistanceLabel")
	WindowAddAnchor("CorksMaxDistanceLabel", "bottomleft", "CorksNameFilterBoxBG", "topleft", 0, CorksTargeting.SectionGap)
	WindowClearAnchors("CorksMaxDistanceSlider")
	WindowAddAnchor("CorksMaxDistanceSlider", "bottomleft", "CorksMaxDistanceLabel", "topleft", 0, 6)

	-- Slider position runs 0..1 across the min..max range
	local range = CorksTargeting.MaxDistanceMax - CorksTargeting.MaxDistanceMin
	SliderBarSetCurrentPosition("CorksMaxDistanceSlider", (CorksTargeting.MaxDistance - CorksTargeting.MaxDistanceMin) / range)
	CorksTargeting.UpdateMaxDistanceLabel()
end

function CorksTargeting.UpdateMaxDistanceLabel()
	LabelSetText("CorksMaxDistanceLabel", StringToWString("Max Distance: " .. CorksTargeting.MaxDistance .. " tiles"))
end

function CorksTargeting.OnMaxDistanceSlide(pos)
	pos = pos or SliderBarGetCurrentPosition("CorksMaxDistanceSlider")
	local range = CorksTargeting.MaxDistanceMax - CorksTargeting.MaxDistanceMin
	local value = CorksTargeting.ClampDistance(CorksTargeting.MaxDistanceMin + pos * range)
	if value ~= CorksTargeting.MaxDistance then
		CorksTargeting.MaxDistance = value
		Interface.SaveNumber("CorksTargetingMaxDistance", value)
	end
	CorksTargeting.UpdateMaxDistanceLabel()
end

function CorksTargeting.ReportError(where, err)
	pcall(WindowUtils.ChatPrint, StringToWString("Corks' Targeting name filter (" .. where .. "): " .. tostring(err)), SystemData.ChatLogFilters.SYSTEM)
end

function CorksTargeting.Shutdown()
	WindowUtils.SaveWindowPosition("CorksTargetingWindow")
	CorksTargeting.SyncFromButtons()
	CorksGumpArt.ReleaseAll(CorksTargeting.GumpArt)
end

function CorksTargeting.SyncFromButtons()
	if not CorksTargeting.Initialized then
		return
	end
	for _, i in ipairs(CorksTargeting.NotorietyShown) do
		local templateName = "CorksNotoCheck_" .. i
		if DoesWindowNameExist(templateName .. "Button") then
			CorksTargeting.NotorietyFilter[i] = ButtonGetPressedFlag(templateName .. "Button")
			Interface.SaveBoolean("CorksTargetingNoto" .. i, CorksTargeting.NotorietyFilter[i])
		end
	end
	CorksTargeting.NotorietyFilter[5] = CorksTargeting.NotorietyFilter[4]
	if DoesWindowNameExist("CorksPlayersOnlyCheckButton") then
		CorksTargeting.PlayersOnly = ButtonGetPressedFlag("CorksPlayersOnlyCheckButton")
		Interface.SaveBoolean("CorksTargetingPlayersOnly", CorksTargeting.PlayersOnly)
	end
	if DoesWindowNameExist("CorksIgnoreSummonsCheckButton") then
		CorksTargeting.IgnoreSummons = ButtonGetPressedFlag("CorksIgnoreSummonsCheckButton")
		Interface.SaveBoolean("CorksTargetingIgnoreSummons", CorksTargeting.IgnoreSummons)
	end
	if DoesWindowNameExist("CorksNameFilterBox") then
		-- pcall so a bad filter can never stop targeting
		local ok, err = pcall(CorksTargeting.SetNameFilter, TextEditBoxGetText("CorksNameFilterBox"))
		if not ok then
			CorksTargeting.ReportError("read", err)
			CorksTargeting.NameFilters = {}
		end
		pcall(Interface.SaveWString, "CorksTargetingNameFilter", CorksTargeting.NameFilterText)
	end
end

-- Parses L"orc, lich lord" into { L"orc", L"lich lord" } (lowercased, trimmed)
-- type() reports "string" for both strings and wstrings, so probe with wstring.len
function CorksTargeting.ToWString(text)
	if text == nil then
		return L""
	end
	if pcall(wstring.len, text) then
		return text
	end
	return StringToWString(tostring(text))
end

function CorksTargeting.SetNameFilter(text)
	text = CorksTargeting.ToWString(text)
	CorksTargeting.NameFilterText = text
	CorksTargeting.NameFilters = {}
	local lower = CorksTargeting.ToWString(wstring.lower(text))
	local len = wstring.len(lower)
	local start = 1
	while start <= len + 1 do
		local comma = wstring.find(lower, L",", start, true)
		local stop = (comma or (len + 1)) - 1
		-- trim spaces from both ends
		while start <= stop and wstring.sub(lower, start, start) == L" " do
			start = start + 1
		end
		while stop >= start and wstring.sub(lower, stop, stop) == L" " do
			stop = stop - 1
		end
		if stop >= start then
			table.insert(CorksTargeting.NameFilters, wstring.sub(lower, start, stop))
		end
		if not comma then
			break
		end
		start = comma + 1
	end
end

-- Clicking a checkbox's label toggles the checkbox.
function CorksTargeting.OnCheckLabelClick()
	local button = string.gsub(SystemData.ActiveWindow.name, "Label$", "Button")
	ButtonSetPressedFlag(button, not ButtonGetPressedFlag(button))
end

-- Clicking the box gives it keyboard focus so typing goes into it.
function CorksTargeting.OnNameFilterClick()
	WindowAssignFocus("CorksNameFilterBox", true)
end

function CorksTargeting.OnNameFilterEnter()
	CorksTargeting.SyncFromButtons()
	WindowAssignFocus("CorksNameFilterBox", false)
end

-- True when the text contains any of the Target Text filters.
function CorksTargeting.TextMatches(text)
	if text == nil then
		return false
	end
	local lower = CorksTargeting.ToWString(wstring.lower(CorksTargeting.ToWString(text)))
	for _, filter in ipairs(CorksTargeting.NameFilters) do
		if wstring.find(lower, filter, 1, true) then
			return true
		end
	end
	return false
end

-- Checks the name first, then every line of the mobile's tooltip (where event tags
-- and the like are shown). Tooltip data may not have arrived yet: it is requested and
-- kept while the mobile is around, so it can match on a later key press.
function CorksTargeting.NameAllowed(name, mobileId)
	if table.getn(CorksTargeting.NameFilters) == 0 then
		return true
	end
	if CorksTargeting.TextMatches(name) then
		return true
	end
	if mobileId == nil then
		return false
	end

	local data = WindowData.ItemProperties[mobileId]
	if not data and not CorksTargeting.RegisteredProps[mobileId] then
		RegisterWindowData(WindowData.ItemProperties.Type, mobileId)
		CorksTargeting.RegisteredProps[mobileId] = true
		data = WindowData.ItemProperties[mobileId]
	end
	if not data or not data.PropertiesList then
		return false
	end
	for _, line in ipairs(data.PropertiesList) do
		if CorksTargeting.TextMatches(WindowUtils.translateMarkup(line)) then
			return true
		end
	end
	return false
end

-- The window only opens when the user turns it on with the Targeting Gump action.
-- Whether it's open is saved, so it opens again at login if it was open when the
-- client closed (Interface.lua reads the setting when it creates the window).
-- The window is always created, so the targeting actions work while it's closed.

-- Open or close the window, creating it again if it was destroyed.
function CorksTargeting.Toggle()
	local open = DoesWindowNameExist("CorksTargetingWindow") and WindowGetShowing("CorksTargetingWindow")
	CorksTargeting.SetOpen(not open)
end

-- Right-click closes the window until the action opens it again.
function CorksTargeting.OnClose()
	CorksTargeting.SetOpen(false)
end

function CorksTargeting.SetOpen(open)
	Interface.SaveBoolean("CorksTargetingWindowOpen", open)
	if not DoesWindowNameExist("CorksTargetingWindow") then
		if open then
			CreateWindow("CorksTargetingWindow", true)
		end
		return
	end
	if not open then
		CorksTargeting.SyncFromButtons()
	end
	WindowSetShowing("CorksTargetingWindow", open)
end


----------------------------------------------------------------
-- Get all valid mobile targets from the engine directly
----------------------------------------------------------------

-- Mobiles whose name data this file asked for, so it can be released when they leave.
CorksTargeting.RegisteredNames = {}
-- Mobiles whose tooltip data (properties) the Target Text filter asked for.
CorksTargeting.RegisteredProps = {}

-- Every mobile the client knows about, nearest first, without you, your pets or your
-- party. Built fresh on each key press: MobilesOnScreen's list only holds mobiles
-- whose names had already loaded when it was last rebuilt, so newly arrived mobs
-- could be missing from it.
function CorksTargeting.GetMobileList()
	local targets = GetAllMobileTargets() or {}
	local present = {}
	local list = {}
	for _, mobileId in pairs(targets) do
		present[mobileId] = true
		if mobileId ~= WindowData.PlayerStatus.PlayerId
			and not MobilesOnScreen.IsPet(mobileId)
			and not HealthBarManager.IsPartyMember(mobileId) then
			table.insert(list, { id = mobileId, dist = GetDistanceFromPlayer(mobileId) })
		end
	end

	-- Stop listening for mobiles that have gone.
	for mobileId in pairs(CorksTargeting.RegisteredNames) do
		if not present[mobileId] then
			UnregisterWindowData(WindowData.MobileName.Type, mobileId)
			CorksTargeting.RegisteredNames[mobileId] = nil
		end
	end
	for mobileId in pairs(CorksTargeting.RegisteredProps) do
		if not present[mobileId] then
			UnregisterWindowData(WindowData.ItemProperties.Type, mobileId)
			CorksTargeting.RegisteredProps[mobileId] = nil
		end
	end

	table.sort(list, function(a, b) return a.dist < b.dist end)
	local ids = {}
	for i, entry in ipairs(list) do
		ids[i] = entry.id
	end
	return ids
end

----------------------------------------------------------------
-- Target selection (suppresses context menu)
----------------------------------------------------------------

CorksTargeting.SuppressContextMenu = false
CorksTargeting.org_ContextMenuShow = nil

function CorksTargeting.HookContextMenu()
	if CorksTargeting.org_ContextMenuShow then
		return
	end
	CorksTargeting.org_ContextMenuShow = ContextMenu.Show
	ContextMenu.Show = function()
		if CorksTargeting.SuppressContextMenu then
			CorksTargeting.SuppressContextMenu = false
			WindowSetShowing("ContextMenu", false)
			return
		end
		CorksTargeting.org_ContextMenuShow()
	end
end

function CorksTargeting.SelectTarget(mobileId)
	CorksTargeting.HookContextMenu()
	CorksTargeting.SuppressContextMenu = true
	HandleSingleLeftClkTarget(mobileId)
end

----------------------------------------------------------------
-- Targeting Filter
----------------------------------------------------------------

function CorksTargeting.TargetAllowed(mobileId)
	if (mobileId == WindowData.PlayerStatus.PlayerId) then
		return false
	end

	if not IsMobile(mobileId) then
		return false
	end

	local data = WindowData.MobileName[mobileId]
	if (not data) then
		-- Ask for the name and notoriety and keep asking: they arrive from the server
		-- shortly after, so the mobile can be picked on the next key press.
		-- GetMobileList releases the request once the mobile is gone.
		if not CorksTargeting.RegisteredNames[mobileId] then
			RegisterWindowData(WindowData.MobileName.Type, mobileId)
			CorksTargeting.RegisteredNames[mobileId] = true
		end
		data = WindowData.MobileName[mobileId]
		if (not data) then
			return false
		end
	end
	if data.Notoriety == nil then
		return false
	end

	-- Check distance
	if GetDistanceFromPlayer(mobileId) > CorksTargeting.MaxDistance then
		return false
	end

	-- Check notoriety filter
	local noto = data.Notoriety + 1
	if noto >= 2 and noto <= 8 then
		if (CorksTargeting.NotorietyFilter[noto] == false) then
			return false
		end
	end

	-- Check players only filter
	if CorksTargeting.PlayersOnly then
		-- Exclude pets
		if IsObjectIdPet(mobileId) then
			return false
		end
		-- Exclude known creatures/NPCs from CreaturesDB
		if CreaturesDB.GetName(mobileId) then
			return false
		end
		-- Exclude invulnerable NPCs (vendors, guards, healers, etc.)
		if noto == NameColor.Notoriety.INVULNERABLE then
			return false
		end
	end

	-- Check ignore summons filter
	if CorksTargeting.IgnoreSummons then
		if MobilesOnScreen.IsSummon(data.MobName, mobileId) then
			return false
		end
	end

	-- Check name filter
	local ok, allowed = pcall(CorksTargeting.NameAllowed, data.MobName, mobileId)
	if not ok then
		CorksTargeting.ReportError("match", allowed)
	elseif not allowed then
		return false
	end

	return true
end

----------------------------------------------------------------
-- Target Nearest (Notoriety)
----------------------------------------------------------------

function CorksTargeting.NearTarget()
	CorksTargeting.SyncFromButtons()

	local mobileList = CorksTargeting.GetMobileList()
	local candidates = {}
	for i = 1, table.getn(mobileList) do
		local mobileId = mobileList[i]
		if CorksTargeting.TargetAllowed(mobileId) then
			table.insert(candidates, { id = mobileId, dist = GetDistanceFromPlayer(mobileId) })
		end
	end
	table.sort(candidates, function(a, b) return a.dist < b.dist end)
	for _, entry in ipairs(candidates) do
		if (TargetWindow.TargetId == entry.id) then
			return
		end
		if CorksTargeting.TargetAllowed(entry.id) then
			CorksTargeting.SelectTarget(entry.id)
			if (WindowGetShowing("TargetWindow") and TargetWindow.TargetId == entry.id) then
				return
			end
		end
	end
end

----------------------------------------------------------------
-- Target Next (Notoriety)
----------------------------------------------------------------

function CorksTargeting.NextTarget()
	CorksTargeting.SyncFromButtons()

	local mobileList = CorksTargeting.GetMobileList()
	local listSize = table.getn(mobileList)

	if listSize == 0 then
		return
	end

	if CorksTargeting.nxt > listSize then
		CorksTargeting.nxt = 1
	end

	local final = 0
	for i = CorksTargeting.nxt, listSize do
		local mobileId = mobileList[i]
		if (CorksTargeting.TargetAllowed(mobileId) and mobileId ~= TargetWindow.TargetId) then
			CorksTargeting.SelectTarget(mobileId)
			if (WindowGetShowing("TargetWindow") and TargetWindow.TargetId == mobileId) then
				final = mobileId
				CorksTargeting.nxt = i + 1
				if (CorksTargeting.nxt > listSize) then
					CorksTargeting.nxt = 1
				end
				return
			end
		end
	end
	-- Wrap around from beginning if we didn't find anything past nxt
	if final == 0 and CorksTargeting.nxt > 1 then
		for i = 1, CorksTargeting.nxt - 1 do
			local mobileId = mobileList[i]
			if (CorksTargeting.TargetAllowed(mobileId) and mobileId ~= TargetWindow.TargetId) then
				CorksTargeting.SelectTarget(mobileId)
				if (WindowGetShowing("TargetWindow") and TargetWindow.TargetId == mobileId) then
					CorksTargeting.nxt = i + 1
					return
				end
			end
		end
	end
	CorksTargeting.nxt = 1
end

----------------------------------------------------------------
-- Target Previous (Notoriety)
----------------------------------------------------------------

function CorksTargeting.PrevTarget()
	CorksTargeting.SyncFromButtons()

	local currentId = TargetWindow.TargetId
	if currentId and currentId ~= 0 then
		for i = table.getn(TargetWindow.PreviousTargets), 1, -1 do
			if TargetWindow.PreviousTargets[i] == currentId then
				table.remove(TargetWindow.PreviousTargets, i)
				break
			end
		end
	end
	local previous = CorksTargeting.SearchValidPrevTarget()
	if (previous and previous.id ~= TargetWindow.TargetId) then
		CorksTargeting.SelectTarget(previous.id)
	end
end

function CorksTargeting.SearchValidPrevTarget()
	local max = table.getn(TargetWindow.PreviousTargets)
	for i = max, 1, -1 do
		if (TargetWindow.PreviousTargets[i] ~= TargetWindow.TargetId and IsMobile(TargetWindow.PreviousTargets[i])) then
			if CorksTargeting.TargetAllowed(TargetWindow.PreviousTargets[i]) then
				return { id = TargetWindow.PreviousTargets[i], idx = i }
			end
		end
	end
end
