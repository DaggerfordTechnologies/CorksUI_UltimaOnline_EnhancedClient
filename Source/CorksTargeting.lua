
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

-- Name filter: comma separated, case-insensitive partial matches (empty = no filter)
CorksTargeting.NameFilterText = L""
CorksTargeting.NameFilters = {}

CorksTargeting.NotorietyLabels = {
	[2] = L"Innocent (Blue)",
	[3] = L"Friend (Green)",
	[4] = L"Can Attack (Grey)",
	[5] = L"Criminal (Grey)",
	[6] = L"Enemy (Orange)",
	[7] = L"Murderer (Red)",
	[8] = L"Invulnerable (Yellow)",
}

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
	CorksTargeting.PlayersOnly = Interface.LoadBoolean("CorksTargetingPlayersOnly", false)
	CorksTargeting.IgnoreSummons = Interface.LoadBoolean("CorksTargetingIgnoreSummons", false)

	-- Create filter checkboxes
	for i = 2, 8 do
		local templateName = "CorksNotoCheck_" .. i
		CreateWindowFromTemplate(templateName, "Settings_LabelCheckButton", "CorksTargetingWindowScrollChild")
		ButtonSetCheckButtonFlag(templateName .. "Button", true)
		LabelSetText(templateName .. "Label", CorksTargeting.NotorietyLabels[i])

		-- Color the label to match the notoriety
		NameColor.UpdateLabelNameColor(templateName .. "Label", i)

		ButtonSetPressedFlag(templateName .. "Button", CorksTargeting.NotorietyFilter[i])

		if i == 2 then
			WindowAddAnchor(templateName, "topleft", "CorksTargetingWindowScrollChild", "topleft", 10, 5)
		else
			WindowAddAnchor(templateName, "bottomleft", "CorksNotoCheck_" .. (i - 1), "topleft", 0, 8)
		end
	end

	-- Create Players Only checkbox
	local playersTemplate = "CorksPlayersOnlyCheck"
	CreateWindowFromTemplate(playersTemplate, "Settings_LabelCheckButton", "CorksTargetingWindowScrollChild")
	ButtonSetCheckButtonFlag(playersTemplate .. "Button", true)
	LabelSetText(playersTemplate .. "Label", L"Players Only")
	LabelSetTextColor(playersTemplate .. "Label", 255, 255, 255)
	ButtonSetPressedFlag(playersTemplate .. "Button", CorksTargeting.PlayersOnly)
	WindowAddAnchor(playersTemplate, "bottomleft", "CorksNotoCheck_8", "topleft", 0, 20)

	-- Create Ignore Summons checkbox
	local summonsTemplate = "CorksIgnoreSummonsCheck"
	CreateWindowFromTemplate(summonsTemplate, "Settings_LabelCheckButton", "CorksTargetingWindowScrollChild")
	ButtonSetCheckButtonFlag(summonsTemplate .. "Button", true)
	LabelSetText(summonsTemplate .. "Label", L"Ignore Summons")
	LabelSetTextColor(summonsTemplate .. "Label", 255, 255, 255)
	ButtonSetPressedFlag(summonsTemplate .. "Button", CorksTargeting.IgnoreSummons)
	WindowAddAnchor(summonsTemplate, "bottomleft", playersTemplate, "topleft", 0, 8)

	WindowUtils.SetWindowTitle("CorksTargetingWindow", L"Corks' Targeting")
	CorksTargeting.Initialized = true

	-- Name filter last, and protected, so it can never break the rest of the window
	local ok, err = pcall(CorksTargeting.InitNameFilter, summonsTemplate)
	if not ok then
		CorksTargeting.ReportError("init", err)
	end
end

function CorksTargeting.InitNameFilter(anchorTo)
	LabelSetText("CorksNameFilterLabel", L"Name contains (comma separated):")
	LabelSetTextColor("CorksNameFilterLabel", 255, 255, 255)
	WindowClearAnchors("CorksNameFilterLabel")
	WindowAddAnchor("CorksNameFilterLabel", "bottomleft", anchorTo, "topleft", 0, 20)
	WindowClearAnchors("CorksNameFilterBox")
	WindowAddAnchor("CorksNameFilterBox", "bottomleft", "CorksNameFilterLabel", "topleft", 5, 10)

	-- Saved value is optional; a failed load just means an empty filter
	local ok, saved = pcall(Interface.LoadWString, "CorksTargetingNameFilter", L"")
	if ok then
		CorksTargeting.SetNameFilter(saved)
	end
	TextEditBoxSetText("CorksNameFilterBox", CorksTargeting.NameFilterText)
end

function CorksTargeting.ReportError(where, err)
	pcall(WindowUtils.ChatPrint, StringToWString("Corks' Targeting name filter (" .. where .. "): " .. tostring(err)), SystemData.ChatLogFilters.SYSTEM)
end

function CorksTargeting.Shutdown()
	WindowUtils.SaveWindowPosition("CorksTargetingWindow")
	CorksTargeting.SyncFromButtons()
end

function CorksTargeting.SyncFromButtons()
	if not CorksTargeting.Initialized then
		return
	end
	for i = 2, 8 do
		local templateName = "CorksNotoCheck_" .. i
		if DoesWindowNameExist(templateName .. "Button") then
			CorksTargeting.NotorietyFilter[i] = ButtonGetPressedFlag(templateName .. "Button")
			Interface.SaveBoolean("CorksTargetingNoto" .. i, CorksTargeting.NotorietyFilter[i])
		end
	end
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

function CorksTargeting.OnNameFilterEnter()
	CorksTargeting.SyncFromButtons()
	WindowAssignFocus("CorksNameFilterBox", false)
end

function CorksTargeting.NameAllowed(name)
	if table.getn(CorksTargeting.NameFilters) == 0 then
		return true
	end
	if name == nil then
		return false
	end
	local lname = CorksTargeting.ToWString(wstring.lower(CorksTargeting.ToWString(name)))
	for _, filter in ipairs(CorksTargeting.NameFilters) do
		if wstring.find(lname, filter, 1, true) then
			return true
		end
	end
	return false
end

function CorksTargeting.Toggle()
	local wndName = "CorksTargetingWindow"
	if not DoesWindowNameExist(wndName) then
		return
	end
	local showing = WindowGetShowing(wndName)
	WindowSetShowing(wndName, not showing)
end

function CorksTargeting.OnClose()
	CorksTargeting.SyncFromButtons()
	WindowSetShowing("CorksTargetingWindow", false)
end


----------------------------------------------------------------
-- Get all valid mobile targets from the engine directly
----------------------------------------------------------------

function CorksTargeting.GetMobileList()
	-- Try MobilesOnScreen list first
	if table.getn(MobilesOnScreen.MobilesSort) > 0 then
		return MobilesOnScreen.MobilesSort
	end
	-- Fall back to engine API
	local targets = GetAllMobileTargets()
	if targets then
		return targets
	end
	return {}
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
		RegisterWindowData(WindowData.MobileName.Type, mobileId)
		data = WindowData.MobileName[mobileId]
		if (not data) then
			UnregisterWindowData(WindowData.MobileName.Type, mobileId)
			return false
		end
	end

	-- Check visibility
	if GetDistanceFromPlayer(mobileId) >= 22 then
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
	local ok, allowed = pcall(CorksTargeting.NameAllowed, data.MobName)
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
