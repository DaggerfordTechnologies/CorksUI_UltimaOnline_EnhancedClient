----------------------------------------------------------------
-- Corks' Jewelry Box Search
--
-- A search box laid over the bottom of an open jewelry box (server gump
-- 999143), with a red X on its left that clears it. Items on the page you're
-- looking at that don't match are covered with a dark square. The jewelry box
-- only sends the page you're on, so the other pages can't be searched until
-- you view them. Each page you view is remembered while the box stays open,
-- and hovering the search box lists how many matches each of those pages has.
--
-- Searching matches an item's name and property text, ignoring case. Several
-- words must all match ("gold ring luck"), in any order.
----------------------------------------------------------------

CorksJewelrySearch = {}

CorksJewelrySearch.GUMP_ID = 999143
CorksJewelrySearch.ITEMS_TID = 1157698   -- "Items: ~1_COUNT~ of ~2_MAX~"
CorksJewelrySearch.PAGE_TID = 1153561    -- "Page ~1_CUR~ of ~2_MAX~"
CorksJewelrySearch.WINDOW = "CorksJewelrySearch"
CorksJewelrySearch.BOX = "CorksJewelrySearchBox"
CorksJewelrySearch.MARK_TEMPLATE = "CorksJewelrySearchMarkTemplate"
CorksJewelrySearch.MARK_PREFIX = "CorksJewelrySearchMark"
CorksJewelrySearch.CHECK_SECONDS = 0.25
-- Changing page closes the gump and the server sends a new one. If the box
-- vanishes within CLICK_SECONDS of a click on one of its buttons, the search is
-- kept for up to CLOSE_SECONDS while the new one arrives. Vanishing without a
-- click means the player closed it, and the search is cleared after
-- QUICK_SECONDS: short enough that nobody reopens the box in time, long enough
-- that a page change still survives if the click wasn't seen.
CorksJewelrySearch.CLICK_SECONDS = 1
CorksJewelrySearch.CLOSE_SECONDS = 5
CorksJewelrySearch.QUICK_SECONDS = 0.75
CorksJewelrySearch.Clock = 0
CorksJewelrySearch.ClickedAt = nil
CorksJewelrySearch.Reopening = false
-- Window names of the open box's buttons, to recognise clicks on them
CorksJewelrySearch.Buttons = {}
CorksJewelrySearch.DIM_ALPHA = 0.75
-- How far up from the jewelry box's bottom edge the search box sits
CorksJewelrySearch.BOTTOM_INSET = 12

-- Search words, lower case. Empty = no search.
CorksJewelrySearch.Terms = {}
-- objectId -> lower-case name and property text (filled as properties arrive)
CorksJewelrySearch.TextCache = {}
-- objectId -> page it was seen on, for the box that's open
CorksJewelrySearch.Seen = {}
-- "count/pages" of the open box; when it changes (a filter was picked, an item
-- added or taken out) the remembered pages no longer line up and are dropped
CorksJewelrySearch.Signature = nil
CorksJewelrySearch.Page = 0
CorksJewelrySearch.Pages = 0
-- Items on the current page: { { button = windowName, id = objectId }, ... }
CorksJewelrySearch.Current = {}
-- objectIds whose properties were requested and are still awaited
CorksJewelrySearch.Requested = {}
CorksJewelrySearch.MarkCount = 0
CorksJewelrySearch.Tick = 0
CorksJewelrySearch.GoneFor = 0
CorksJewelrySearch.Showing = false
CorksJewelrySearch.LastShown = nil

----------------------------------------------------------------
-- Text helpers (no client windows; covered by tests/test_jewelrysearch.lua)
----------------------------------------------------------------

-- Any client text value as a plain string, or nil. type() can't be trusted to
-- tell wide strings from plain ones in the client, so test with wstring.len.
function CorksJewelrySearch.ToText(value)
	if value == nil then
		return nil
	end
	if type(value) == "number" then
		return tostring(value)
	end
	local isWide = wstring ~= nil and pcall(wstring.len, value)
	if not isWide and type(value) == "string" then
		return value
	end
	local ok, text = pcall(WStringToString, value)
	if ok and type(text) == "string" then
		return text
	end
	return nil
end

-- The search box text split into lower-case words
function CorksJewelrySearch.ParseTerms(text)
	local terms = {}
	text = CorksJewelrySearch.ToText(text) or ""
	for word in string.gmatch(string.lower(text), "%S+") do
		table.insert(terms, word)
	end
	return terms
end

-- True when the item text contains every search word
function CorksJewelrySearch.Matches(itemText, terms)
	if not itemText then
		return false
	end
	for _, term in ipairs(terms) do
		if not string.find(itemText, term, 1, true) then
			return false
		end
	end
	return true
end

-- Remembers which items are on a page. Items no longer on that page are
-- forgotten (they were taken out or moved to another page).
function CorksJewelrySearch.RecordPage(seen, page, ids)
	for id, onPage in pairs(seen) do
		if onPage == page then
			seen[id] = nil
		end
	end
	for _, id in ipairs(ids) do
		seen[id] = page
	end
end

-- The result line: matches on this page, on each other viewed page, and the
-- pages not viewed yet. textOf(id) gives an item's text, or nil if not loaded.
function CorksJewelrySearch.Summary(seen, page, pages, terms, textOf)
	if #terms == 0 then
		return "Type to search. Pages you view are remembered while the box is open."
	end
	local perPage, loading = {}, 0
	for id, onPage in pairs(seen) do
		local text = textOf(id)
		if text == nil then
			loading = loading + 1
		elseif CorksJewelrySearch.Matches(text, terms) then
			perPage[onPage] = (perPage[onPage] or 0) + 1
		end
	end
	local parts = { "This page: " .. (perPage[page] or 0) }
	local unseen = {}
	for p = 1, math.max(pages, 1) do
		if p ~= page then
			if perPage[p] then
				table.insert(parts, "Page " .. p .. ": " .. perPage[p])
			else
				local viewed = false
				for _, onPage in pairs(seen) do
					if onPage == p then
						viewed = true
						break
					end
				end
				if not viewed then
					table.insert(unseen, tostring(p))
				end
			end
		end
	end
	if #unseen > 0 then
		table.insert(parts, "Not viewed: " .. table.concat(unseen, ", "))
	end
	if loading > 0 then
		table.insert(parts, "Loading " .. loading)
	end
	return table.concat(parts, "  |  ")
end

----------------------------------------------------------------
-- Reading the jewelry box gump
----------------------------------------------------------------

-- A label's numeric parameter, e.g. the 1 and 2 in "Page 1 of 2"
function CorksJewelrySearch.Param(label, index)
	if type(label) ~= "table" or type(label.tidParms) ~= "table" then
		return nil
	end
	local text = CorksJewelrySearch.ToText(label.tidParms[index])
	if not text then
		return nil
	end
	return tonumber((string.gsub(text, "[^%d]", "")))
end

-- The object ID an item picture of the gump shows, or nil
function CorksJewelrySearch.ItemIdOf(buttonName)
	if type(buttonName) ~= "string" or not DoesWindowNameExist(buttonName) then
		return nil
	end
	local ok, gumpId = pcall(WindowGetId, buttonName)
	if not ok or not gumpId then
		return nil
	end
	local found, objectId = pcall(GenericGumpGetItemPropertiesId, gumpId, buttonName)
	if found and objectId and objectId ~= 0 then
		return objectId
	end
	return nil
end

-- An item's lower-case name and properties, or nil while they haven't arrived.
-- Asks the client for them the first time and keeps the request open until
-- they come, so they load without hovering the item.
function CorksJewelrySearch.ItemText(objectId)
	local cached = CorksJewelrySearch.TextCache[objectId]
	if cached then
		return cached
	end
	local data = WindowData.ItemProperties[objectId]
	if not data and not CorksJewelrySearch.Requested[objectId] then
		CorksJewelrySearch.Requested[objectId] = true
		pcall(RegisterWindowData, WindowData.ItemProperties.Type, objectId)
		data = WindowData.ItemProperties[objectId]
	end
	if type(data) ~= "table" or type(data.PropertiesList) ~= "table" or #data.PropertiesList == 0 then
		return nil
	end
	local parts = {}
	for _, line in ipairs(data.PropertiesList) do
		local ok, plain = pcall(WindowUtils.translateMarkup, line)
		local text = CorksJewelrySearch.ToText(ok and plain or line)
		if text then
			table.insert(parts, text)
		end
	end
	if #parts == 0 then
		return nil
	end
	local text = string.lower(table.concat(parts, " | "))
	CorksJewelrySearch.TextCache[objectId] = text
	CorksJewelrySearch.ReleaseRequest(objectId)
	return text
end

function CorksJewelrySearch.ReleaseRequest(objectId)
	if CorksJewelrySearch.Requested[objectId] then
		CorksJewelrySearch.Requested[objectId] = nil
		pcall(UnregisterWindowData, WindowData.ItemProperties.Type, objectId)
	end
end

-- Reads the open jewelry box: page numbers and the items shown.
-- Returns false when no jewelry box is open.
function CorksJewelrySearch.ReadGump()
	local J = CorksJewelrySearch
	local gump = GumpData and type(GumpData.Gumps) == "table" and GumpData.Gumps[J.GUMP_ID]
	if type(gump) ~= "table" or type(gump.windowName) ~= "string" or not DoesWindowNameExist(gump.windowName) then
		return false
	end
	local count, page, pages
	if type(gump.Labels) == "table" then
		for _, label in pairs(gump.Labels) do
			if type(label) == "table" then
				if label.tid == J.ITEMS_TID then
					count = J.Param(label, 1)
				elseif label.tid == J.PAGE_TID then
					page = J.Param(label, 1)
					pages = J.Param(label, 2)
				end
			end
		end
	end
	J.GumpWindow = gump.windowName
	J.Page = page or 1
	J.Pages = pages or 1

	local signature = tostring(count) .. "/" .. tostring(J.Pages)
	if signature ~= J.Signature then
		J.Signature = signature
		J.Seen = {}
	end

	-- Every button that shows an item is one of the page's item pictures; the
	-- filter, page and Add Jewelry buttons don't have one
	local current, ids, buttons = {}, {}, {}
	if type(gump.Buttons) == "table" then
		local numbers = {}
		for number in pairs(gump.Buttons) do
			table.insert(numbers, number)
		end
		table.sort(numbers, function(a, b) return tostring(a) < tostring(b) end)
		for _, number in ipairs(numbers) do
			local name = gump.Buttons[number]
			if type(name) == "string" then
				buttons[name] = true
			end
			local id = J.ItemIdOf(name)
			if id then
				table.insert(current, { button = name, id = id })
				table.insert(ids, id)
			end
		end
	end
	J.Current = current
	J.Buttons = buttons
	J.RecordPage(J.Seen, J.Page, ids)
	return true
end

-- Wraps GenericGump.OnClicked to note clicks on the jewelry box's buttons.
-- A page, filter or item click makes the server close the box and send it
-- again, so the box vanishing right after one isn't the player closing it.
function CorksJewelrySearch.InstallClickHook()
	if not GenericGump or CorksJewelrySearch.HookedOnClicked or type(GenericGump.OnClicked) ~= "function" then
		return
	end
	local original = GenericGump.OnClicked
	CorksJewelrySearch.HookedOnClicked = original
	GenericGump.OnClicked = function(...)
		pcall(function()
			local J = CorksJewelrySearch
			if J.Showing and J.Buttons[SystemData.ActiveWindow.name] then
				J.ClickedAt = J.Clock
			end
		end)
		return original(...)
	end
end

----------------------------------------------------------------
-- Drawing
----------------------------------------------------------------

function CorksJewelrySearch.Mark(index)
	local name = CorksJewelrySearch.MARK_PREFIX .. index
	if not DoesWindowNameExist(name) then
		CreateWindowFromTemplate(name, CorksJewelrySearch.MARK_TEMPLATE, "Root")
		WindowSetAlpha(name .. "Dim", CorksJewelrySearch.DIM_ALPHA)
		WindowSetShowing(name, false)
		if index > CorksJewelrySearch.MarkCount then
			CorksJewelrySearch.MarkCount = index
		end
	end
	return name
end

function CorksJewelrySearch.HideMarks()
	for i = 1, CorksJewelrySearch.MarkCount do
		local name = CorksJewelrySearch.MARK_PREFIX .. i
		if DoesWindowNameExist(name) then
			WindowSetShowing(name, false)
			WindowClearAnchors(name)
		end
	end
end

-- Covers the items on this page that don't match, and updates the result line
function CorksJewelrySearch.Apply()
	local J = CorksJewelrySearch
	local terms = J.Terms
	local used = 0
	local key = {}
	for _, item in ipairs(J.Current) do
		local text = J.ItemText(item.id)
		-- Items still loading stay uncovered rather than looking like misses
		local hide = #terms > 0 and text ~= nil and not J.Matches(text, terms)
		if hide then
			table.insert(key, item.button)
		end
	end
	local summary = J.Summary(J.Seen, J.Page, J.Pages, terms, J.ItemText)
	local shown = table.concat(key, ",") .. "#" .. summary
	if shown == J.LastShown then
		return
	end
	J.LastShown = shown
	J.SummaryText = summary

	J.HideMarks()
	for _, button in ipairs(key) do
		if DoesWindowNameExist(button) then
			used = used + 1
			local mark = J.Mark(used)
			WindowClearAnchors(mark)
			WindowAddAnchor(mark, "topleft", button, "topleft", 0, 0)
			WindowAddAnchor(mark, "bottomright", button, "bottomright", 0, 0)
			WindowSetShowing(mark, true)
		end
	end
end

-- Lays the search box over the bottom of the jewelry box, centered, at the
-- box's scale so it shrinks and grows with it
function CorksJewelrySearch.ShowBar(gumpWindow)
	local J = CorksJewelrySearch
	if not DoesWindowNameExist(J.WINDOW) then
		return
	end
	local ok, scale = pcall(WindowGetScale, gumpWindow)
	if ok and scale and scale > 0 and scale ~= J.Scale then
		WindowSetScale(J.WINDOW, scale)
		J.Scale = scale
	end
	if not J.Showing or J.AnchoredTo ~= gumpWindow then
		WindowClearAnchors(J.WINDOW)
		WindowAddAnchor(J.WINDOW, "bottom", gumpWindow, "bottom", 0, -J.BOTTOM_INSET)
		J.AnchoredTo = gumpWindow
	end
	if not J.Showing then
		WindowSetShowing(J.WINDOW, true)
		J.Showing = true
		J.LastShown = nil
	end
end

-- Hides the bar and covers. forget = the box was closed, so drop what was seen
-- and empty the search box.
function CorksJewelrySearch.HideBar(forget)
	local J = CorksJewelrySearch
	J.HideMarks()
	if J.Showing and DoesWindowNameExist(J.WINDOW) then
		WindowAssignFocus(J.BOX, false)
		WindowSetShowing(J.WINDOW, false)
	end
	J.Showing = false
	J.AnchoredTo = nil
	J.Scale = nil
	J.LastShown = nil
	J.Current = {}
	J.Buttons = {}
	if forget then
		J.Seen = {}
		J.Signature = nil
		J.Reopening = false
		J.Terms = {}
		J.SummaryText = nil
		if DoesWindowNameExist(J.BOX) then
			TextEditBoxSetText(J.BOX, L"")
		end
		for id in pairs(J.Requested) do
			J.ReleaseRequest(id)
		end
	end
end

----------------------------------------------------------------
-- Update loop (called from Interface.OnUpdate)
----------------------------------------------------------------

function CorksJewelrySearch.OnUpdate(timePassed)
	local J = CorksJewelrySearch
	J.Clock = J.Clock + (timePassed or 0)
	J.Tick = J.Tick + (timePassed or 0)
	if J.Tick < J.CHECK_SECONDS then
		return
	end
	local elapsed = J.Tick
	J.Tick = 0

	if J.ReadGump() then
		J.GoneFor = 0
		J.Reopening = false
		J.ShowBar(J.GumpWindow)
		J.Apply()
	elseif J.Showing or J.Signature then
		-- Gone: hide right away (covers would point at missing windows). If one
		-- of its buttons was just clicked the server is sending it again, so keep
		-- the search for a while; otherwise the player closed it.
		if J.Showing then
			J.Reopening = J.ClickedAt ~= nil and J.Clock - J.ClickedAt <= J.CLICK_SECONDS
		end
		J.GoneFor = J.GoneFor + elapsed
		J.HideBar(J.GoneFor >= (J.Reopening and J.CLOSE_SECONDS or J.QUICK_SECONDS))
	end
end

----------------------------------------------------------------
-- Search box
----------------------------------------------------------------

function CorksJewelrySearch.OnBoxClick()
	WindowAssignFocus(CorksJewelrySearch.BOX, true)
end

function CorksJewelrySearch.OnTextChanged()
	local J = CorksJewelrySearch
	J.Terms = J.ParseTerms(TextEditBoxGetText(J.BOX))
	J.LastShown = nil
	if J.Showing then
		J.Apply()
	end
end

function CorksJewelrySearch.OnBoxEnter()
	WindowAssignFocus(CorksJewelrySearch.BOX, false)
end

-- The red X (or Escape) clears the search
function CorksJewelrySearch.OnClear()
	TextEditBoxSetText(CorksJewelrySearch.BOX, L"")
	CorksJewelrySearch.OnTextChanged()
	WindowAssignFocus(CorksJewelrySearch.BOX, false)
end

function CorksJewelrySearch.ShowTooltip(text)
	Tooltips.CreateTextOnlyTooltip(SystemData.ActiveWindow.name, StringToWString(text))
	Tooltips.Finalize()
	Tooltips.AnchorTooltip(Tooltips.ANCHOR_WINDOW_TOP)
end

function CorksJewelrySearch.OnClearTooltip()
	CorksJewelrySearch.ShowTooltip("Clear search")
end

-- Match counts: this page, other pages viewed, pages not viewed yet
function CorksJewelrySearch.OnBoxTooltip()
	CorksJewelrySearch.ShowTooltip(CorksJewelrySearch.SummaryText or "Type to search the jewelry box")
end
