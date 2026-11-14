----------------------------------------------------------------
-- Keeps the buff/debuff icons through /reloadui.
--
-- The server only reports a buff when it starts or ends (and all of them at
-- login), and a UI reload throws away the icons and the default UI's list of
-- active buffs, so they'd be gone until the next login. /reloadui calls Save
-- just before reloading. Lua globals do NOT survive a reload (verified), so the
-- buffs are written as lines of text to a client text log, which does, and to
-- the UI settings as a fallback. Once the buff bar exists again Update reads
-- them back and recreates each icon through the default UI's own
-- BuffDebuff.CreateNewBuff, with its timer reduced by the time the reload took.
--
-- Lines: "T|<time>", then per buff "B|<id>|<has timer 0/1>|<seconds left>|<good 0/1>|<abilityId>"
-- followed by its name lines "N|<text>" and tooltip lines "P|<text>".
----------------------------------------------------------------

CorksBuffRestore = {}

-- How long after the reload to wait before restoring, so the buff bar is ready
-- and any buffs the server re-sends by itself arrive first (seconds)
CorksBuffRestore.DELAY = 2
-- A snapshot older than this is ignored (seconds)
CorksBuffRestore.MAX_AGE = 120
CorksBuffRestore.Wait = 0

-- What was saved and what happened to each buff, written to the game's logs
-- folder (the log is emptied by each save, so it covers the latest reload)
CorksBuffRestore.LOG = "CorksBuffRestore"
CorksBuffRestore.LOG_FILE = "logs/CorksBuffRestore.log"
CorksBuffRestore.LogReady = false
CorksBuffRestore.CheckedAfterLoad = false

-- Where the snapshot is kept through the reload
CorksBuffRestore.STORE_LOG = "CorksBuffSnapshot"
CorksBuffRestore.STORE_SETTING = "CorksBuffSnapshot"
-- The snapshot read back after the reload, waiting to be restored
CorksBuffRestore.Pending = nil

function CorksBuffRestore.Log(text, clear)
	pcall(function()
		local log = CorksBuffRestore.LOG
		if not CorksBuffRestore.LogReady then
			pcall(TextLogCreate, log, 500)
			TextLogSetEnabled(log, true)
			TextLogSetIncrementalSaving(log, true, CorksBuffRestore.LOG_FILE)
			pcall(TextLogAddFilterType, log, 1, L"")
			CorksBuffRestore.LogReady = true
		end
		if clear then
			TextLogClear(log)
			TextLogSetIncrementalSaving(log, true, CorksBuffRestore.LOG_FILE)
		end
		TextLogAddEntry(log, 1, StringToWString(tostring(text)))
	end)
end

function CorksBuffRestore.Describe(id, data, timeLeft)
	local name = ""
	if type(data.NameWStringVector) == "table" and data.NameWStringVector[1] then
		local ok, text = pcall(WStringToString, data.NameWStringVector[1])
		if ok and text then
			name = " \"" .. text .. "\""
		end
	end
	return "buff " .. tostring(id) .. name .. " good=" .. tostring(data.good)
		.. " HasTimer=" .. tostring(data.HasTimer) .. " TimerSeconds=" .. tostring(data.TimerSeconds)
		.. " timeLeft=" .. tostring(timeLeft)
end

-- Seconds since some fixed point, or nil if the client can't say
function CorksBuffRestore.Now()
	local ok, timestamp = pcall(GetCurrentDateTime)
	if ok and type(timestamp) == "number" then
		return timestamp
	end
	return nil
end

function CorksBuffRestore.CopyList(list)
	if type(list) ~= "table" then
		return list
	end
	local copy = {}
	for k, v in pairs(list) do
		copy[k] = v
	end
	return copy
end

-- Called by /reloadui just before the reload.
function CorksBuffRestore.Save()
	if not BuffDebuff or type(BuffDebuff.TableOrder) ~= "table" then
		CorksBuffRestore.Log("Save: no buff list", true)
		return
	end
	CorksBuffRestore.Log("Save: " .. #BuffDebuff.TableOrder .. " buff(s) in TableOrder", true)
	-- Every buff the default UI knows about, saved or not, to see what's missed
	for buffId, data in pairs(BuffDebuff.BuffData) do
		if type(data) == "table" then
			CorksBuffRestore.Log("  known " .. CorksBuffRestore.Describe(buffId, data, BuffDebuff.Timers[buffId])
				.. " window=" .. tostring(BuffDebuff.BuffWindowId[buffId]))
		end
	end
	local buffs = {}
	local done = {}
	for _, buffId in ipairs(BuffDebuff.TableOrder) do
		local data = BuffDebuff.BuffData[buffId]
		if not done[buffId] and BuffDebuff.BuffWindowId[buffId] == true and type(data) == "table" then
			CorksBuffRestore.Log("  saved " .. CorksBuffRestore.Describe(buffId, data, BuffDebuff.Timers[buffId]))
			done[buffId] = true
			local timeLeft = BuffDebuff.Timers[buffId]
			if type(timeLeft) ~= "number" then
				timeLeft = data.TimerSeconds
			end
			table.insert(buffs, {
				id = buffId,
				data = {
					abilityId = data.abilityId,
					TimerSeconds = timeLeft,
					HasTimer = data.HasTimer,
					NameVectorSize = data.NameVectorSize,
					ToolTipVectorSize = data.ToolTipVectorSize,
					IsBeingRemoved = false,
					NameWStringVector = CorksBuffRestore.CopyList(data.NameWStringVector),
					ToolTipWStringVector = CorksBuffRestore.CopyList(data.ToolTipWStringVector),
					good = data.good,
				},
			})
		end
	end
	CorksBuffRestore.WriteLines(CorksBuffRestore.ToLines({ time = CorksBuffRestore.Now(), buffs = buffs }))
end

----------------------------------------------------------------
-- Keeping the snapshot through the reload
----------------------------------------------------------------

-- A buff name/tooltip entry as a wstring (they normally are already)
function CorksBuffRestore.AsWString(text)
	if type(text) == "string" then
		return StringToWString(text)
	elseif type(text) == "number" then
		return towstring(text)
	end
	return text
end

function CorksBuffRestore.ToLines(snapshot)
	local lines = { StringToWString("T|" .. tostring(snapshot.time or "")) }
	for _, buff in ipairs(snapshot.buffs) do
		local d = buff.data
		table.insert(lines, StringToWString("B|" .. buff.id
			.. "|" .. (d.HasTimer and 1 or 0)
			.. "|" .. (tonumber(d.TimerSeconds) or 0)
			.. "|" .. (d.good and 1 or 0)
			.. "|" .. (tonumber(d.abilityId) or buff.id)))
		for _, text in ipairs(type(d.NameWStringVector) == "table" and d.NameWStringVector or {}) do
			table.insert(lines, L"N|" .. CorksBuffRestore.AsWString(text))
		end
		for _, text in ipairs(type(d.ToolTipWStringVector) == "table" and d.ToolTipWStringVector or {}) do
			table.insert(lines, L"P|" .. CorksBuffRestore.AsWString(text))
		end
	end
	return lines
end

function CorksBuffRestore.FromLines(lines)
	local snapshot = { buffs = {} }
	local current
	for _, line in ipairs(lines) do
		local tag = WStringToString(wstring.sub(line, 1, 2))
		if tag == "T|" then
			snapshot.time = tonumber(WStringToString(wstring.sub(line, 3)))
		elseif tag == "B|" then
			local id, hasTimer, seconds, good, abilityId = string.match(WStringToString(line),
				"^B|(%-?%d+)|(%d)|(%-?[%d%.]+)|(%d)|(%-?%d+)")
			if id then
				current = {
					id = tonumber(id),
					data = {
						abilityId = tonumber(abilityId),
						TimerSeconds = tonumber(seconds),
						HasTimer = hasTimer == "1",
						good = good == "1",
						IsBeingRemoved = false,
						NameWStringVector = {},
						ToolTipWStringVector = {},
						NameVectorSize = 0,
						ToolTipVectorSize = 0,
					},
				}
				table.insert(snapshot.buffs, current)
			else
				current = nil
			end
		elseif current and tag == "N|" then
			table.insert(current.data.NameWStringVector, wstring.sub(line, 3))
			current.data.NameVectorSize = #current.data.NameWStringVector
		elseif current and tag == "P|" then
			table.insert(current.data.ToolTipWStringVector, wstring.sub(line, 3))
			current.data.ToolTipVectorSize = #current.data.ToolTipWStringVector
		end
	end
	return snapshot
end

-- Writes the lines to the text log and to the settings, then hands the
-- settings to the client so they're kept through the reload.
function CorksBuffRestore.WriteLines(lines)
	local log = CorksBuffRestore.STORE_LOG
	local ok, err = pcall(function()
		pcall(TextLogCreate, log, 500)
		TextLogSetEnabled(log, true)
		TextLogClear(log)
		pcall(TextLogAddFilterType, log, 1, L"")
		for _, line in ipairs(lines) do
			TextLogAddEntry(log, 1, line)
		end
	end)
	if not ok then
		CorksBuffRestore.Log("Save: text log failed: " .. tostring(err))
	end

	ok, err = pcall(function()
		local key = CorksBuffRestore.STORE_SETTING
		CorksBuffRestore.ClearSettings()
		for i, line in ipairs(lines) do
			Interface.SaveWString(key .. i, line)
		end
		Interface.SaveNumber(key .. "Count", #lines)
		UserSettingsChanged()
	end)
	if not ok then
		CorksBuffRestore.Log("Save: settings failed: " .. tostring(err))
	end
end

function CorksBuffRestore.ClearSettings()
	local key = CorksBuffRestore.STORE_SETTING
	local count = Interface.LoadNumber(key .. "Count", 0)
	for i = 1, count do
		Interface.DeleteSetting(key .. i)
	end
	Interface.DeleteSetting(key .. "Count")
end

-- The lines kept in the text log, or nil. The client's entry numbering may
-- start at 0 or 1, so both are tried.
function CorksBuffRestore.ReadLog()
	local log = CorksBuffRestore.STORE_LOG
	local ok, count = pcall(TextLogGetNumEntries, log)
	if not ok or type(count) ~= "number" or count <= 0 then
		return nil
	end
	local function entry(index)
		local got, _, _, text = pcall(TextLogGetEntry, log, index)
		if got and text then
			return text
		end
		return nil
	end
	local first = 0
	if not entry(0) then
		first = 1
	end
	local lines = {}
	for i = first, first + count - 1 do
		local text = entry(i)
		if text then
			table.insert(lines, text)
		end
	end
	pcall(TextLogClear, log)
	if #lines == 0 then
		return nil
	end
	return lines
end

function CorksBuffRestore.ReadSettings()
	local key = CorksBuffRestore.STORE_SETTING
	local count = Interface.LoadNumber(key .. "Count", 0)
	if count <= 0 then
		return nil
	end
	local lines = {}
	for i = 1, count do
		local text = Interface.LoadWString(key .. i, L"")
		if text ~= L"" then
			table.insert(lines, text)
		end
	end
	if #lines == 0 then
		return nil
	end
	return lines
end

-- Reads the snapshot once after the reload and removes it from both places,
-- so it's never used twice.
function CorksBuffRestore.ReadSnapshot()
	local lines, source = CorksBuffRestore.ReadLog(), "text log"
	local fromSettings = CorksBuffRestore.ReadSettings()
	if not lines then
		lines, source = fromSettings, "settings"
	end
	if fromSettings then
		CorksBuffRestore.ClearSettings()
	end
	if not lines then
		return nil, "nowhere"
	end
	return CorksBuffRestore.FromLines(lines), source
end

-- Called every frame from Interface.Update; does nothing unless a snapshot is waiting
function CorksBuffRestore.Update(timePassed)
	if not CorksBuffRestore.CheckedAfterLoad then
		CorksBuffRestore.CheckedAfterLoad = true
		local ok, snapshot, source = pcall(CorksBuffRestore.ReadSnapshot)
		if not ok then
			CorksBuffRestore.Log("After load: reading the snapshot failed: " .. tostring(snapshot))
		elseif snapshot then
			local ids = {}
			for _, buff in ipairs(snapshot.buffs) do
				table.insert(ids, CorksBuffRestore.Describe(buff.id, buff.data, buff.data.TimerSeconds))
			end
			CorksBuffRestore.Log("After load: snapshot found in " .. source .. ", " .. #snapshot.buffs .. " buff(s)")
			for _, text in ipairs(ids) do
				CorksBuffRestore.Log("  " .. text)
			end
			CorksBuffRestore.Pending = snapshot
		else
			CorksBuffRestore.Log("After load: no snapshot (nothing saved by /reloadui)")
		end
	end
	if not CorksBuffRestore.Pending then
		return
	end
	CorksBuffRestore.Wait = CorksBuffRestore.Wait + (timePassed or 0)
	if CorksBuffRestore.Wait < CorksBuffRestore.DELAY then
		return
	end
	if not (AdvancedBuff and DoesWindowNameExist(AdvancedBuff.WindowNameGood) and WindowData.BuffDataCSV) then
		return
	end
	-- One try only, so a problem can't repeat every frame
	local snapshot = CorksBuffRestore.Pending
	CorksBuffRestore.Pending = nil
	CorksBuffRestore.Restore(snapshot)
end

function CorksBuffRestore.Say(text)
	pcall(WindowUtils.ChatPrint, StringToWString(text), SystemData.ChatLogFilters.SYSTEM)
end

function CorksBuffRestore.Restore(snapshot)
	local elapsed = 0
	local now = CorksBuffRestore.Now()
	if now and snapshot.time then
		elapsed = math.max(0, now - snapshot.time)
	end
	CorksBuffRestore.Log("Restore: " .. #snapshot.buffs .. " saved, reload took " .. elapsed .. "s")
	if elapsed > CorksBuffRestore.MAX_AGE then
		CorksBuffRestore.Log("  snapshot too old, skipped")
		return
	end

	local system = WindowData.BuffDebuffSystem
	local originalId = system.CurrentBuffId
	-- CreateNewBuff reads the buff's ID from here; check it can be set
	system.CurrentBuffId = -1
	if system.CurrentBuffId ~= -1 then
		system.CurrentBuffId = originalId
		CorksBuffRestore.Log("  CurrentBuffId can't be set")
		CorksBuffRestore.Say("Buff icons could not be restored after the UI reload.")
		return
	end

	-- No "Blood Oath" or "Panic" splash for buffs that were already up
	local originalSplash = CenterScreenText.SendCenterScreenTexture
	CenterScreenText.SendCenterScreenTexture = function() end

	local restored = 0
	local ok, err = pcall(function()
		for _, buff in ipairs(snapshot.buffs) do
			local id = buff.id
			local data = buff.data
			local timeLeft = data.TimerSeconds
			if data.HasTimer and type(timeLeft) == "number" then
				timeLeft = math.floor(timeLeft - elapsed)
			end
			local expired = data.HasTimer and (type(timeLeft) ~= "number" or timeLeft <= 0)
			-- Skip buffs that ran out during the reload, and ones the server already re-sent
			if expired then
				CorksBuffRestore.Log("  skipped (expired) " .. CorksBuffRestore.Describe(id, data, timeLeft))
			elseif BuffDebuff.BuffWindowId[id] == true then
				CorksBuffRestore.Log("  skipped (already shown) " .. CorksBuffRestore.Describe(id, data, timeLeft))
			else
				CorksBuffRestore.Log("  restoring " .. CorksBuffRestore.Describe(id, data, timeLeft))
				data.TimerSeconds = timeLeft
				BuffDebuff.BuffData[id] = data
				-- Marks it as already active, so the "new buff" circle doesn't flash
				BuffDebuff.ActiveBuffs[id] = true
				system.CurrentBuffId = id
				local made, problem = pcall(BuffDebuff.CreateNewBuff)
				if made then
					restored = restored + 1
				else
					BuffDebuff.BuffData[id] = nil
					BuffDebuff.ActiveBuffs[id] = nil
					CorksBuffRestore.Log("    failed: " .. tostring(problem))
					CorksBuffRestore.Say("Buff icon " .. tostring(id) .. " could not be restored: " .. tostring(problem))
				end
			end
		end
	end)

	system.CurrentBuffId = originalId
	CenterScreenText.SendCenterScreenTexture = originalSplash
	CorksBuffRestore.Log("Restore done: " .. restored .. " restored" .. (ok and "" or (", error: " .. tostring(err))))
	if not ok then
		CorksBuffRestore.Say("Restoring buff icons failed: " .. tostring(err))
	elseif restored > 0 then
		CorksBuffRestore.Say("Restored " .. restored .. " buff icon(s) after the UI reload.")
	end
end
