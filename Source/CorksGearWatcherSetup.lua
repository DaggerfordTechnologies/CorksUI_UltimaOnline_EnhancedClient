----------------------------------------------------------------
-- Gear Watcher Setup: settings for the Gear Watcher's repair popup.
-- Opened from the Setup button on the Gear Watcher. The settings themselves
-- live in CorksDurabilityGump (AlertOn, AlertPercent), which does the checking.
----------------------------------------------------------------

CorksGearWatcherSetup = {}

CorksGearWatcherSetup.WINDOW = "CorksGearWatcherSetup"
-- Size, as in the XML
CorksGearWatcherSetup.WIDTH = 320
CorksGearWatcherSetup.HEIGHT = 190

-- Same classic background as the Gear Watcher, or nil for the standard EC look
CorksGearWatcherSetup.ClassicBackground = 2620
CorksGearWatcherSetup.TitleOffsetY = 8
-- Gump art loaded for the classic background, released on shutdown
CorksGearWatcherSetup.GumpArt = {}

-- A check box's pressed flag only changes after its click handler, so it's read
-- on the next update
CorksGearWatcherSetup.Dirty = false

----------------------------------------------------------------
-- Functions
----------------------------------------------------------------

function CorksGearWatcherSetup.Initialize()
	local W = CorksGearWatcherSetup.WINDOW
	WindowUtils.RestoreWindowPosition(W)
	WindowUtils.LoadScale(W)
	WindowUtils.SetWindowTitle(W, L"Gear Watcher Setup")

	ButtonSetCheckButtonFlag(W .. "PopupButton", true)
	LabelSetText(W .. "PopupLabel", L"Show the Repair popup")
	LabelSetText(W .. "LevelHeader", L"Show it when an item is at or below:")
	LabelSetText(W .. "Note", L"Shows once for each item, and again after that item is repaired and wears down.")

	CorksGearWatcherSetup.ApplyClassicLook()
	CorksGearWatcherSetup.Refresh()
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

-- Shows the current settings
function CorksGearWatcherSetup.Refresh()
	local W = CorksGearWatcherSetup.WINDOW
	if not DoesWindowNameExist(W) then
		return
	end
	CorksDurabilityGump.LoadAlertSettings()
	ButtonSetPressedFlag(W .. "PopupButton", CorksDurabilityGump.AlertOn)
	LabelSetText(W .. "Level", StringToWString(tostring(CorksDurabilityGump.AlertPercent) .. "%"))
end

-- Moves the alert level one step up (1) or down (-1)
function CorksGearWatcherSetup.StepLevel(direction)
	CorksDurabilityGump.LoadAlertSettings()
	CorksDurabilityGump.SetAlertPercent(CorksDurabilityGump.AlertPercent + direction * CorksDurabilityGump.ALERT_STEP)
	CorksGearWatcherSetup.Refresh()
end

----------------------------------------------------------------
-- Event Handlers
----------------------------------------------------------------

function CorksGearWatcherSetup.OnUpdate(timePassed)
	if not CorksGearWatcherSetup.Dirty then
		return
	end
	CorksGearWatcherSetup.Dirty = false
	local on = ButtonGetPressedFlag(CorksGearWatcherSetup.WINDOW .. "PopupButton")
	if on ~= CorksDurabilityGump.AlertOn then
		CorksDurabilityGump.SetAlertOn(on)
	end
end

function CorksGearWatcherSetup.OnPopupButton()
	CorksGearWatcherSetup.Dirty = true
end

-- Clicking the text toggles the check box too
function CorksGearWatcherSetup.OnPopupLabel()
	local button = CorksGearWatcherSetup.WINDOW .. "PopupButton"
	ButtonSetPressedFlag(button, not ButtonGetPressedFlag(button))
	CorksGearWatcherSetup.Dirty = true
end

function CorksGearWatcherSetup.OnMinus()
	CorksGearWatcherSetup.StepLevel(-1)
end

function CorksGearWatcherSetup.OnPlus()
	CorksGearWatcherSetup.StepLevel(1)
end

-- Right-click closes the window
function CorksGearWatcherSetup.OnClose()
	CorksGearWatcherSetup.SetOpen(false)
end

-- Open or close the window; it's only created the first time it's opened
function CorksGearWatcherSetup.Toggle()
	local W = CorksGearWatcherSetup.WINDOW
	local open = DoesWindowNameExist(W) and WindowGetShowing(W)
	CorksGearWatcherSetup.SetOpen(not open)
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
		-- Catch a check box click made just before closing
		CorksGearWatcherSetup.OnUpdate(0)
	end
	WindowSetShowing(W, open)
	if open then
		CorksGearWatcherSetup.Refresh()
	end
end
