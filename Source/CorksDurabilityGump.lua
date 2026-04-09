----------------------------------------------------------------
-- Global Variables
----------------------------------------------------------------

CorksDurabilityGump = {}

CorksDurabilityGump.DURABILITY_TID = 1060639
CorksDurabilityGump.REFRESH_INTERVAL = 10
CorksDurabilityGump.RefreshTimer = 0
CorksDurabilityGump.RowCount = 0
CorksDurabilityGump.NeedsResize = false

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
	if CorksDurabilityGump.NeedsResize then
		CorksDurabilityGump.NeedsResize = false
		CorksDurabilityGump.Resize()
		return
	end
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

-- Phase 1: build rows and set text. Resize is deferred to next frame so
-- LabelGetTextDimensions can return valid measurements after layout.
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
	CorksDurabilityGump.NeedsResize = true
end

-- Phase 2: measure label text and size the window to fit. Runs the frame
-- after Update() so the layout engine has processed the new labels.
function CorksDurabilityGump.Resize()
	local windowName = "CorksDurabilityGump"
	local scrollChild = windowName .. "ListScrollChild"
	local rowCount = CorksDurabilityGump.RowCount

	if not DoesWindowNameExist(windowName) or rowCount == 0 then
		return
	end

	local maxItemWidth = 0
	local maxDurWidth = 0

	for i = 1, rowCount do
		local rowName = scrollChild .. "Row" .. i
		if DoesWindowNameExist(rowName) then
			local itemW, _ = LabelGetTextDimensions(rowName .. "ItemName")
			if itemW and itemW > maxItemWidth then
				maxItemWidth = itemW
			end
			local durW, _ = LabelGetTextDimensions(rowName .. "Durability")
			if durW and durW > maxDurWidth then
				maxDurWidth = durW
			end
		end
	end

	-- If all measurements are zero the layout engine hasn't processed the labels yet.
	-- Defer to the next frame and try again.
	if maxItemWidth == 0 and maxDurWidth == 0 then
		CorksDurabilityGump.NeedsResize = true
		return
	end

	-- Also account for the header label widths
	local headerItemW, _ = LabelGetTextDimensions(windowName .. "HeaderItem")
	if headerItemW and headerItemW > maxItemWidth then
		maxItemWidth = headerItemW
	end
	local headerDurW, _ = LabelGetTextDimensions(windowName .. "HeaderDur")
	if headerDurW and headerDurW > maxDurWidth then
		maxDurWidth = headerDurW
	end

	-- Layout constants
	-- Row layout: leftMargin | itemLabel | gap | durLabel | rightPad
	-- scrollPad = list x-offset(10) + scrollbar width(20) + right margin(10)
	local leftMargin = 8
	local gap        = 20
	local rightPad   = 16
	local scrollPad  = 40
	local minWidth   = 250

	local durLabelWidth = maxDurWidth + 16
	if durLabelWidth < 80 then
		durLabelWidth = 80
	end

	local contentWidth = scrollPad + leftMargin + maxItemWidth + gap + durLabelWidth + rightPad
	if contentWidth < minWidth then
		contentWidth = minWidth
	end

	local itemLabelWidth = contentWidth - scrollPad - leftMargin - gap - durLabelWidth - rightPad

	-- Durability header x relative to window topleft (list starts at x=10)
	local durColumnX = 10 + leftMargin + itemLabelWidth + gap

	-- Preserve the user-applied scale (set via mouse wheel) when resizing.
	-- Without this, calling WindowSetDimensions resets the visual scale.
	local currentScale = WindowGetScale(windowName)
	WindowSetDimensions(windowName, contentWidth, 400)
	WindowSetScale(windowName, currentScale)
	WindowSetDimensions(windowName .. "List", contentWidth - 20, 320)
	WindowSetDimensions(scrollChild, contentWidth - 40, rowCount * 22)

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

	WindowSetDimensions(windowName .. "HeaderItem", itemLabelWidth, 20)
	WindowSetDimensions(windowName .. "HeaderDur", durLabelWidth, 20)
	WindowClearAnchors(windowName .. "HeaderDur")
	WindowAddAnchor(windowName .. "HeaderDur", "topleft", windowName, "topleft", durColumnX, 38)
end
