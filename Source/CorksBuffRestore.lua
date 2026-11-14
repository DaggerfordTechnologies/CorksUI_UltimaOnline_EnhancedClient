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
CorksBuffRestore.CheckedAfterLoad = false

-- Where the snapshot is kept through the reload
CorksBuffRestore.STORE_LOG = "CorksBuffSnapshot"
CorksBuffRestore.STORE_SETTING = "CorksBuffSnapshot"
-- The snapshot read back after the reload, waiting to be restored
CorksBuffRestore.Pending = nil

-- Seconds since some fixed point, or nil if the client can't say
function CorksBuffRestore.Now()
	local ok, timestamp = pcall(GetCurrentDateTime)
	if ok and type(timestamp) == "number" then
		return timestamp
	end
	return nil
end

function CorksBuffRestore.Say(text)
	pcall(WindowUtils.ChatPrint, StringToWString(text), SystemData.ChatLogFilters.SYSTEM)
end

-- Called by /reloadui just before the reload.
function CorksBuffRestore.Save()
	if not BuffDebuff or type(BuffDebuff.TableOrder) ~= "table" then
		return
	end
	local buffs = {}
	local done = {}
	for _, buffId in ipairs(BuffDebuff.TableOrder) do
		local data = BuffDebuff.BuffData[buffId]
		if not done[buffId] and BuffDebuff.BuffWindowId[buffId] == true and type(data) == "table" then
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
					good = data.good,
					NameWStringVector = data.NameWStringVector,
					ToolTipWStringVector = data.ToolTipWStringVector,
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
-- settings to the client so they're kept through the reload. Each is
-- protected, so one failing still leaves the other.
function CorksBuffRestore.WriteLines(lines)
	local log = CorksBuffRestore.STORE_LOG
	pcall(function()
		pcall(TextLogCreate, log, 500)
		TextLogSetEnabled(log, true)
		TextLogClear(log)
		pcall(TextLogAddFilterType, log, 1, L"")
		for _, line in ipairs(lines) do
			TextLogAddEntry(log, 1, line)
		end
	end)

	pcall(function()
		local key = CorksBuffRestore.STORE_SETTING
		CorksBuffRestore.ClearSettings()
		for i, line in ipairs(lines) do
			Interface.SaveWString(key .. i, line)
		end
		Interface.SaveNumber(key .. "Count", #lines)
		UserSettingsChanged()
	end)
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
	local lines = CorksBuffRestore.ReadLog()
	local fromSettings = CorksBuffRestore.ReadSettings()
	if fromSettings then
		CorksBuffRestore.ClearSettings()
	end
	lines = lines or fromSettings
	if not lines then
		return nil
	end
	return CorksBuffRestore.FromLines(lines)
end

-- Called every frame from Interface.Update; does nothing unless a snapshot is waiting
function CorksBuffRestore.Update(timePassed)
	if not CorksBuffRestore.CheckedAfterLoad then
		CorksBuffRestore.CheckedAfterLoad = true
		local ok, snapshot = pcall(CorksBuffRestore.ReadSnapshot)
		if ok then
			CorksBuffRestore.Pending = snapshot
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

function CorksBuffRestore.Restore(snapshot)
	local elapsed = 0
	local now = CorksBuffRestore.Now()
	if now and snapshot.time then
		elapsed = math.max(0, now - snapshot.time)
	end
	if elapsed > CorksBuffRestore.MAX_AGE then
		return
	end

	local system = WindowData.BuffDebuffSystem
	local originalId = system.CurrentBuffId
	-- CreateNewBuff reads the buff's ID from here; check it can be set
	system.CurrentBuffId = -1
	if system.CurrentBuffId ~= -1 then
		system.CurrentBuffId = originalId
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
			if not expired and BuffDebuff.BuffWindowId[id] ~= true then
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
					CorksBuffRestore.Say("Buff icon " .. tostring(id) .. " could not be restored: " .. tostring(problem))
				end
			end
		end
	end)

	system.CurrentBuffId = originalId
	CenterScreenText.SendCenterScreenTexture = originalSplash
	if not ok then
		CorksBuffRestore.Say("Restoring buff icons failed: " .. tostring(err))
	elseif restored > 0 then
		CorksBuffRestore.Say("Restored " .. restored .. " buff icon(s) after the UI reload.")
	end
end
