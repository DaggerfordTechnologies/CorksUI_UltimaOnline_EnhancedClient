----------------------------------------------------------------
-- Global Variables
----------------------------------------------------------------

CorksTimers = {}

-- Heal potions of every strength share this object type; the name tells them apart.
CorksTimers.HEAL_POTION_TYPE = 3852
CorksTimers.GREATER_HEAL_NAME = "greater heal"
CorksTimers.GREATER_HEAL_DURATION = 10

-- System messages (lowercase) that mean the potion was not drunk.
CorksTimers.REJECT_TEXTS = {
	"you are already at full health",
	"you must wait a few seconds before using another healing potion",
}

-- How long after a double-click a rejection message can still cancel the timer.
CorksTimers.REJECT_WINDOW = 2

-- How long "Ready" stays on screen before the window hides.
CorksTimers.READY_DISPLAY_TIME = 3

CorksTimers.Remaining = 0
CorksTimers.ReadyTimer = 0
CorksTimers.PendingTimer = 0
CorksTimers.Previous = nil

----------------------------------------------------------------
-- Functions
----------------------------------------------------------------

function CorksTimers.Initialize()
	WindowSetScale("CorksTimers", SystemData.Settings.Interface.customUiScale * 0.80)
	WindowUtils.LoadScale("CorksTimers")
	WindowUtils.SetWindowTitle("CorksTimers", L"Greater Heal")

	StatusBarSetMaximumValue("CorksTimersBar", CorksTimers.GREATER_HEAL_DURATION)
	StatusBarSetCurrentValue("CorksTimersBar", 0)

	WindowUtils.RestoreWindowPosition("CorksTimers")
	WindowSetShowing("CorksTimers", false)

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

function CorksTimers.OnClose()
	CorksTimers.Remaining = 0
	CorksTimers.ReadyTimer = 0
	CorksTimers.PendingTimer = 0
	WindowSetShowing("CorksTimers", false)
end

function CorksTimers.UseItem(objectId, ...)
	local ok, err = pcall(CorksTimers.OnItemUsed, objectId)
	Interface.ErrorTracker(ok, err)
	return CorksTimers.OriginalUseItem(objectId, ...)
end

function CorksTimers.OnItemUsed(objectId)
	if CorksTimers.IsGreaterHealPotion(objectId) then
		-- Remember the current state so a rejection message can put it back.
		CorksTimers.Previous = { remaining = CorksTimers.Remaining, ready = CorksTimers.ReadyTimer }
		CorksTimers.PendingTimer = CorksTimers.REJECT_WINDOW
		CorksTimers.Start()
	end
end

function CorksTimers.IsGreaterHealPotion(objectId)
	if not objectId or objectId == 0 then
		return false
	end

	RegisterWindowData(WindowData.ObjectInfo.Type, objectId)
	local itemData = WindowData.ObjectInfo[objectId]
	local objectType = itemData and itemData.objectType
	UnregisterWindowData(WindowData.ObjectInfo.Type, objectId)

	if objectType ~= CorksTimers.HEAL_POTION_TYPE then
		return false
	end

	local name = ItemProperties.GetObjectProperties(objectId, 1, "CorksTimers")
	if not name then
		return false
	end
	name = string.lower(WStringToString(name))
	return string.find(name, CorksTimers.GREATER_HEAL_NAME, 1, true) ~= nil
end

-- Called for every journal line from Interface.NewChatText.
-- Only system messages count, so a player saying the phrase won't cancel the timer.
function CorksTimers.OnChatText()
	if CorksTimers.PendingTimer <= 0 then
		return
	end
	if not SystemData.Text or SystemData.TextChannelID ~= SystemData.ChatLogFilters.SYSTEM then
		return
	end

	local text = string.lower(WStringToString(SystemData.Text))
	for _, reject in ipairs(CorksTimers.REJECT_TEXTS) do
		if string.find(text, reject, 1, true) then
			CorksTimers.Cancel()
			return
		end
	end
end

-- The potion was not drunk: put the timer back the way it was before the double-click.
function CorksTimers.Cancel()
	-- Time that passed between the double-click and the rejection message.
	local elapsed = CorksTimers.REJECT_WINDOW - CorksTimers.PendingTimer
	CorksTimers.PendingTimer = 0
	local previous = CorksTimers.Previous or { remaining = 0, ready = 0 }
	CorksTimers.Previous = nil

	CorksTimers.Remaining = math.max(previous.remaining - elapsed, 0)
	CorksTimers.ReadyTimer = math.max(previous.ready - elapsed, 0)
	if previous.remaining > 0 and CorksTimers.Remaining == 0 then
		CorksTimers.ReadyTimer = CorksTimers.READY_DISPLAY_TIME
	end

	if CorksTimers.Remaining > 0 then
		WindowSetTintColor("CorksTimersBar", 255, 60, 60)
		CorksTimers.Refresh()
	elseif CorksTimers.ReadyTimer > 0 then
		CorksTimers.Refresh()
	else
		WindowSetShowing("CorksTimers", false)
	end
end

function CorksTimers.Start()
	if not DoesWindowNameExist("CorksTimers") then
		return
	end

	CorksTimers.Remaining = CorksTimers.GREATER_HEAL_DURATION
	CorksTimers.ReadyTimer = 0

	WindowSetTintColor("CorksTimersBar", 255, 60, 60)
	StatusBarSetMaximumValue("CorksTimersBar", CorksTimers.GREATER_HEAL_DURATION)
	WindowSetShowing("CorksTimers", true)
	CorksTimers.Refresh()
end

-- Called every frame from Interface.Update.
function CorksTimers.OnUpdate(timePassed)
	if CorksTimers.PendingTimer > 0 then
		CorksTimers.PendingTimer = CorksTimers.PendingTimer - timePassed
		if CorksTimers.PendingTimer <= 0 then
			CorksTimers.PendingTimer = 0
			CorksTimers.Previous = nil
		end
	end

	if CorksTimers.Remaining > 0 then
		CorksTimers.Remaining = CorksTimers.Remaining - timePassed
		if CorksTimers.Remaining <= 0 then
			CorksTimers.Remaining = 0
			CorksTimers.ReadyTimer = CorksTimers.READY_DISPLAY_TIME
		end
		CorksTimers.Refresh()
	elseif CorksTimers.ReadyTimer > 0 then
		CorksTimers.ReadyTimer = CorksTimers.ReadyTimer - timePassed
		if CorksTimers.ReadyTimer <= 0 then
			CorksTimers.ReadyTimer = 0
			WindowSetShowing("CorksTimers", false)
		end
	end
end

function CorksTimers.Refresh()
	if CorksTimers.Remaining > 0 then
		StatusBarSetCurrentValue("CorksTimersBar", CorksTimers.Remaining)
		LabelSetText("CorksTimersTime", towstring(string.format("%.1f sec", CorksTimers.Remaining)))
	else
		WindowSetTintColor("CorksTimersBar", 0, 200, 0)
		StatusBarSetCurrentValue("CorksTimersBar", CorksTimers.GREATER_HEAL_DURATION)
		LabelSetText("CorksTimersTime", L"Ready")
	end
end
