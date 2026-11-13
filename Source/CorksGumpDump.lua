----------------------------------------------------------------
-- /gumpdump: a temporary tool for finding where a server gump keeps a value
-- (e.g. an event NPC's reward points). With the gump open, type /gumpdump in
-- chat. Each open server gump's ID and text lines are printed to chat and
-- written to logs/CorksGumpDump.log in the game folder.
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
