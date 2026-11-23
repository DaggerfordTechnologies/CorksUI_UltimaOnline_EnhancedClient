----------------------------------------------------------------
-- /combatdump: a temporary tool for seeing what the client sends for damage,
-- before building the Combat Meter. Type /combatdump in chat to start
-- recording and again to stop. While it records, every damage number and every
-- change to your own hit points is written to logs/CorksCombatDump.log in the
-- game folder. Stopping prints a short summary in chat.
--
-- Questions it should answer:
--  * Does the Damage table carry more than mobileId, damageNumber and a color
--    (who dealt it, a damage type)? Every field is written out.
--  * In a group fight, do other players' hits on a mob show up? Each line says
--    whether the mobile hit is your target and whether you're in war mode.
--  * Do your hit point changes line up with the damage numbers you take, and how
--    do heals show? HP lines are written as they change.
----------------------------------------------------------------

CorksCombatDump = {}

CorksCombatDump.LOG = "CorksCombatDump"
CorksCombatDump.LOG_FILE = "logs/CorksCombatDump.log"

CorksCombatDump.Recording = false
CorksCombatDump.Hooked = false
CorksCombatDump.StartTime = 0
CorksCombatDump.LastHealth = nil
CorksCombatDump.Counts = nil

-- Opens (or reopens, after a UI reload) the log file, emptied
function CorksCombatDump.StartLog()
	local log = CorksCombatDump.LOG
	-- A log left from before a UI reload writes nothing more to disk, so start fresh
	pcall(TextLogDestroy, log)
	pcall(TextLogCreate, log, 5000)
	TextLogSetEnabled(log, true)
	TextLogClear(log)
	TextLogSetIncrementalSaving(log, true, CorksCombatDump.LOG_FILE)
	pcall(TextLogAddFilterType, log, 1, L"")
end

function CorksCombatDump.Line(text)
	pcall(TextLogAddEntry, CorksCombatDump.LOG, 1, StringToWString(tostring(text)))
end

function CorksCombatDump.Chat(text)
	pcall(WindowUtils.ChatPrint, StringToWString(text), SystemData.ChatLogFilters.SYSTEM)
end

-- Any value as readable text, without failing on wstrings or tables
function CorksCombatDump.Show(value, depth)
	depth = depth or 0
	local kind = type(value)
	if kind == "wstring" or kind == "userdata" then
		local ok, text = pcall(WStringToString, value)
		if ok and text then
			return "\"" .. text .. "\""
		end
		return tostring(value)
	elseif kind == "string" then
		local ok, text = pcall(WStringToString, value)
		if ok and type(text) == "string" then
			return "\"" .. text .. "\""
		end
		return "\"" .. value .. "\""
	elseif kind == "table" then
		local parts = {}
		for k, v in pairs(value) do
			local item
			if type(v) == "table" and depth >= 1 then
				item = "{...}"
			else
				item = CorksCombatDump.Show(v, depth + 1)
			end
			table.insert(parts, tostring(k) .. "=" .. item)
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end

-- Seconds since recording started, to a tenth
function CorksCombatDump.Time()
	return string.format("%7.1f", (Interface.TimeSinceLogin or 0) - CorksCombatDump.StartTime)
end

function CorksCombatDump.PlayerId()
	return WindowData.PlayerStatus and WindowData.PlayerStatus.PlayerId
end

function CorksCombatDump.MobileName(mobileId)
	local data = WindowData.MobileName and WindowData.MobileName[mobileId]
	if data and data.MobName then
		return CorksCombatDump.Show(data.MobName)
	end
	return "?"
end

-- How the stock DamageWindow sorts a hit: "you" (you were hit), "pet" (your pet
-- was hit) or "dealt" (anything else, which the stock code counts as your damage)
function CorksCombatDump.StockGroup(mobileId)
	local isPet = false
	pcall(function()
		isPet = MobilesOnScreen.IsPet(mobileId) == true
	end)
	if isPet then
		return "pet"
	elseif mobileId == CorksCombatDump.PlayerId() then
		return "you"
	end
	return "dealt"
end

-- Called with the client's Damage table filled in, before the stock code draws it
function CorksCombatDump.OnDamage()
	if not CorksCombatDump.Recording or type(Damage) ~= "table" then
		return
	end
	local mobileId = Damage.mobileId
	local group = CorksCombatDump.StockGroup(mobileId)
	local counts = CorksCombatDump.Counts
	counts[group] = (counts[group] or 0) + 1
	counts.mobiles[mobileId] = true

	local target = WindowData.CurrentTarget and WindowData.CurrentTarget.TargetId
	local status = WindowData.PlayerStatus or {}
	CorksCombatDump.Line(CorksCombatDump.Time() .. " DAMAGE " .. tostring(Damage.damageNumber)
		.. " " .. group
		.. " mobile=" .. tostring(mobileId) .. " " .. CorksCombatDump.MobileName(mobileId)
		.. " isTarget=" .. tostring(mobileId == target)
		.. " isLastTarget=" .. tostring(mobileId == Interface.LastTarget)
		.. " warMode=" .. tostring(status.InWarMode)
		.. " myHP=" .. tostring(status.CurrentHealth) .. "/" .. tostring(status.MaxHealth))
	CorksCombatDump.Line("          Damage = " .. CorksCombatDump.Show(Damage))
	local mobile = WindowData.MobileName and WindowData.MobileName[mobileId]
	if mobile then
		CorksCombatDump.Line("          MobileName = " .. CorksCombatDump.Show(mobile))
	end
end

-- Writes a line whenever your own hit points change
function CorksCombatDump.OnUpdate()
	if not CorksCombatDump.Recording then
		return
	end
	local status = WindowData.PlayerStatus
	local health = status and status.CurrentHealth
	if health == nil or health == CorksCombatDump.LastHealth then
		return
	end
	if CorksCombatDump.LastHealth ~= nil then
		local change = health - CorksCombatDump.LastHealth
		local sign = ""
		if change > 0 then
			sign = "+"
			CorksCombatDump.Counts.healed = CorksCombatDump.Counts.healed + change
		end
		CorksCombatDump.Line(CorksCombatDump.Time() .. " MYHP " .. tostring(CorksCombatDump.LastHealth)
			.. " -> " .. tostring(health) .. " (" .. sign .. tostring(change) .. ")"
			.. " max=" .. tostring(status.MaxHealth))
	end
	CorksCombatDump.LastHealth = health
end

function CorksCombatDump.InstallHook()
	if CorksCombatDump.Hooked or not DamageWindow or type(DamageWindow.Init) ~= "function" then
		return
	end
	local original = DamageWindow.Init
	DamageWindow.Init = function(...)
		pcall(CorksCombatDump.OnDamage)
		return original(...)
	end
	CorksCombatDump.Hooked = true
end

function CorksCombatDump.Start()
	CorksCombatDump.InstallHook()
	CorksCombatDump.StartLog()
	CorksCombatDump.StartTime = Interface.TimeSinceLogin or 0
	CorksCombatDump.Counts = { mobiles = {}, healed = 0 }
	local status = WindowData.PlayerStatus or {}
	CorksCombatDump.LastHealth = status.CurrentHealth
	CorksCombatDump.Recording = true
	CorksCombatDump.Line("Corks combat dump. Player " .. tostring(status.PlayerId)
		.. " HP " .. tostring(status.CurrentHealth) .. "/" .. tostring(status.MaxHealth))
	CorksCombatDump.Line("Groups are how the stock DamageWindow sorts a hit: you = you were hit,"
		.. " pet = your pet was hit, dealt = anything else (counted as your damage).")
	CorksCombatDump.Chat("Combat dump: recording to " .. CorksCombatDump.LOG_FILE .. ". Type /combatdump again to stop.")
end

function CorksCombatDump.Stop()
	CorksCombatDump.Recording = false
	local counts = CorksCombatDump.Counts
	local mobiles = 0
	for _ in pairs(counts.mobiles) do
		mobiles = mobiles + 1
	end
	local summary = "Combat dump stopped: " .. tostring(counts.dealt or 0) .. " dealt, "
		.. tostring(counts.you or 0) .. " taken, " .. tostring(counts.pet or 0) .. " on your pet, "
		.. mobiles .. " mobiles, " .. tostring(counts.healed) .. " HP healed."
	CorksCombatDump.Line(summary)
	CorksCombatDump.Chat(summary .. " Saved in " .. CorksCombatDump.LOG_FILE .. ".")
end

function CorksCombatDump.Toggle()
	if CorksCombatDump.Recording then
		CorksCombatDump.Stop()
	else
		CorksCombatDump.Start()
	end
end
