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
	local maxItemWidth = 0
	local maxDurWidth = 0

	for index = 1, WindowData.Paperdoll[playerId].numSlots do
		local slotData = WindowData.Paperdoll[playerId][index]

		if slotData.slotId ~= 0 and CorksDurabilityGump.SlotNames[index] then
			local objectId = slotData.slotId
			local dur = ItemProperties.GetObjectPropertiesParamsForTid(objectId, CorksDurabilityGump.DURABILITY_TID, "CorksDurabilityGump")

			if dur then
				rowCount = rowCount + 1
				local current = tonumber(dur[1])
				local max = tonumber(dur[2])

				-- Get item name (first property line)
				local itemName = ItemProperties.GetObjectProperties(objectId, 1, "CorksDurabilityGump")
				if not itemName then
					itemName = L"Unknown"
				end

				local rowName = scrollChild .. "Row" .. rowCount
				CreateWindowFromTemplate(rowName, "CorksDurabilityGumpRowTemplate", scrollChild)

				if rowCount == 1 then
					WindowAddAnchor(rowName, "topleft", scrollChild, "topleft", 0, 0)
				else
					WindowAddAnchor(rowName, "topleft", scrollChild .. "Row" .. (rowCount - 1), "bottomleft", 0, 0)
				end

				-- Item name
				LabelSetText(rowName .. "ItemName", itemName)
				local itemW, _ = LabelGetTextDimensions(rowName .. "ItemName")
				if itemW and itemW > maxItemWidth then
					maxItemWidth = itemW
				end

				-- Durability text
				local durText = towstring(tostring(current) .. " / " .. tostring(max))
				LabelSetText(rowName .. "Durability", durText)
				local durW, _ = LabelGetTextDimensions(rowName .. "Durability")
				if durW and durW > maxDurWidth then
					maxDurWidth = durW
				end

				-- Color based on durability percentage
				local perc = 0
				if max > 0 then
					perc = math.floor((current / max) * 100)
				end

				if perc > 75 then
					-- Green
					LabelSetTextColor(rowName .. "Durability", 0, 255, 0)
				elseif perc > 50 then
					-- Yellow
					LabelSetTextColor(rowName .. "Durability", 255, 255, 0)
				elseif perc > 25 then
					-- Orange
					LabelSetTextColor(rowName .. "Durability", 255, 165, 0)
				elseif perc > 10 then
					-- Red
					LabelSetTextColor(rowName .. "Durability", 255, 80, 0)
				else
					-- Bright red
					LabelSetTextColor(rowName .. "Durability", 255, 0, 0)
				end
			end
		end
	end

	-- If no items with durability found, show a message
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

	-- Measure header text width to ensure durability column fits both header and values
	local headerDurW, _ = LabelGetTextDimensions(windowName .. "HeaderDur")
	if headerDurW and headerDurW > maxDurWidth then
		maxDurWidth = headerDurW
	end

	-- Layout constants
	-- Row content layout: leftMargin | itemLabel | gap | durLabel | rightPad
	-- Row width = contentWidth - scrollPad  (scrollbar 20 + list-left offset 10 + inner margin 10)
	local leftMargin = 8   -- item label left offset in row template (from XML anchor)
	local gap        = 20  -- gap between item and durability columns
	local rightPad   = 16  -- padding after durability label to row right edge
	local scrollPad  = 40  -- accounts for scrollbar + list/window offsets
	local minWidth   = 250

	local durLabelWidth = maxDurWidth + 16
	if durLabelWidth < 80 then
		durLabelWidth = 80
	end

	-- Derive contentWidth so all columns fit exactly within the row
	local contentWidth = scrollPad + leftMargin + maxItemWidth + gap + durLabelWidth + rightPad
	if contentWidth < minWidth then
		contentWidth = minWidth
	end

	-- Recalculate itemLabelWidth in case minWidth clamped contentWidth upward
	local itemLabelWidth = contentWidth - scrollPad - leftMargin - gap - durLabelWidth - rightPad

	-- Durability column x relative to window topleft:
	-- list starts at x=10, row at scrollChild topleft, item label at leftMargin inside row
	local durColumnX = 10 + leftMargin + itemLabelWidth + gap

	WindowSetDimensions(windowName, contentWidth, 400)
	WindowSetDimensions(windowName .. "List", contentWidth - 20, 320)
	WindowSetDimensions(scrollChild, contentWidth - 40, rowCount * 22)

	-- Resize rows and reposition durability labels
	for i = 1, rowCount do
		local rowName = scrollChild .. "Row" .. i
		if DoesWindowNameExist(rowName) then
			WindowSetDimensions(rowName, contentWidth - 40, 22)
			WindowSetDimensions(rowName .. "ItemName", itemLabelWidth, 20)
			WindowSetDimensions(rowName .. "Durability", durLabelWidth, 20)
			WindowClearAnchors(rowName .. "Durability")
			WindowAddAnchor(rowName .. "Durability", "left", rowName, "left", leftMargin + itemLabelWidth + gap, 0)
		end
	end

	-- Position header labels to match column positions
	WindowSetDimensions(windowName .. "HeaderItem", itemLabelWidth, 20)
	WindowSetDimensions(windowName .. "HeaderDur", durLabelWidth, 20)
	WindowClearAnchors(windowName .. "HeaderDur")
	WindowAddAnchor(windowName .. "HeaderDur", "topleft", windowName, "topleft", durColumnX, 38)
end
