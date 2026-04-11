
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
		if (not CorksTargeting.NotorietyFilter[noto]) then
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
