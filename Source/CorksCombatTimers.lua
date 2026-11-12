----------------------------------------------------------------
-- Global Variables
----------------------------------------------------------------

CorksCombatTimers = {}

-- Each entry becomes a row while its ability is up or cooling down. An ability is
-- spotted one of two ways:
--
--   buffId: the client shows a buff icon while the ability is active; this is that
--     icon's id. The row goes through all three stages below.
--   triggerTexts: for instant abilities with no buff icon. When a game message
--     containing one of these (lowercase) arrives, the cooldown starts.
--
--   Active:   from when the buff appears until it ends, using the buff's own timer
--             (activeDuration is used when the buff doesn't send one).
--   Cooldown: from when the buff ends (or the trigger message), for cooldown seconds.
--   Ready:    shown for READY_DISPLAY_TIME seconds, then the row is removed.
CorksCombatTimers.Timers = {
	{
		title          = L"Evasion",
		buffId         = 1094,  -- AB_EVASION
		activeDuration = 8,
		cooldown       = 20,    -- the default UI's hotbar uses 20 seconds too
		color          = { r = 120, g = 220, b = 255 },  -- light blue
	},
	{
		title          = L"War Cry",
		buffId         = 1148,  -- AB_WAR_CRY_BUFF
		activeDuration = 10,
		cooldown       = 1200,  -- 20 minutes
		color          = { r = 255, g = 90, b = 90 },  -- red
	},
	{
		title          = L"Rejuvenate",  -- Chivalry mastery
		triggerTexts   = { "you feel completely rejuvenated" },
		cooldown       = 3600,  -- 1 hour
		color          = { r = 255, g = 215, b = 140 },  -- light gold
	},
}

-- Rows defined in CorksCombatTimers.xml. Timers beyond this many at once aren't shown.
CorksCombatTimers.MAX_ROWS = 4

-- How long "Ready" stays on screen before a row is removed.
CorksCombatTimers.READY_DISPLAY_TIME = 3

-- Bar colors for each phase.
CorksCombatTimers.ACTIVE_BAR = { r = 70, g = 130, b = 255 }
CorksCombatTimers.COOLDOWN_BAR = { r = 255, g = 60, b = 60 }
CorksCombatTimers.READY_BAR = { r = 0, g = 200, b = 0 }

CorksCombatTimers.VisibleRows = 0

----------------------------------------------------------------
-- Functions
----------------------------------------------------------------

function CorksCombatTimers.Initialize()
	-- Toggle can recreate the window mid-session; keep any timers already running.
	for _, timer in ipairs(CorksCombatTimers.Timers) do
		if timer.phase == nil then
			CorksCombatTimers.Reset(timer)
		end
	end

	CorksCombatTimers.VisibleRows = 0
	for i = 1, CorksCombatTimers.MAX_ROWS do
		CorksTimers.RowLabels["CorksCombatTimersRow" .. i] = nil
		WindowSetShowing("CorksCombatTimersRow" .. i, false)
	end

	WindowSetScale("CorksCombatTimers", SystemData.Settings.Interface.customUiScale * 0.80)
	WindowUtils.LoadScale("CorksCombatTimers")
	WindowUtils.SetWindowTitle("CorksCombatTimers", L"Combat Timers")

	WindowUtils.RestoreWindowPosition("CorksCombatTimers")
	CorksCombatTimers.Refresh()

	-- Buff changes are watched on Root so they arrive whether or not this window
	-- is open. The default buff bar already registers the buff data.
	if not CorksCombatTimers.BuffHandlerRegistered then
		WindowRegisterEventHandler("Root", WindowData.BuffDebuff.Event, "CorksCombatTimers.OnBuffEvent")
		CorksCombatTimers.BuffHandlerRegistered = true
	end
end

function CorksCombatTimers.Shutdown()
	WindowUtils.SaveWindowPosition("CorksCombatTimers")
end

-- The window only opens when the user turns it on with the Combat Timers action.
-- Whether it's open is saved, so it opens again at login if it was open when the
-- client closed (Interface.lua reads the setting when it creates the window).
-- Timers keep running while it's closed.

-- Right-click closes the window until the action opens it again.
function CorksCombatTimers.OnClose()
	CorksCombatTimers.SetOpen(false)
end

-- Open or close the window, creating it again if it was destroyed.
function CorksCombatTimers.Toggle()
	local open = DoesWindowNameExist("CorksCombatTimers") and WindowGetShowing("CorksCombatTimers")
	CorksCombatTimers.SetOpen(not open)
end

function CorksCombatTimers.SetOpen(open)
	Interface.SaveBoolean("CorksCombatTimersOpen", open)
	if not DoesWindowNameExist("CorksCombatTimers") then
		if open then
			CreateWindow("CorksCombatTimers", true)
		end
		return
	end
	WindowSetShowing("CorksCombatTimers", open)
	if open then
		CorksCombatTimers.Refresh()
	end
end

function CorksCombatTimers.Reset(timer)
	timer.phase = "none"
	timer.remaining = 0
	timer.barMax = 1
end

function CorksCombatTimers.IsActive(timer)
	return timer.phase ~= nil and timer.phase ~= "none"
end

-- A buff was added, refreshed or removed.
function CorksCombatTimers.OnBuffEvent()
	local buffId = WindowData.BuffDebuffSystem and WindowData.BuffDebuffSystem.CurrentBuffId
	if not buffId or buffId == 0 then
		return
	end

	for _, timer in ipairs(CorksCombatTimers.Timers) do
		if timer.buffId == buffId then
			local data = WindowData.BuffDebuff
			if data.IsBeingRemoved then
				-- The active countdown may already have run out and started the cooldown.
				if timer.phase == "active" then
					CorksCombatTimers.StartCooldown(timer)
				end
			else
				local seconds = timer.activeDuration
				if data.HasTimer and data.TimerSeconds and data.TimerSeconds > 0 then
					seconds = data.TimerSeconds
				end
				timer.phase = "active"
				timer.remaining = seconds
				timer.barMax = seconds
			end
			CorksCombatTimers.Refresh()
			return
		end
	end
end

-- Called for every journal line from Interface.NewChatText.
-- Only game messages count, so a player saying the phrase won't start a timer. Some
-- game messages arrive on other channels than SYSTEM, but they all carry a TextID;
-- text players type never does.
function CorksCombatTimers.OnChatText()
	if not SystemData.Text then
		return
	end
	local isGameMessage = SystemData.TextChannelID == SystemData.ChatLogFilters.SYSTEM
		or (SystemData.TextID ~= nil and SystemData.TextID ~= 0)
	if not isGameMessage then
		return
	end

	local text
	for _, timer in ipairs(CorksCombatTimers.Timers) do
		if timer.triggerTexts then
			text = text or string.lower(WStringToString(SystemData.Text))
			for _, trigger in ipairs(timer.triggerTexts) do
				if string.find(text, trigger, 1, true) then
					CorksCombatTimers.StartCooldown(timer)
					CorksCombatTimers.Refresh()
					break
				end
			end
		end
	end
end

function CorksCombatTimers.StartCooldown(timer)
	if timer.cooldown and timer.cooldown > 0 then
		timer.phase = "cooldown"
		timer.remaining = timer.cooldown
		timer.barMax = timer.cooldown
	else
		timer.phase = "ready"
		timer.remaining = CorksCombatTimers.READY_DISPLAY_TIME
	end
end

-- Called every frame from Interface.Update.
function CorksCombatTimers.OnUpdate(timePassed)
	local changed = false
	for _, timer in ipairs(CorksCombatTimers.Timers) do
		if CorksCombatTimers.IsActive(timer) then
			CorksCombatTimers.UpdateTimer(timer, timePassed)
			changed = true
		end
	end
	if changed then
		CorksCombatTimers.Refresh()
	end
end

function CorksCombatTimers.UpdateTimer(timer, timePassed)
	timer.remaining = timer.remaining - timePassed
	if timer.remaining > 0 then
		return
	end

	if timer.phase == "active" then
		-- Usually the buff-removed event gets here first; this covers a missed one.
		CorksCombatTimers.StartCooldown(timer)
	elseif timer.phase == "cooldown" then
		timer.phase = "ready"
		timer.remaining = CorksCombatTimers.READY_DISPLAY_TIME
	else
		CorksCombatTimers.Reset(timer)
	end
end

-- Fill the rows with the running timers, sorted by name, and size the window to fit.
-- With nothing running it shows a placeholder row. Refresh doesn't change whether
-- the window is showing; only SetOpen does.
function CorksCombatTimers.Refresh()
	if not DoesWindowNameExist("CorksCombatTimers") then
		return
	end

	local active = {}
	for _, timer in ipairs(CorksCombatTimers.Timers) do
		if CorksCombatTimers.IsActive(timer) then
			table.insert(active, timer)
		end
	end
	table.sort(active, CorksTimers.CompareTitles)
	while #active > CorksCombatTimers.MAX_ROWS do
		table.remove(active)
	end
	local rowCount = math.max(#active, 1)

	-- Resize before drawing, as in CorksTimers.Refresh.
	if rowCount ~= CorksCombatTimers.VisibleRows then
		CorksCombatTimers.VisibleRows = rowCount
		local height = math.max(58 + rowCount * CorksTimers.ROW_HEIGHT, CorksTimers.MIN_HEIGHT)
		WindowSetDimensions("CorksCombatTimers", CorksTimers.WINDOW_WIDTH, height)
	end

	if #active == 0 then
		CorksTimers.DrawPlaceholder("CorksCombatTimersRow1")
	end
	for i, timer in ipairs(active) do
		CorksCombatTimers.DrawRow("CorksCombatTimersRow" .. i, timer)
	end
	for i = rowCount + 1, CorksCombatTimers.MAX_ROWS do
		WindowSetShowing("CorksCombatTimersRow" .. i, false)
	end
end

function CorksCombatTimers.DrawRow(rowName, timer)
	local bar = rowName .. "Bar"
	local label = rowName .. "Time"

	WindowSetShowing(rowName, true)
	WindowSetShowing(bar, true)
	WindowSetShowing(label, true)
	CorksTimers.SetRowName(rowName, timer.title, timer.color or CorksTimers.DEFAULT_COLOR)
	StatusBarSetMaximumValue(bar, timer.barMax)

	local barColor
	if timer.phase == "ready" then
		barColor = CorksCombatTimers.READY_BAR
		StatusBarSetCurrentValue(bar, timer.barMax)
		LabelSetText(label, L"Ready")
	else
		if timer.phase == "active" then
			barColor = CorksCombatTimers.ACTIVE_BAR
		else
			barColor = CorksCombatTimers.COOLDOWN_BAR
		end
		local remaining = math.max(timer.remaining, 0)
		StatusBarSetCurrentValue(bar, remaining)
		LabelSetText(label, CorksTimers.FormatTime(remaining))
	end
	WindowSetTintColor(bar, barColor.r, barColor.g, barColor.b)
end
