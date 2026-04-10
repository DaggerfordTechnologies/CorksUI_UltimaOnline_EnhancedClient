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
	CorksDurabilityGump.Update()
end

function CorksDurabilityGump.Shutdown()
	WindowUtils.SaveWindowPosition("CorksDurabilityGump")
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

function CorksDurabilityGump.OnClose()
	WindowSetShowing("CorksDurabilityGump", false)
end

function CorksDurabilityGump.Toggle()
	if DoesWindowNameExist("CorksDurabilityGump") then
		local showing = WindowGetShowing("CorksDurabilityGump")
		WindowSetShowing("CorksDurabilityGump", not showing)
		if not showing then
			CorksDurabilityGump.Update()
		end
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

				LabelSetText(rowName .. "ItemName", itemName)

				local durText = towstring(tostring(current) .. " / " .. tostring(max))
				LabelSetText(rowName .. "Durability", durText)

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
			end
		end
	end

	-- If no items with durability, show placeholder in row 1
	if rowCount == 0 then
		rowCount = 1
		local rowName = scrollChild .. "Row1"
		WindowSetShowing(rowName, true)
		LabelSetText(rowName .. "ItemName", L"No items with durability equipped.")
		LabelSetTextColor(rowName .. "ItemName", 180, 180, 180)
		LabelSetText(rowName .. "Durability", L"")
	end

	CorksDurabilityGump.RowCount = rowCount

	-- Resize the window and scroll child to fit the visible rows exactly.
	-- Rows are statically defined in XML so WindowSetDimensions does not reset
	-- their inherited scale. Only resize when row count actually changes.
	local targetHeight = rowCount * 22 + 80
	if targetHeight ~= CorksDurabilityGump.CurrentHeight then
		CorksDurabilityGump.CurrentHeight = targetHeight
		WindowSetDimensions(windowName, 400, targetHeight)
		WindowSetDimensions(scrollChild, 360, rowCount * 22)
	end
end
