----------------------------------------------------------------
-- Global Variables
----------------------------------------------------------------

CorksDurabilityGump = {}

CorksDurabilityGump.DURABILITY_TID = 1060639
CorksDurabilityGump.REFRESH_INTERVAL = 10
CorksDurabilityGump.RefreshTimer = 0
CorksDurabilityGump.RowCount = 0
CorksDurabilityGump.CurrentHeight = 0
CorksDurabilityGump.MAX_ROWS = 19  -- Max equippable slots

-- The window background image can't be drawn shorter than 90px and starts 28px
-- down, so a shorter window lets it spill past the frame at the bottom.
CorksDurabilityGump.MIN_HEIGHT = 120

-- Width and starting height, as in the XML
CorksDurabilityGump.WIDTH = 400
CorksDurabilityGump.XML_HEIGHT = 400

-- Classic UO gump background (base gump art ID), or nil for the standard EC look.
-- Redrawn whenever the window changes height.
CorksDurabilityGump.ClassicBackground = 2620
-- How far below the gump's top edge the title sits (clears the classic border)
CorksDurabilityGump.TitleOffsetY = 8
-- Gump art loaded for the classic background, released on shutdown
CorksDurabilityGump.GumpArt = {}

-- Repair popup: shown once when an equipped item drops to AlertPercent or lower,
-- and again only after that item has been repaired above it and worn down again.
-- Checked from Interface's update loop, so it works while the window is closed.
-- The player changes these in the Gear Watcher Setup window (CorksGearWatcherSetup).
CorksDurabilityGump.ALERT_DEFAULT = 25
CorksDurabilityGump.ALERT_MIN = 5
CorksDurabilityGump.ALERT_MAX = 95
CorksDurabilityGump.ALERT_STEP = 5
CorksDurabilityGump.ALERT_CHECK_SECONDS = 10
CorksDurabilityGump.AlertTick = 0
CorksDurabilityGump.AlertLoaded = false
CorksDurabilityGump.AlertOn = true
CorksDurabilityGump.AlertPercent = CorksDurabilityGump.ALERT_DEFAULT
-- Items already warned about, by object id
CorksDurabilityGump.Alerted = {}

CorksDurabilityGump.SlotNames = {
	[1]  = "Head",
	[2]  = "Neck",
	[3]  = "Arms",
	[4]  = "Right Hand",
	[5]  = "Ring",
	[6]  = "Legs",
	[7]  = "Ears",
	[8]  = "Chest",
	[9]  = "Bracelet",
	[10] = "Left Hand",
	[11] = "Gloves",
	[12] = "Talisman",
	[13] = "Feet",
	[14] = "Shirt",
	[15] = "Waist",
	[16] = "Robe",
	[17] = "Gorget",
	[18] = "Cape",
	[19] = "Pants",
}

----------------------------------------------------------------
-- Functions
----------------------------------------------------------------

function CorksDurabilityGump.Initialize()
	WindowSetScale("CorksDurabilityGump", SystemData.Settings.Interface.customUiScale * 0.80)
	WindowUtils.LoadScale("CorksDurabilityGump")
	WindowUtils.SetWindowTitle("CorksDurabilityGump", L"Corks Gear Watcher")

	LabelSetText("CorksDurabilityGumpHeaderItem", L"Item")
	LabelSetText("CorksDurabilityGumpHeaderDur", L"Durability")
	ButtonSetText("CorksDurabilityGumpSetupButton", L"Setup")

	WindowRegisterEventHandler("Root", WindowData.Paperdoll.Event, "CorksDurabilityGump.OnPaperdollEvent")

	-- Rows are defined statically in XML, so just hide them all until Update populates them.
	CorksDurabilityGump.CreateRows()

	WindowUtils.RestoreWindowPosition("CorksDurabilityGump")

	-- The window starts at its XML size; Update resizes it (and redraws the art)
	CorksDurabilityGump.CurrentHeight = 0
	CorksDurabilityGump.ApplyClassicLook(CorksDurabilityGump.XML_HEIGHT)
	CorksDurabilityGump.Update()
end

function CorksDurabilityGump.Shutdown()
	WindowUtils.SaveWindowPosition("CorksDurabilityGump")
	CorksGumpArt.ReleaseAll(CorksDurabilityGump.GumpArt)
end

-- Draws the classic background at the window's current height (protected, so a
-- problem with the art can never stop the durability list updating).
function CorksDurabilityGump.ApplyClassicLook(height)
	if not CorksDurabilityGump.ClassicBackground then
		return
	end
	local ok, err = pcall(function()
		CorksGumpArt.ApplyClassic("CorksDurabilityGump", CorksDurabilityGump.ClassicBackground,
			CorksDurabilityGump.WIDTH, height, CorksDurabilityGump.GumpArt)
		CorksGumpArt.FinishClassic("CorksDurabilityGump", CorksDurabilityGump.TitleOffsetY)
	end)
	if not ok then
		pcall(WindowUtils.ChatPrint, StringToWString("Gear Watcher background: " .. tostring(err)), SystemData.ChatLogFilters.SYSTEM)
	end
end

function CorksDurabilityGump.CreateRows()
	local scrollChild = "CorksDurabilityGumpListScrollChild"
	for i = 1, CorksDurabilityGump.MAX_ROWS do
		WindowSetShowing(scrollChild .. "Row" .. i, false)
	end
end

function CorksDurabilityGump.OnPaperdollEvent()
	if WindowData.UpdateInstanceId == WindowData.PlayerStatus.PlayerId then
		CorksDurabilityGump.Update()
	end
end

function CorksDurabilityGump.OnUpdate(timePassed)
	CorksDurabilityGump.RefreshTimer = CorksDurabilityGump.RefreshTimer + timePassed
	if CorksDurabilityGump.RefreshTimer >= CorksDurabilityGump.REFRESH_INTERVAL then
		CorksDurabilityGump.RefreshTimer = 0
		CorksDurabilityGump.Update()
	end
end

-- The window only opens when the user turns it on with the Durability Gump action.
-- Whether it's open is saved, so it opens again at login if it was open when the
-- client closed (Interface.lua reads the setting when it creates the window).

-- Right-click closes the window until the action opens it again.
function CorksDurabilityGump.OnClose()
	CorksDurabilityGump.SetOpen(false)
end

-- Open or close the window, creating it again if it was destroyed.
function CorksDurabilityGump.Toggle()
	local open = DoesWindowNameExist("CorksDurabilityGump") and WindowGetShowing("CorksDurabilityGump")
	CorksDurabilityGump.SetOpen(not open)
end

function CorksDurabilityGump.SetOpen(open)
	Interface.SaveBoolean("CorksDurabilityGumpOpen", open)
	if not DoesWindowNameExist("CorksDurabilityGump") then
		if open then
			CreateWindow("CorksDurabilityGump", true)
		end
		return
	end
	WindowSetShowing("CorksDurabilityGump", open)
	if open then
		CorksDurabilityGump.Update()
	end
end

function CorksDurabilityGump.Update()
	local windowName = "CorksDurabilityGump"
	local scrollChild = windowName .. "ListScrollChild"

	if not DoesWindowNameExist(windowName) then
		return
	end

	local playerId = WindowData.PlayerStatus.PlayerId
	if not WindowData.Paperdoll[playerId] then
		return
	end

	-- Hide all rows first
	for i = 1, CorksDurabilityGump.MAX_ROWS do
		WindowSetShowing(scrollChild .. "Row" .. i, false)
	end

	local rowCount = 0

	for index = 1, WindowData.Paperdoll[playerId].numSlots do
		local slotData = WindowData.Paperdoll[playerId][index]

		if slotData.slotId ~= 0 and CorksDurabilityGump.SlotNames[index] then
			local objectId = slotData.slotId
			local current, max, perc = CorksDurabilityGump.GetDurability(objectId)

			if current then
				rowCount = rowCount + 1

				local itemName = ItemProperties.GetObjectProperties(objectId, 1, "CorksDurabilityGump")
				if not itemName then
					itemName = L"Unknown"
				end

				local rowName = scrollChild .. "Row" .. rowCount
				WindowSetShowing(rowName, true)

				-- A label takes its color when its text is set, so set the color first.
				-- Row 1 may have been gray from the "no items" placeholder.
				LabelSetTextColor(rowName .. "ItemName", 255, 255, 255)
				LabelSetText(rowName .. "ItemName", itemName)

				if perc > 75 then
					LabelSetTextColor(rowName .. "Durability", 0, 255, 0)
				elseif perc > 50 then
					LabelSetTextColor(rowName .. "Durability", 255, 255, 0)
				elseif perc > 25 then
					LabelSetTextColor(rowName .. "Durability", 255, 165, 0)
				elseif perc > 10 then
					LabelSetTextColor(rowName .. "Durability", 255, 80, 0)
				else
					LabelSetTextColor(rowName .. "Durability", 255, 0, 0)
				end

				local durText = towstring(tostring(current) .. " / " .. tostring(max))
				LabelSetText(rowName .. "Durability", durText)
			end
		end
	end

	-- If no items with durability, show placeholder in row 1
	if rowCount == 0 then
		rowCount = 1
		local rowName = scrollChild .. "Row1"
		WindowSetShowing(rowName, true)
		LabelSetTextColor(rowName .. "ItemName", 180, 180, 180)
		LabelSetText(rowName .. "ItemName", L"No items with durability equipped.")
		LabelSetText(rowName .. "Durability", L"")
	end

	CorksDurabilityGump.RowCount = rowCount

	-- Resize the window and scroll child to fit the visible rows exactly.
	-- Rows are statically defined in XML so WindowSetDimensions does not reset
	-- their inherited scale. Only resize when row count actually changes.
	local targetHeight = math.max(rowCount * 22 + 80, CorksDurabilityGump.MIN_HEIGHT)
	if targetHeight ~= CorksDurabilityGump.CurrentHeight then
		CorksDurabilityGump.CurrentHeight = targetHeight
		WindowSetDimensions(windowName, CorksDurabilityGump.WIDTH, targetHeight)
		WindowSetDimensions(scrollChild, 360, rowCount * 22)
		CorksDurabilityGump.ApplyClassicLook(targetHeight)
	end
end

-- An item's durability as current, max and percent left (rounded down),
-- or nil when the item has no durability (or its properties haven't loaded yet).
function CorksDurabilityGump.GetDurability(objectId)
	local dur = ItemProperties.GetObjectPropertiesParamsForTid(objectId, CorksDurabilityGump.DURABILITY_TID, "CorksDurabilityGump")
	if not dur then
		return nil
	end
	local current = tonumber(dur[1])
	local max = tonumber(dur[2])
	if not current or not max then
		return nil
	end
	local perc = 0
	if max > 0 then
		perc = math.floor((current / max) * 100)
	end
	return current, max, perc
end

----------------------------------------------------------------
-- Repair popup
----------------------------------------------------------------

function CorksDurabilityGump.LoadAlertSettings()
	if CorksDurabilityGump.AlertLoaded then
		return
	end
	CorksDurabilityGump.AlertLoaded = true
	CorksDurabilityGump.AlertOn = Interface.LoadBoolean("CorksGearWatcherPopupOn", true)
	CorksDurabilityGump.AlertPercent = CorksDurabilityGump.ClampAlertPercent(
		Interface.LoadNumber("CorksGearWatcherAlertPercent", CorksDurabilityGump.ALERT_DEFAULT))
end

function CorksDurabilityGump.ClampAlertPercent(value)
	value = tonumber(value) or CorksDurabilityGump.ALERT_DEFAULT
	return math.max(CorksDurabilityGump.ALERT_MIN, math.min(CorksDurabilityGump.ALERT_MAX, value))
end

function CorksDurabilityGump.SetAlertOn(on)
	CorksDurabilityGump.LoadAlertSettings()
	CorksDurabilityGump.AlertOn = on
	Interface.SaveBoolean("CorksGearWatcherPopupOn", on)
	-- Check straight away rather than waiting for the next timed check
	CorksDurabilityGump.AlertTick = CorksDurabilityGump.ALERT_CHECK_SECONDS
end

function CorksDurabilityGump.SetAlertPercent(value)
	CorksDurabilityGump.LoadAlertSettings()
	CorksDurabilityGump.AlertPercent = CorksDurabilityGump.ClampAlertPercent(value)
	Interface.SaveNumber("CorksGearWatcherAlertPercent", CorksDurabilityGump.AlertPercent)
	CorksDurabilityGump.AlertTick = CorksDurabilityGump.ALERT_CHECK_SECONDS
end

-- Called every frame from Interface's update loop; looks at the equipped items
-- every ALERT_CHECK_SECONDS and shows the popup for any newly worn-down item.
function CorksDurabilityGump.CheckAlerts(timePassed)
	local D = CorksDurabilityGump
	D.AlertTick = D.AlertTick + (timePassed or 0)
	if D.AlertTick < D.ALERT_CHECK_SECONDS then
		return
	end
	D.AlertTick = 0

	D.LoadAlertSettings()
	if not D.AlertOn then
		-- Start fresh, so turning it back on warns about anything already worn down
		D.Alerted = {}
		return
	end

	local playerId = WindowData.PlayerStatus and WindowData.PlayerStatus.PlayerId
	if not playerId or playerId == 0 then
		return
	end
	-- The player's paperdoll data stays registered once asked for (as PaperdollWindow does)
	if not WindowData.Paperdoll[playerId] then
		RegisterWindowData(WindowData.Paperdoll.Type, playerId)
	end
	local paperdoll = WindowData.Paperdoll[playerId]
	if not paperdoll then
		return
	end

	local show = false
	for index = 1, paperdoll.numSlots do
		local slotData = paperdoll[index]
		if slotData and slotData.slotId ~= 0 and D.SlotNames[index] then
			local objectId = slotData.slotId
			local _, max, perc = D.GetDurability(objectId)
			if max and max > 0 then
				if perc <= D.AlertPercent then
					if not D.Alerted[objectId] then
						D.Alerted[objectId] = true
						show = true
					end
				else
					-- Repaired (or the level was lowered): warn again next time it wears down
					D.Alerted[objectId] = nil
				end
			end
		end
	end

	if show then
		D.ShowRepairPopup()
	end
end

-- Flashes the CST_Repair graphic (Source/CorksTextures.xml) mid-screen, the same
-- way CenterScreenText shows the stock popups like Low Life
function CorksDurabilityGump.ShowRepairPopup()
	local image = "CenterScreenTextImage"
	DynamicImageSetTexture(image, "CST_Repair", 0, 0)
	DynamicImageSetTextureDimensions(image, 400, 100)
	WindowSetDimensions(image, 400, 100)
	WindowStopAlphaAnimation(image)
	WindowSetAlpha(image, 0)
	WindowStartAlphaAnimation(image, Window.AnimationType.LOOP, 0.5, 1, 1, false, 0, 3)
end

function CorksDurabilityGump.OnSetupButton()
	CorksGearWatcherSetup.Toggle()
end
