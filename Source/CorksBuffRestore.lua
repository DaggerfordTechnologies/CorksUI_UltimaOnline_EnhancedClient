----------------------------------------------------------------
-- Keeps the buff/debuff icons through /reloadui.
--
-- The server only reports a buff when it starts or ends (and all of them at
-- login), and a UI reload throws away the icons and the default UI's list of
-- active buffs, so they'd be gone until the next login. /reloadui calls Save
-- just before reloading; the Lua globals survive the reload, and once the buff
-- bar exists again Update recreates each icon through the default UI's own
-- BuffDebuff.CreateNewBuff, with its timer reduced by the time the reload took.
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

-- Called by /reloadui just before the reload. The snapshot is kept in a global
-- that isn't set anywhere else, so it survives the reload.
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
	CorksBuffSnapshot = { time = CorksBuffRestore.Now(), buffs = buffs }
end

-- Called every frame from Interface.Update; does nothing unless a snapshot is waiting
function CorksBuffRestore.Update(timePassed)
	if not CorksBuffRestore.CheckedAfterLoad then
		CorksBuffRestore.CheckedAfterLoad = true
		CorksBuffRestore.Log("After load: snapshot " .. (CorksBuffSnapshot and "found" or "not found"))
	end
	if not CorksBuffSnapshot then
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
	local snapshot = CorksBuffSnapshot
	CorksBuffSnapshot = nil
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
