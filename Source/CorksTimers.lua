----------------------------------------------------------------
-- Global Variables
----------------------------------------------------------------

CorksTimers = {}

-- Each entry becomes a row in the Timers window while it runs. A timer starts when
-- an item whose name contains itemName (lowercase) is double-clicked, and
-- objectType matches when it is set.
--
-- Two ways to tell whether the item was really used:
--   rejectTexts: the timer starts right away; if a system message containing one of
--     these (lowercase) arrives within REJECT_WINDOW seconds, the timer goes back
--     to how it was.
--   startOnUse: the timer waits until the double-clicked stack goes down by one
--     (or disappears, if it was the last one), checking for up to useWindow seconds
--     (USE_WINDOW when not set).
--
-- The name in the row is drawn in the used potion's hue. Unhued potions (hue 0) get
-- their color from the item art, so color is used for those. Set ignoreHue to
-- always use color.
CorksTimers.Timers = {
	{
		title       = L"Greater Heal",
		itemName    = "greater heal",
		objectType  = 3852,  -- heal potions of every strength share this type
		duration    = 10,
		color       = { r = 255, g = 230, b = 0 },  -- yellow
		ignoreHue   = true,
		-- Full health or still on cooldown means no potion is drunk, so no timer.
		startOnUse  = true,
		useWindow   = 3,  -- drinking is instant, no target to pick
	},
	{
		title       = L"Greater Conflagration",
		itemName    = "greater conflagration",
		duration    = 30,
		color       = { r = 255, g = 140, b = 0 },  -- orange
		ignoreHue   = true,
		-- Thrown potions: a failed throw or a cancelled target doesn't use one up.
		startOnUse  = true,
	},
	{
		title       = L"Supernova",
		itemName    = "supernova",
		duration    = 120,
		color       = { r = 170, g = 80, b = 255 },  -- purple
		ignoreHue   = true,
		startOnUse  = true,
		useWindow   = 3,  -- drunk, not thrown
	},
	{
		title       = L"Barrab Hemolymph",
		itemName    = "barrab hemolymph",
		duration    = 1200,  -- 20 minutes
		color       = { r = 60, g = 220, b = 60 },  -- green
		ignoreHue   = true,
		startOnUse  = true,
		useWindow   = 3,
	},
}

-- Rows defined in CorksTimers.xml. Timers beyond this many at once aren't shown.
CorksTimers.MAX_ROWS = 8
CorksTimers.ROW_HEIGHT = 38
CorksTimers.WINDOW_WIDTH = 240

-- The window background image can't be drawn shorter than 90px and starts 28px
-- down, so a shorter window lets it spill past the frame at the bottom.
CorksTimers.MIN_HEIGHT = 120

-- How long after a double-click a rejection message can still cancel the timer.
CorksTimers.REJECT_WINDOW = 2

-- How long after a double-click a startOnUse stack is watched for a potion being used
-- (long enough to pick a target).
CorksTimers.USE_WINDOW = 15

-- How long "Ready" stays on screen before a row is removed.
CorksTimers.READY_DISPLAY_TIME = 3

-- Row name color when neither the potion's hue nor the entry gives one.
CorksTimers.DEFAULT_COLOR = { r = 255, g = 200, b = 50 }

CorksTimers.VisibleRows = 0

-- Name text and color last drawn on each row, so a row is only relabelled when its
-- timer (or that timer's color) changes.
CorksTimers.RowLabels = {}

----------------------------------------------------------------
-- Functions
----------------------------------------------------------------

function CorksTimers.Initialize()
	for _, timer in ipairs(CorksTimers.Timers) do
		CorksTimers.Reset(timer)
	end

	for i = 1, CorksTimers.MAX_ROWS do
		WindowSetShowing("CorksTimersRow" .. i, false)
	end

	WindowSetScale("CorksTimers", SystemData.Settings.Interface.customUiScale * 0.80)
	WindowUtils.LoadScale("CorksTimers")
	WindowUtils.SetWindowTitle("CorksTimers", L"Corks' Timers")

	WindowUtils.RestoreWindowPosition("CorksTimers")
	CorksTimers.Refresh()

	-- Every double-click in the UI (backpack, containers, paperdoll) goes through
	-- UserActionUseItem, so wrap it once to see which object was used.
	if not CorksTimers.OriginalUseItem then
		CorksTimers.OriginalUseItem = UserActionUseItem
		UserActionUseItem = CorksTimers.UseItem
	end
end

function CorksTimers.Shutdown()
	WindowUtils.SaveWindowPosition("CorksTimers")
end

function CorksTimers.Reset(timer)
	timer.remaining = 0
	timer.ready = 0
	timer.pending = 0
	timer.previous = nil
	CorksTimers.StopWatching(timer)
end

function CorksTimers.IsActive(timer)
	return timer.remaining ~= nil and (timer.remaining > 0 or timer.ready > 0)
end

function CorksTimers.UseItem(objectId, ...)
	local ok, err = pcall(CorksTimers.OnItemUsed, objectId)
	Interface.ErrorTracker(ok, err)
	return CorksTimers.OriginalUseItem(objectId, ...)
end

function CorksTimers.OnItemUsed(objectId)
	if not objectId or objectId == 0 then
		return
	end

	for _, timer in ipairs(CorksTimers.Timers) do
		if CorksTimers.ItemMatches(timer, objectId) then
			if timer.startOnUse then
				CorksTimers.StartWatching(timer, objectId)
				return
			end

			-- Remember the current state so a rejection message can put it back.
			timer.previous = { remaining = timer.remaining, ready = timer.ready }
			timer.pending = CorksTimers.REJECT_WINDOW
			timer.remaining = timer.duration
			timer.ready = 0
			CorksTimers.Refresh()
			return
		end
	end
end

function CorksTimers.ItemMatches(timer, objectId)
	if timer.objectType then
		RegisterWindowData(WindowData.ObjectInfo.Type, objectId)
		local itemData = WindowData.ObjectInfo[objectId]
		local objectType = itemData and itemData.objectType
		UnregisterWindowData(WindowData.ObjectInfo.Type, objectId)

		if objectType ~= timer.objectType then
			return false
		end
	end

	local name = ItemProperties.GetObjectProperties(objectId, 1, "CorksTimers")
	if not name then
		return false
	end
	name = string.lower(WStringToString(name))
	return string.find(name, timer.itemName, 1, true) ~= nil
end

-- Remember the double-clicked stack and its size; CheckWatch starts the timer once
-- it shrinks. The object stays registered so its quantity keeps updating.
function CorksTimers.StartWatching(timer, objectId)
	CorksTimers.StopWatching(timer)

	RegisterWindowData(WindowData.ObjectInfo.Type, objectId)
	local itemData = WindowData.ObjectInfo[objectId]
	if not itemData or not itemData.quantity then
		UnregisterWindowData(WindowData.ObjectInfo.Type, objectId)
		return
	end

	timer.watch = {
		objectId = objectId,
		quantity = itemData.quantity,
		hueId = itemData.hueId,
		timeLeft = timer.useWindow or CorksTimers.USE_WINDOW,
	}
end

function CorksTimers.StopWatching(timer)
	if timer.watch then
		UnregisterWindowData(WindowData.ObjectInfo.Type, timer.watch.objectId)
		timer.watch = nil
	end
end

function CorksTimers.CheckWatch(timer, timePassed)
	local watch = timer.watch
	local used = false

	if not IsValidObject(watch.objectId) then
		-- The last potion in the stack was used.
		used = true
	else
		local itemData = WindowData.ObjectInfo[watch.objectId]
		if itemData and itemData.quantity and itemData.quantity < watch.quantity then
			used = true
		end
	end

	if used then
		CorksTimers.StopWatching(timer)
		if not timer.ignoreHue then
			timer.textColor = CorksTimers.GetHueColor(watch.hueId)
		end
		timer.remaining = timer.duration
		timer.ready = 0
		CorksTimers.Refresh()
		return
	end

	watch.timeLeft = watch.timeLeft - timePassed
	if watch.timeLeft <= 0 then
		CorksTimers.StopWatching(timer)
	end
end

-- Called for every journal line from Interface.NewChatText.
-- Only system messages count, so a player saying a phrase won't cancel a timer.
function CorksTimers.OnChatText()
	if not SystemData.Text or SystemData.TextChannelID ~= SystemData.ChatLogFilters.SYSTEM then
		return
	end

	local text
	for _, timer in ipairs(CorksTimers.Timers) do
		if timer.pending and timer.pending > 0 and timer.rejectTexts then
			text = text or string.lower(WStringToString(SystemData.Text))
			for _, reject in ipairs(timer.rejectTexts) do
				if string.find(text, reject, 1, true) then
					CorksTimers.Cancel(timer)
					break
				end
			end
		end
	end
end

-- The item wasn't used: put the timer back the way it was before the double-click.
function CorksTimers.Cancel(timer)
	-- Time that passed between the double-click and the rejection message.
	local elapsed = CorksTimers.REJECT_WINDOW - timer.pending
	timer.pending = 0
	local previous = timer.previous or { remaining = 0, ready = 0 }
	timer.previous = nil

	timer.remaining = math.max(previous.remaining - elapsed, 0)
	timer.ready = math.max(previous.ready - elapsed, 0)
	if previous.remaining > 0 and timer.remaining == 0 then
		timer.ready = CorksTimers.READY_DISPLAY_TIME
	end

	CorksTimers.Refresh()
end

-- Called every frame from Interface.Update.
function CorksTimers.OnUpdate(timePassed)
	local changed = false
	for _, timer in ipairs(CorksTimers.Timers) do
		if timer.remaining and CorksTimers.UpdateTimer(timer, timePassed) then
			changed = true
		end
	end
	if changed then
		CorksTimers.Refresh()
	end
end

-- Returns true when the timer was running this frame, so the window needs redrawing.
function CorksTimers.UpdateTimer(timer, timePassed)
	if timer.watch then
		CorksTimers.CheckWatch(timer, timePassed)
	end

	if timer.pending > 0 then
		timer.pending = timer.pending - timePassed
		if timer.pending <= 0 then
			timer.pending = 0
			timer.previous = nil
		end
	end

	if timer.remaining > 0 then
		timer.remaining = timer.remaining - timePassed
		if timer.remaining <= 0 then
			timer.remaining = 0
			timer.ready = CorksTimers.READY_DISPLAY_TIME
		end
		return true
	elseif timer.ready > 0 then
		timer.ready = timer.ready - timePassed
		if timer.ready <= 0 then
			timer.ready = 0
		end
		return true
	end
	return false
end

-- Fill the rows with the running timers, sorted by name, and size the window to fit.
-- The window stays open; with nothing running it shows a placeholder row.
function CorksTimers.Refresh()
	if not DoesWindowNameExist("CorksTimers") then
		return
	end

	local active = {}
	for _, timer in ipairs(CorksTimers.Timers) do
		if CorksTimers.IsActive(timer) then
			table.insert(active, timer)
		end
	end
	table.sort(active, CorksTimers.CompareTitles)
	while #active > CorksTimers.MAX_ROWS do
		table.remove(active)
	end
	local rowCount = math.max(#active, 1)

	-- Resize before drawing: resizing makes the engine redo the window's layout,
	-- which can undo colors set on the rows beforehand. Only the root window is
	-- resized; resizing rows would reset their scale.
	if rowCount ~= CorksTimers.VisibleRows then
		CorksTimers.VisibleRows = rowCount
		local height = math.max(58 + rowCount * CorksTimers.ROW_HEIGHT, CorksTimers.MIN_HEIGHT)
		WindowSetDimensions("CorksTimers", CorksTimers.WINDOW_WIDTH, height)
	end

	if #active == 0 then
		CorksTimers.DrawPlaceholder("CorksTimersRow1")
	end
	for i, timer in ipairs(active) do
		CorksTimers.DrawRow("CorksTimersRow" .. i, timer)
	end
	for i = rowCount + 1, CorksTimers.MAX_ROWS do
		WindowSetShowing("CorksTimersRow" .. i, false)
	end

	WindowSetShowing("CorksTimers", true)
end

function CorksTimers.CompareTitles(a, b)
	if not a.sortKey then
		a.sortKey = string.lower(WStringToString(a.title))
	end
	if not b.sortKey then
		b.sortKey = string.lower(WStringToString(b.title))
	end
	return a.sortKey < b.sortKey
end

function CorksTimers.DrawRow(rowName, timer)
	local bar = rowName .. "Bar"
	local label = rowName .. "Time"

	WindowSetShowing(rowName, true)
	WindowSetShowing(bar, true)
	WindowSetShowing(label, true)
	CorksTimers.SetRowName(rowName, timer.title, timer.textColor or timer.color or CorksTimers.DEFAULT_COLOR)
	StatusBarSetMaximumValue(bar, timer.duration)

	if timer.remaining > 0 then
		WindowSetTintColor(bar, 255, 60, 60)
		StatusBarSetCurrentValue(bar, timer.remaining)
		LabelSetText(label, CorksTimers.FormatTime(timer.remaining))
	else
		WindowSetTintColor(bar, 0, 200, 0)
		StatusBarSetCurrentValue(bar, timer.duration)
		LabelSetText(label, L"Ready")
	end
end

function CorksTimers.DrawPlaceholder(rowName)
	WindowSetShowing(rowName, true)
	WindowSetShowing(rowName .. "Bar", false)
	WindowSetShowing(rowName .. "Time", false)
	CorksTimers.SetRowName(rowName, L"No active timers", { r = 180, g = 180, b = 180 })
end

-- A label takes its color when its text is set, and setting the same text again
-- doesn't redraw it. So set the color first, then clear and reset the text.
function CorksTimers.SetRowName(rowName, text, color)
	local last = CorksTimers.RowLabels[rowName]
	if last and last.text == text and last.r == color.r and last.g == color.g and last.b == color.b then
		return
	end
	CorksTimers.RowLabels[rowName] = { text = text, r = color.r, g = color.g, b = color.b }

	local label = rowName .. "Name"
	LabelSetTextColor(label, color.r, color.g, color.b)
	LabelSetText(label, L"")
	LabelSetText(label, text)
end

-- "1:59" for a minute or more, "9.3 sec" below that.
function CorksTimers.FormatTime(seconds)
	if seconds >= 60 then
		local whole = math.ceil(seconds)
		return towstring(string.format("%d:%02d", math.floor(whole / 60), whole % 60))
	end
	return towstring(string.format("%.1f sec", seconds))
end

-- RGB for a hue, or nil for an unhued item.
function CorksTimers.GetHueColor(hueId)
	if not hueId or hueId == 0 then
		return nil
	end
	local r, g, b = HueRGBAValue(hueId)
	return { r = r, g = g, b = b }
end
