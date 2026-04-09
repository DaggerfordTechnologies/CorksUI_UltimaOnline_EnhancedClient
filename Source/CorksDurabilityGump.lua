----------------------------------------------------------------
-- Global Variables
----------------------------------------------------------------

CorksDurabilityGump = {}

CorksDurabilityGump.DURABILITY_TID = 1060639
CorksDurabilityGump.REFRESH_INTERVAL = 10
CorksDurabilityGump.RefreshTimer = 0
CorksDurabilityGump.RowCount = 0

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

-- Logical width of the scroll child as defined in the XML template.
-- Never derived at runtime to avoid feedback with window scale.
CorksDurabilityGump.SCROLL_CHILD_WIDTH = 360

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

	WindowUtils.RestoreWindowPosition("CorksDurabilityGump")
	CorksDurabilityGump.Update()
end

function CorksDurabilityGump.Shutdown()
	WindowUtils.SaveWindowPosition("CorksDurabilityGump")
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

	-- Destroy old rows
	for i = 1, CorksDurabilityGump.RowCount do
		local oldRow = scrollChild .. "Row" .. i
		if DoesWindowNameExist(oldRow) then
			DestroyWindow(oldRow)
		end
	end
	CorksDurabilityGump.RowCount = 0

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
				CreateWindowFromTemplate(rowName, "CorksDurabilityGumpRowTemplate", scrollChild)

				if rowCount == 1 then
					WindowAddAnchor(rowName, "topleft", scrollChild, "topleft", 0, 0)
				else
					WindowAddAnchor(rowName, "bottomleft", scrollChild .. "Row" .. (rowCount - 1), "topleft", 0, 0)
				end

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

	-- If no items with durability found, show a placeholder row
	if rowCount == 0 then
		rowCount = 1
		local rowName = scrollChild .. "Row1"
		CreateWindowFromTemplate(rowName, "CorksDurabilityGumpRowTemplate", scrollChild)
		WindowAddAnchor(rowName, "topleft", scrollChild, "topleft", 0, 0)
		LabelSetText(rowName .. "ItemName", L"No items with durability equipped.")
		LabelSetTextColor(rowName .. "ItemName", 180, 180, 180)
		LabelSetText(rowName .. "Durability", L"")
	end

	CorksDurabilityGump.RowCount = rowCount

	-- Update scroll child height only. Width is always the XML constant —
	-- never derived from WindowGetDimensions to avoid any scale feedback.
	WindowSetDimensions(scrollChild, CorksDurabilityGump.SCROLL_CHILD_WIDTH, rowCount * 22)
end
