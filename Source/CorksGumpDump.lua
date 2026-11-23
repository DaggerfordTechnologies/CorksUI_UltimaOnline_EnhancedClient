----------------------------------------------------------------
-- /gumpdump: a temporary tool for finding where a server gump keeps a value
-- (e.g. an event NPC's reward points). With the gump open, type /gumpdump in
-- chat. Each open server gump's ID and text lines are printed to chat and
-- written to logs/CorksGumpDump.log in the game folder, along with the gump's
-- button IDs and any item pictures (object ID and properties) it shows.
-- Hovering a few item pictures before running it helps it find the rest.
----------------------------------------------------------------

CorksGumpDump = {}

CorksGumpDump.LOG = "CorksGumpDump"
CorksGumpDump.LOG_FILE = "logs/CorksGumpDump.log"
-- Chat only gets the first part of long lines; the log file gets all of it
CorksGumpDump.CHAT_LIMIT = 160

-- Opens (or reopens, after a UI reload) the log file, emptied
function CorksGumpDump.StartLog()
	local log = CorksGumpDump.LOG
	pcall(TextLogCreate, log, 2000)
	TextLogSetEnabled(log, true)
	TextLogClear(log)
	TextLogSetIncrementalSaving(log, true, CorksGumpDump.LOG_FILE)
	pcall(TextLogAddFilterType, log, 1, L"")
end

function CorksGumpDump.Line(text)
	text = tostring(text)
	pcall(TextLogAddEntry, CorksGumpDump.LOG, 1, StringToWString(text))
	local shown = text
	if string.len(shown) > CorksGumpDump.CHAT_LIMIT then
		shown = string.sub(shown, 1, CorksGumpDump.CHAT_LIMIT) .. "..."
	end
	pcall(WindowUtils.ChatPrint, StringToWString(shown), SystemData.ChatLogFilters.SYSTEM)
end

-- Any value as readable text, without failing on wstrings or tables
function CorksGumpDump.Show(value, depth)
	depth = depth or 0
	local kind = type(value)
	if kind == "wstring" or kind == "userdata" then
		local ok, text = pcall(WStringToString, value)
		if ok and text then
			return "\"" .. text .. "\""
		end
		return tostring(value)
	elseif kind == "string" then
		return "\"" .. value .. "\""
	elseif kind == "table" then
		local parts = {}
		for k, v in pairs(value) do
			local item
			if type(v) == "table" and depth >= 2 then
				item = "{...}"
			else
				item = CorksGumpDump.Show(v, depth + 1)
			end
			table.insert(parts, tostring(k) .. "=" .. item)
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end

-- A label's cliloc text with its parameters filled in, or nil
function CorksGumpDump.LabelText(label)
	if type(label) ~= "table" or not label.tid or label.tid == 0 then
		return nil
	end
	local ok, text = pcall(function()
		local base = GetStringFromTid(label.tid)
		if label.tidParms then
			return ReplaceTokens(base, label.tidParms)
		end
		return base
	end)
	if ok and text then
		return CorksGumpDump.Show(text)
	end
	return nil
end

function CorksGumpDump.DumpGump(gumpId, data)
	CorksGumpDump.Line("== Gump ID " .. tostring(gumpId) .. "  window=" .. CorksGumpDump.Show(data.windowName))

	-- What else the client keeps for the gump, so nothing is missed
	local keys = {}
	for k, v in pairs(data) do
		table.insert(keys, tostring(k) .. ":" .. type(v))
	end
	table.sort(keys)
	CorksGumpDump.Line("   fields: " .. table.concat(keys, " "))

	if type(data.Labels) == "table" then
		local ids = {}
		for k in pairs(data.Labels) do
			table.insert(ids, k)
		end
		table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
		for _, k in ipairs(ids) do
			local label = data.Labels[k]
			local text = CorksGumpDump.LabelText(label)
			local line = "   label " .. tostring(k) .. ": " .. CorksGumpDump.Show(label)
			if text then
				line = line .. "  -> " .. text
			end
			CorksGumpDump.Line(line)
		end
	end

	if type(data.TextEntry) == "table" then
		CorksGumpDump.Line("   text entries: " .. CorksGumpDump.Show(data.TextEntry))
	end

	-- Button ID -> window name: shows which IDs page or filter the gump, and how
	-- the client names the gump's child windows
	if type(data.Buttons) == "table" then
		local ids = {}
		for k in pairs(data.Buttons) do
			table.insert(ids, k)
		end
		table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
		for _, k in ipairs(ids) do
			local name = data.Buttons[k]
			local line = "   button " .. tostring(k) .. ": " .. CorksGumpDump.Show(name)
			local item = CorksGumpDump.ItemIdOf(name, data.windowName)
			if item then
				line = line .. "  item=" .. tostring(item)
			end
			CorksGumpDump.Line(line)
		end
	end

	CorksGumpDump.DumpItems(data)
end

----------------------------------------------------------------
-- Item pictures (e.g. a jewelry box's contents)
----------------------------------------------------------------

-- Names of gump windows hovered since the UI loaded, with the item they showed
CorksGumpDump.Hovered = {}
-- How far to count when guessing child window names
CorksGumpDump.PROBE_MAX = 400
-- Name endings to try after the gump's window name, besides those seen on buttons
CorksGumpDump.PROBE_SUFFIXES = { "", "Image", "Item", "ItemImage", "Tile", "TilePic", "Pic", "Button", "Label", "Child" }

-- The object ID a gump child window shows, or nil
function CorksGumpDump.ItemIdOf(childName, gumpWindowName)
	if not childName or not DoesWindowNameExist(childName) then
		return nil
	end
	local ids = {}
	local ok, id = pcall(WindowGetId, childName)
	if ok and id then
		table.insert(ids, id)
	end
	if gumpWindowName and DoesWindowNameExist(gumpWindowName) then
		ok, id = pcall(WindowGetId, gumpWindowName)
		if ok and id then
			table.insert(ids, id)
		end
	end
	for _, gumpId in ipairs(ids) do
		local found, objectId = pcall(GenericGumpGetItemPropertiesId, gumpId, childName)
		if found and objectId and objectId ~= 0 then
			return objectId
		end
	end
	return nil
end

-- An item's property lines as one string, or a note that they aren't loaded
function CorksGumpDump.ItemText(objectId)
	local ok, lines = pcall(ItemProperties.GetObjectProperties, objectId, nil, "CorksGumpDump")
	if not ok or type(lines) ~= "table" or #lines == 0 then
		return "(properties not loaded yet - hover the item or run /gumpdump again)"
	end
	local parts = {}
	for i, line in ipairs(lines) do
		parts[i] = CorksGumpDump.Show(line)
	end
	return table.concat(parts, " | ")
end

-- Finds the gump's child windows that show an item, by trying likely names
function CorksGumpDump.DumpItems(data)
	local root = data.windowName
	if type(root) ~= "string" or not DoesWindowNameExist(root) then
		return
	end

	-- Prefixes: the gump's name plus each guessed ending, and every known child
	-- name (buttons, hovered windows) with its trailing number removed
	local prefixes, seenPrefix = {}, {}
	local function addPrefix(prefix)
		if prefix and not seenPrefix[prefix] then
			seenPrefix[prefix] = true
			table.insert(prefixes, prefix)
		end
	end
	for _, suffix in ipairs(CorksGumpDump.PROBE_SUFFIXES) do
		addPrefix(root .. suffix)
	end
	local known = {}
	if type(data.Buttons) == "table" then
		for _, name in pairs(data.Buttons) do
			table.insert(known, name)
		end
	end
	for name in pairs(CorksGumpDump.Hovered) do
		table.insert(known, name)
	end
	for _, name in ipairs(known) do
		if type(name) == "string" and string.sub(name, 1, string.len(root)) == root then
			addPrefix((string.gsub(name, "%d+$", "")))
		end
	end

	local found, seenWindow = 0, {}
	local windows = 0
	for _, prefix in ipairs(prefixes) do
		for i = 0, CorksGumpDump.PROBE_MAX do
			local name = prefix .. i
			if not seenWindow[name] and DoesWindowNameExist(name) then
				seenWindow[name] = true
				windows = windows + 1
				local objectId = CorksGumpDump.ItemIdOf(name, root)
				if objectId then
					found = found + 1
					CorksGumpDump.Line("   item " .. name .. ": id=" .. tostring(objectId) .. "  " .. CorksGumpDump.ItemText(objectId))
				end
			end
		end
	end
	CorksGumpDump.Line("   item scan: " .. found .. " item(s) among " .. windows .. " child window(s) found by name")

	-- Hovered windows of this gump that the name scan missed
	for name, entry in pairs(CorksGumpDump.Hovered) do
		if not seenWindow[name] and string.sub(name, 1, string.len(root)) == root then
			CorksGumpDump.Line("   hovered " .. name .. ": id=" .. tostring(entry.objectId) .. "  " .. CorksGumpDump.ItemText(entry.objectId))
		end
	end
end

-- Wraps GenericGump.OnMouseOver to note each hovered gump window that shows an
-- item. Its name tells the scan how the client names item pictures.
function CorksGumpDump.InstallHoverHook()
	if not GenericGump or CorksGumpDump.HookedOnMouseOver or type(GenericGump.OnMouseOver) ~= "function" then
		return
	end
	local original = GenericGump.OnMouseOver
	CorksGumpDump.HookedOnMouseOver = original
	GenericGump.OnMouseOver = function(...)
		pcall(function()
			local name = SystemData.ActiveWindow.name
			local objectId = CorksGumpDump.ItemIdOf(name, nil)
			if objectId then
				CorksGumpDump.Hovered[name] = { objectId = objectId }
			end
		end)
		return original(...)
	end
end

-- The text as drawn on screen, for the most recently opened gump only (the
-- default UI keeps this list for one gump). Catches plain and HTML text that
-- has no cliloc number.
function CorksGumpDump.DumpDrawnText()
	local labels = GenericGump and GenericGump.LastGumpLabels
	CorksGumpDump.Line("== Drawn text of the latest gump (" .. CorksGumpDump.Show(GenericGump and GenericGump.LastGump) .. ")")
	if type(labels) ~= "table" or #labels == 0 then
		CorksGumpDump.Line("   (none)")
		return
	end
	for i, entry in ipairs(labels) do
		local name = entry.windowName
		if name and DoesWindowNameExist(name) then
			local ok, text = pcall(LabelGetText, name)
			if ok and text then
				CorksGumpDump.Line("   " .. i .. " " .. name .. ": " .. CorksGumpDump.Show(text))
			end
		end
	end
end

function CorksGumpDump.Run()
	local ok, err = pcall(function()
		CorksGumpDump.StartLog()
		local count = 0
		if GumpData and type(GumpData.Gumps) == "table" then
			local ids = {}
			for gumpId in pairs(GumpData.Gumps) do
				table.insert(ids, gumpId)
			end
			table.sort(ids, function(a, b) return tostring(a) < tostring(b) end)
			for _, gumpId in ipairs(ids) do
				count = count + 1
				local data = GumpData.Gumps[gumpId]
				if type(data) == "table" then
					local done, problem = pcall(CorksGumpDump.DumpGump, gumpId, data)
					if not done then
						CorksGumpDump.Line("   error: " .. tostring(problem))
					end
				end
			end
		end
		if count == 0 then
			CorksGumpDump.Line("Gump dump: no server gumps are open.")
		end
		CorksGumpDump.DumpDrawnText()
		CorksGumpDump.Line("Gump dump: " .. count .. " gump(s), saved to " .. CorksGumpDump.LOG_FILE)
	end)
	if not ok then
		pcall(WindowUtils.ChatPrint, StringToWString("Gump dump error: " .. tostring(err)), SystemData.ChatLogFilters.SYSTEM)
	end
end
