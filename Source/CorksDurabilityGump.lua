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
			local dur = ItemProperties.GetObjectPropertiesParamsForTid(objectId, CorksDurabilityGump.DURABILITY_TID, "CorksDurabilityGump")

			if dur then
				rowCount = rowCount + 1
				local current = tonumber(dur[1])
				local max = tonumber(dur[2])

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

				local perc = 0
				if max > 0 then
					perc = math.floor((current / max) * 100)
				end

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
