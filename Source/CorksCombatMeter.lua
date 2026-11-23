----------------------------------------------------------------
-- Corks' Combat Meter
----------------------------------------------------------------
-- Sums up each fight (damage dealt, damage per second, biggest hit, damage taken
-- by you and your pet, healing and absorbed damage), keeps the last few fights,
-- lists recent hits, and adjusts the overhead damage numbers: hides small ones,
-- makes big hits larger and shows your heals and absorbed damage over your head.
--
-- What the client sends (checked with /combatdump): each damage number comes with
-- only the mobile hit and the amount, never who dealt it. Hits by you, your pets
-- and your friends all arrive the same way, so "dealt" is your group's damage.
-- Hits on you and on your pet are reliable.
--
-- Data comes from three places:
--  * DamageWindow.Init, wrapped (InstallHook): every damage number. The stock
--    code still draws it; AfterDamage then hides or enlarges it.
--  * Your own hit points (OnUpdate): heals and regeneration, worked out from
--    hit point rises plus damage numbers not yet seen as a drop.
--  * Game message 1075127 (OnChatText): "~1_damage~ point(s) of damage have been
--    absorbed. A total of ~2_remaining~ point(s) of shielding remain."

CorksCombatMeter = {}

CorksCombatMeter.WINDOW = "CorksCombatMeter"
-- Size, as in the XML
CorksCombatMeter.WIDTH = 380
CorksCombatMeter.HEIGHT = 446

-- Same classic background as the Gear Watcher, or nil for the standard EC look
CorksCombatMeter.ClassicBackground = 2620
CorksCombatMeter.TitleOffsetY = 8
-- Gump art loaded for the classic background, released on shutdown
CorksCombatMeter.GumpArt = {}

-- A fight ends after this many seconds with no damage
CorksCombatMeter.FIGHT_GAP = 10
-- Finished fights kept; the window lists the fight in progress and these
CorksCombatMeter.MAX_FIGHTS = 3
CorksCombatMeter.MAX_RECENT = 50
-- How often the open window is redrawn
CorksCombatMeter.REFRESH_EVERY = 0.5
-- Damage numbers not yet seen as a hit point drop (and drops not yet matched to
-- a number) are forgotten after this many seconds
CorksCombatMeter.MATCH_TIME = 2
-- Big hits are drawn this much larger
CorksCombatMeter.BIG_SCALE = 1.5

-- Rows defined in CorksCombatMeter.xml; keep in sync
CorksCombatMeter.STAT_ROWS = 7
CorksCombatMeter.ENEMY_ROWS = 3
CorksCombatMeter.RECENT_ROWS = 4
CorksCombatMeter.FIGHT_ROWS = 3

CorksCombatMeter.COLOR = {
	dealt  = { 255, 220, 90 },
	you    = { 255, 90, 90 },
	pet    = { 230, 120, 255 },
	heal   = { 90, 255, 120 },
	regen  = { 160, 220, 160 },
	absorb = { 100, 180, 255 },
	gold   = { 255, 200, 50 },
	white  = { 255, 255, 255 },
	grey   = { 170, 170, 170 },
}

CorksCombatMeter.ABSORB_TID = 1075127

-- Settings: on/off switches and numbers with their limits
CorksCombatMeter.CHECKS = {
	{ row = "Numbers", key = "Numbers", text = "Hide small damage numbers and enlarge big hits" },
	{ row = "Heals",   key = "HealNumbers", text = "Show heals over your head" },
	{ row = "Absorbs", key = "AbsorbNumbers", text = "Show absorbed damage over your head" },
}
CorksCombatMeter.SLIDERS = {
	{ row = "MinDamage", key = "MinDamage", text = "Hide numbers below", min = 0, max = 50, default = 0, step = 1 },
	{ row = "BigHit",    key = "BigHit",    text = "Big hits from",      min = 0, max = 300, default = 0, step = 10 },
	{ row = "HealMin",   key = "HealMin",   text = "Heals from",         min = 1, max = 50, default = 5, step = 1 },
}
CorksCombatMeter.FILTERS = {
	{ row = "Dealt", key = "ShowDealt", text = "Dealt", color = "dealt" },
	{ row = "Taken", key = "ShowTaken", text = "Taken", color = "you" },
	{ row = "Pet",   key = "ShowPet",   text = "Pet",   color = "pet" },
	{ row = "Heals", key = "ShowHeals", text = "Heals", color = "heal" },
}

CorksCombatMeter.Settings = {}
CorksCombatMeter.Loaded = false

-- Fights: Current is the one in progress (or nil); Fights the finished ones, newest first
CorksCombatMeter.Current = nil
CorksCombatMeter.Fights = {}
CorksCombatMeter.Selected = nil   -- the fight shown, or nil for the newest
CorksCombatMeter.Recent = {}      -- newest first: { time, kind, amount, name }

-- Hit point tracking
CorksCombatMeter.LastHealth = nil
CorksCombatMeter.Pending = 0       -- damage on you not yet seen as a drop
CorksCombatMeter.Unexplained = 0   -- drops not yet matched to a damage number
CorksCombatMeter.MatchTime = 0

CorksCombatMeter.Hooked = false
CorksCombatMeter.RefreshClock = 0
CorksCombatMeter.Dirty = false
CorksCombatMeter.Syncing = false
CorksCombatMeter.ShowingSetup = false
CorksCombatMeter.Initialized = false

----------------------------------------------------------------
-- Settings
----------------------------------------------------------------

function CorksCombatMeter.Load()
	if CorksCombatMeter.Loaded then
		return
	end
	local S = CorksCombatMeter.Settings
	for _, check in ipairs(CorksCombatMeter.CHECKS) do
		S[check.key] = Interface.LoadBoolean("CorksCombatMeter" .. check.key, true)
	end
	for _, filter in ipairs(CorksCombatMeter.FILTERS) do
		S[filter.key] = Interface.LoadBoolean("CorksCombatMeter" .. filter.key, true)
	end
	for _, slider in ipairs(CorksCombatMeter.SLIDERS) do
		S[slider.key] = CorksCombatMeter.Clamp(slider, Interface.LoadNumber("CorksCombatMeter" .. slider.key, slider.default))
	end
	CorksCombatMeter.Loaded = true
end

function CorksCombatMeter.Get(key)
	CorksCombatMeter.Load()
	return CorksCombatMeter.Settings[key]
end

function CorksCombatMeter.Set(key, value)
	CorksCombatMeter.Load()
	CorksCombatMeter.Settings[key] = value
	if type(value) == "boolean" then
		Interface.SaveBoolean("CorksCombatMeter" .. key, value)
	else
		Interface.SaveNumber("CorksCombatMeter" .. key, value)
	end
end

function CorksCombatMeter.Clamp(slider, value)
	value = tonumber(value) or slider.default
	value = math.floor(value / slider.step + 0.5) * slider.step
	return math.max(slider.min, math.min(slider.max, value))
end

----------------------------------------------------------------
-- Text helpers
----------------------------------------------------------------

function CorksCombatMeter.Now()
	return Interface.TimeSinceLogin or 0
end

function CorksCombatMeter.ToText(value)
	if value == nil then
		return nil
	end
	if type(value) == "number" then
		return tostring(value)
	end
	local ok, text = pcall(WStringToString, value)
	if ok and type(text) == "string" then
		return text
	end
	if type(value) == "string" then
		return value
	end
	return nil
end

-- 12345 -> "12,345"
function CorksCombatMeter.Commas(number)
	local text = tostring(math.floor((number or 0) + 0.5))
	local result = text
	repeat
		local count
		result, count = string.gsub(result, "^(-?%d+)(%d%d%d)", "%1,%2")
	until count == 0
	return result
end

-- 83 -> "1:23"
function CorksCombatMeter.Duration(seconds)
	seconds = math.max(0, math.floor((seconds or 0) + 0.5))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

function CorksCombatMeter.Trim(text)
	return (string.gsub(text or "", "^%s*(.-)%s*$", "%1"))
end

function CorksCombatMeter.MobileName(mobileId)
	local data = WindowData.MobileName and WindowData.MobileName[mobileId]
	local name = data and CorksCombatMeter.ToText(data.MobName)
	name = CorksCombatMeter.Trim(name)
	if name == "" then
		return "Unknown"
	end
	return name
end

function CorksCombatMeter.PlayerId()
	return WindowData.PlayerStatus and WindowData.PlayerStatus.PlayerId
end

-- Who was hit, as the stock DamageWindow sorts it: "pet", "you" or "dealt"
function CorksCombatMeter.Group(mobileId)
	local isPet = false
	pcall(function()
		isPet = MobilesOnScreen.IsPet(mobileId) == true
	end)
	if isPet then
		return "pet"
	elseif mobileId == CorksCombatMeter.PlayerId() then
		return "you"
	end
	return "dealt"
end

----------------------------------------------------------------
-- Fights
----------------------------------------------------------------

function CorksCombatMeter.NewFight(now)
	return {
		start = now, last = now,
		dealt = 0, hits = 0, taken = 0, petTaken = 0,
		healed = 0, regen = 0, absorbed = 0,
		biggest = 0, biggestName = nil,
		enemies = {}, -- mobileId -> { name, total, hits }
	}
end

-- Ends the fight in progress if it has gone quiet
function CorksCombatMeter.CheckFightEnd(now)
	local fight = CorksCombatMeter.Current
	if fight and now - fight.last >= CorksCombatMeter.FIGHT_GAP then
		CorksCombatMeter.EndFight()
	end
end

function CorksCombatMeter.EndFight()
	local fight = CorksCombatMeter.Current
	if not fight then
		return
	end
	CorksCombatMeter.Current = nil
	table.insert(CorksCombatMeter.Fights, 1, fight)
	while table.getn(CorksCombatMeter.Fights) > CorksCombatMeter.MAX_FIGHTS do
		local dropped = table.remove(CorksCombatMeter.Fights)
		if CorksCombatMeter.Selected == dropped then
			CorksCombatMeter.Selected = nil
		end
	end
end

-- The fight in progress, started if there isn't one
function CorksCombatMeter.FightNow(now)
	CorksCombatMeter.CheckFightEnd(now)
	if not CorksCombatMeter.Current then
		CorksCombatMeter.Current = CorksCombatMeter.NewFight(now)
	end
	return CorksCombatMeter.Current
end

function CorksCombatMeter.AddRecent(kind, amount, name)
	table.insert(CorksCombatMeter.Recent, 1, { time = CorksCombatMeter.ClockText(), kind = kind, amount = amount, name = name })
	while table.getn(CorksCombatMeter.Recent) > CorksCombatMeter.MAX_RECENT do
		table.remove(CorksCombatMeter.Recent)
	end
end

-- The time of day as the client shows it, or the time since login
function CorksCombatMeter.ClockText()
	local clock = Interface.Clock
	if type(clock) == "table" and clock.h then
		return string.format("%02d:%02d:%02d", clock.h or 0, clock.m or 0, clock.s or 0)
	end
	return CorksCombatMeter.Duration(CorksCombatMeter.Now())
end

-- A damage number: who was hit and how much
function CorksCombatMeter.RecordDamage(mobileId, amount)
	local now = CorksCombatMeter.Now()
	local group = CorksCombatMeter.Group(mobileId)
	local fight = CorksCombatMeter.FightNow(now)
	fight.last = now
	local name = CorksCombatMeter.MobileName(mobileId)
	if group == "you" then
		fight.taken = fight.taken + amount
		CorksCombatMeter.DamageOnYou(amount, now)
	elseif group == "pet" then
		fight.petTaken = fight.petTaken + amount
	else
		fight.dealt = fight.dealt + amount
		fight.hits = fight.hits + 1
		local enemy = fight.enemies[mobileId]
		if not enemy then
			enemy = { name = name, total = 0, hits = 0 }
			fight.enemies[mobileId] = enemy
		end
		enemy.total = enemy.total + amount
		enemy.hits = enemy.hits + 1
		if amount > fight.biggest then
			fight.biggest = amount
			fight.biggestName = name
		end
	end
	CorksCombatMeter.AddRecent(group, amount, name)
	return group
end

-- A damage number on you: first explains a drop already seen, otherwise waits
-- for the drop
function CorksCombatMeter.DamageOnYou(amount, now)
	local M = CorksCombatMeter
	local matched = math.min(amount, M.Unexplained)
	M.Unexplained = M.Unexplained - matched
	M.Pending = M.Pending + (amount - matched)
	M.MatchTime = now
end

-- Healing worked out from your hit points
function CorksCombatMeter.RecordHeal(amount)
	local M = CorksCombatMeter
	local now = M.Now()
	M.CheckFightEnd(now)
	local isHeal = amount >= M.Get("HealMin")
	local fight = M.Current
	if fight then
		if isHeal then
			fight.healed = fight.healed + amount
		else
			fight.regen = fight.regen + amount
		end
	end
	if isHeal then
		M.AddRecent("heal", amount, nil)
		if M.Get("HealNumbers") then
			pcall(M.ShowOverPlayer, L"+" .. StringToWString(tostring(amount)), M.COLOR.heal)
		end
	end
end

function CorksCombatMeter.RecordAbsorb(amount)
	local M = CorksCombatMeter
	local now = M.Now()
	M.CheckFightEnd(now)
	if M.Current then
		M.Current.absorbed = M.Current.absorbed + amount
	end
	M.AddRecent("absorb", amount, nil)
	if M.Get("AbsorbNumbers") then
		pcall(M.ShowOverPlayer, L"(" .. StringToWString(tostring(amount)) .. L")", M.COLOR.absorb)
	end
end

-- Compares your hit points with last time. A rise is healing, plus any damage
-- number on you whose drop hasn't shown up (the two arrived in the same update).
function CorksCombatMeter.CheckHealth(now)
	local M = CorksCombatMeter
	local status = WindowData.PlayerStatus
	local health = status and status.CurrentHealth
	if health == nil then
		return
	end
	-- Before anything else, so a stale leftover can't be added to this change
	M.ForgetOldMatches(now)
	local last = M.LastHealth
	M.LastHealth = health
	if last == nil or last == health then
		return
	end
	-- Dying and being resurrected aren't healing
	if health == 0 or last == 0 then
		M.Pending, M.Unexplained = 0, 0
		return
	end
	local change = health - last
	if change < 0 then
		local drop = -change
		local matched = math.min(drop, M.Pending)
		M.Pending = M.Pending - matched
		M.Unexplained = M.Unexplained + (drop - matched)
		M.MatchTime = now
	else
		local healed = change + M.Pending
		M.Pending = 0
		M.RecordHeal(healed)
	end
end

function CorksCombatMeter.ForgetOldMatches(now)
	local M = CorksCombatMeter
	if (M.Pending > 0 or M.Unexplained > 0) and now - M.MatchTime > M.MATCH_TIME then
		M.Pending, M.Unexplained = 0, 0
	end
end

----------------------------------------------------------------
-- Overhead numbers
----------------------------------------------------------------

-- The stock number window just made for this mobile with this text, or nil
function CorksCombatMeter.FindNumberWindow(mobileId, text)
	local found
	for index, id in pairs(DamageWindow.AttachedId or {}) do
		if id == mobileId and DamageWindow.AnchorY[index] == DamageWindow.DefaultAnchorY then
			local label = "DamageWindow" .. index .. "Text"
			if DoesWindowNameExist(label) and LabelGetText(label) == text then
				if not found or index > found then
					found = index
				end
			end
		end
	end
	return found
end

-- After the stock code draws a damage number: hide it if small, enlarge if big
function CorksCombatMeter.AfterDamage(mobileId, amount)
	local M = CorksCombatMeter
	if not M.Get("Numbers") then
		return
	end
	local minDamage, bigHit = M.Get("MinDamage"), M.Get("BigHit")
	local hide = amount < minDamage
	local big = bigHit > 0 and amount >= bigHit
	if not hide and not big then
		return
	end
	local index = M.FindNumberWindow(mobileId, L"" .. amount)
	if not index then
		return
	end
	local windowName = "DamageWindow" .. index
	if hide then
		DestroyWindow(windowName)
		DamageWindow.AttachedId[index] = nil
		DamageWindow.AnchorY[index] = 0
	else
		WindowSetScale(windowName, WindowGetScale(windowName) * M.BIG_SCALE)
	end
end

-- Draws text over your head the way the stock code draws damage numbers
function CorksCombatMeter.ShowOverPlayer(text, color)
	local playerId = CorksCombatMeter.PlayerId()
	if not playerId then
		return
	end
	DamageWindow.AddText(playerId, text)
	local index = CorksCombatMeter.FindNumberWindow(playerId, text)
	if index then
		LabelSetTextColor("DamageWindow" .. index .. "Text", color[1], color[2], color[3])
	end
end

function CorksCombatMeter.InstallHook()
	if CorksCombatMeter.Hooked or not DamageWindow or type(DamageWindow.Init) ~= "function" then
		return
	end
	local original = DamageWindow.Init
	DamageWindow.Init = function(...)
		local mobileId, amount
		if type(Damage) == "table" then
			mobileId, amount = Damage.mobileId, tonumber(Damage.damageNumber)
		end
		if mobileId and amount then
			pcall(CorksCombatMeter.RecordDamage, mobileId, amount)
		end
		local result = original(...)
		if mobileId and amount then
			pcall(CorksCombatMeter.AfterDamage, mobileId, amount)
		end
		return result
	end
	CorksCombatMeter.Hooked = true
end

-- Absorbed damage, from the game message. The amount is the message's first
-- number; it's read from the text if the client gives no parameters.
function CorksCombatMeter.OnChatText()
	if SystemData.TextID ~= CorksCombatMeter.ABSORB_TID then
		return
	end
	local amount
	local tokens = SystemData.TextIDToks
	if type(tokens) == "table" and tokens[1] ~= nil then
		amount = tonumber(CorksCombatMeter.ToText(tokens[1]))
	end
	if not amount then
		local text = CorksCombatMeter.ToText(SystemData.Text) or ""
		amount = tonumber(string.match(text, "(%d+)"))
	end
	if amount and amount > 0 then
		CorksCombatMeter.RecordAbsorb(amount)
	end
end

function CorksCombatMeter.OnUpdate(timePassed)
	local M = CorksCombatMeter
	local now = M.Now()
	M.CheckHealth(now)
	M.CheckFightEnd(now)
	M.RefreshClock = M.RefreshClock + (timePassed or 0)
	if M.RefreshClock >= M.REFRESH_EVERY then
		M.RefreshClock = 0
		if M.Initialized and DoesWindowNameExist(M.WINDOW) and WindowGetShowing(M.WINDOW) and not M.ShowingSetup then
			M.Refresh()
		end
	end
end

----------------------------------------------------------------
-- Window: meter
----------------------------------------------------------------

-- The fights to list: the one in progress, then the finished ones
function CorksCombatMeter.FightList()
	local list = {}
	if CorksCombatMeter.Current then
		table.insert(list, CorksCombatMeter.Current)
	end
	for _, fight in ipairs(CorksCombatMeter.Fights) do
		table.insert(list, fight)
	end
	return list
end

function CorksCombatMeter.ShownFight()
	local list = CorksCombatMeter.FightList()
	for _, fight in ipairs(list) do
		if fight == CorksCombatMeter.Selected then
			return fight
		end
	end
	CorksCombatMeter.Selected = nil
	return list[1]
end

function CorksCombatMeter.FightLength(fight)
	return math.max(1, fight.last - fight.start)
end

function CorksCombatMeter.SetLabel(name, text, color)
	color = color or CorksCombatMeter.COLOR.white
	-- A label takes its color when its text is set, so set the color first
	LabelSetTextColor(name, color[1], color[2], color[3])
	LabelSetText(name, StringToWString(text))
end

-- The stat rows: { name, value, color }
function CorksCombatMeter.StatRows(fight)
	local M = CorksCombatMeter
	local C = M.COLOR
	if not fight then
		fight = M.NewFight(0)
	end
	local biggest = "-"
	if fight.biggest > 0 then
		biggest = M.Commas(fight.biggest) .. " on " .. (fight.biggestName or "Unknown")
	end
	-- 1-6 are shown in two columns (1 and 2 side by side, and so on), 7 across the window
	return {
		{ "Dealt",          M.Commas(fight.dealt), C.dealt },
		{ "Per second",     M.Commas(fight.dealt / M.FightLength(fight)), C.dealt },
		{ "Taken",          M.Commas(fight.taken), C.you },
		{ "Pet taken",      M.Commas(fight.petTaken), C.pet },
		{ "Healed / regen", M.Commas(fight.healed) .. " / " .. M.Commas(fight.regen), C.heal },
		{ "Absorbed",       M.Commas(fight.absorbed), C.absorb },
		{ "Biggest hit",    biggest, C.dealt },
	}
end

-- Enemies by damage dealt, most first
function CorksCombatMeter.EnemyRows(fight)
	local rows = {}
	if fight then
		for _, enemy in pairs(fight.enemies) do
			table.insert(rows, enemy)
		end
		table.sort(rows, function(a, b)
			if a.total ~= b.total then
				return a.total > b.total
			end
			return a.name < b.name
		end)
	end
	return rows
end

function CorksCombatMeter.RecentText(entry)
	local M = CorksCombatMeter
	local amount = M.Commas(entry.amount)
	if entry.kind == "dealt" then
		return entry.time .. "  " .. amount .. " on " .. (entry.name or "Unknown")
	elseif entry.kind == "you" then
		return entry.time .. "  " .. amount .. " taken"
	elseif entry.kind == "pet" then
		return entry.time .. "  " .. amount .. " on " .. (entry.name or "your pet")
	elseif entry.kind == "heal" then
		return entry.time .. "  +" .. amount .. " healed"
	elseif entry.kind == "absorb" then
		return entry.time .. "  " .. amount .. " absorbed"
	end
	return entry.time .. "  " .. amount
end

-- Recent entries that pass the filter check boxes
function CorksCombatMeter.RecentRows()
	local M = CorksCombatMeter
	local show = {
		dealt = M.Get("ShowDealt"),
		you = M.Get("ShowTaken"),
		pet = M.Get("ShowPet"),
		heal = M.Get("ShowHeals"),
		absorb = M.Get("ShowHeals"),
	}
	local rows = {}
	for _, entry in ipairs(M.Recent) do
		if show[entry.kind] then
			table.insert(rows, entry)
			if table.getn(rows) >= M.RECENT_ROWS then
				break
			end
		end
	end
	return rows
end

function CorksCombatMeter.FightTitle(fight)
	local M = CorksCombatMeter
	if not fight then
		return "No fights yet"
	end
	if fight == M.Current then
		return "Fight in progress: " .. M.Duration(M.Now() - fight.start)
	end
	return "Fight lasted " .. M.Duration(M.FightLength(fight)) .. ", ended " .. M.Duration(M.Now() - fight.last) .. " ago"
end

function CorksCombatMeter.Refresh()
	local M = CorksCombatMeter
	local C = M.COLOR
	local W = M.WINDOW
	local fight = M.ShownFight()

	M.SetLabel(W .. "FightLabel", M.FightTitle(fight), C.gold)

	local stats = M.StatRows(fight)
	for i = 1, M.STAT_ROWS do
		local stat = stats[i]
		M.SetLabel(W .. "Stat" .. i .. "Name", stat[1], stat[3])
		M.SetLabel(W .. "Stat" .. i .. "Value", stat[2], C.white)
	end

	local enemies = M.EnemyRows(fight)
	for i = 1, M.ENEMY_ROWS do
		local enemy = enemies[i]
		if enemy then
			M.SetLabel(W .. "Enemy" .. i .. "Name", enemy.name, C.white)
			M.SetLabel(W .. "Enemy" .. i .. "Value", M.Commas(enemy.total) .. " (" .. enemy.hits .. " hits)", C.dealt)
		else
			M.SetLabel(W .. "Enemy" .. i .. "Name", i == 1 and "None yet" or "", C.grey)
			M.SetLabel(W .. "Enemy" .. i .. "Value", "", C.white)
		end
	end

	local recent = M.RecentRows()
	for i = 1, M.RECENT_ROWS do
		local entry = recent[i]
		if entry then
			M.SetLabel(W .. "Recent" .. i, M.RecentText(entry), C[entry.kind] or C.white)
		else
			M.SetLabel(W .. "Recent" .. i, "", C.white)
		end
	end

	local fights = M.FightList()
	for i = 1, M.FIGHT_ROWS do
		local listed = fights[i]
		local name = W .. "Fight" .. i
		if listed then
			local when = (listed == M.Current) and "Now " or (M.Duration(M.FightLength(listed)) .. " ")
			local text = when .. "  " .. M.Commas(listed.dealt) .. " dealt, "
				.. M.Commas(listed.dealt / M.FightLength(listed)) .. "/s"
			M.SetLabel(name, text, listed == fight and C.gold or C.white)
		else
			M.SetLabel(name, "", C.white)
		end
	end
end

----------------------------------------------------------------
-- Window: setup
----------------------------------------------------------------

function CorksCombatMeter.SliderValueText(slider, value)
	if slider.key == "BigHit" and value == 0 then
		return "Off"
	elseif slider.key == "MinDamage" and value == 0 then
		return "Off"
	end
	return tostring(value)
end

function CorksCombatMeter.ShowSlider(slider)
	local M = CorksCombatMeter
	local row = M.WINDOW .. slider.row
	local value = M.Get(slider.key)
	M.Syncing = true
	pcall(SliderBarSetCurrentPosition, row .. "Slider", (value - slider.min) / (slider.max - slider.min))
	M.Syncing = false
	LabelSetText(row .. "Value", StringToWString(M.SliderValueText(slider, value)))
end

function CorksCombatMeter.RefreshSetup()
	local M = CorksCombatMeter
	for _, check in ipairs(M.CHECKS) do
		ButtonSetPressedFlag(M.WINDOW .. check.row .. "Button", M.Get(check.key))
	end
	for _, slider in ipairs(M.SLIDERS) do
		M.ShowSlider(slider)
	end
end

function CorksCombatMeter.ShowSetup(show)
	local M = CorksCombatMeter
	M.ShowingSetup = show
	WindowSetShowing(M.WINDOW .. "Meter", not show)
	WindowSetShowing(M.WINDOW .. "Setup", show)
	if show then
		LabelSetText(M.WINDOW .. "SetupLabel", L"Meter")
		M.RefreshSetup()
	else
		LabelSetText(M.WINDOW .. "SetupLabel", L"Setup")
		M.Refresh()
	end
end

-- Draws the classic background (protected, so a problem with the art can never
-- stop the meter working)
function CorksCombatMeter.ApplyClassicLook()
	local M = CorksCombatMeter
	if not M.ClassicBackground then
		return
	end
	local ok, err = pcall(function()
		if CorksGumpArt.ApplyClassic(M.WINDOW, M.ClassicBackground, M.WIDTH, M.HEIGHT, M.GumpArt) then
			CorksGumpArt.FinishClassic(M.WINDOW, M.TitleOffsetY)
		end
	end)
	if not ok then
		pcall(WindowUtils.ChatPrint, StringToWString("Combat Meter background: " .. tostring(err)), SystemData.ChatLogFilters.SYSTEM)
	end
end

-- The row a control belongs to: "CorksCombatMeterBigHitSlider" -> "BigHit"
function CorksCombatMeter.RowOf(windowName, suffix)
	return string.match(windowName or "", "^" .. CorksCombatMeter.WINDOW .. "(.-)" .. suffix .. "$")
end

----------------------------------------------------------------
-- Window: events
----------------------------------------------------------------

function CorksCombatMeter.Initialize()
	local M = CorksCombatMeter
	local W = M.WINDOW
	SnapUtils.SnappableWindows[W] = true
	WindowUtils.RestoreWindowPosition(W, false)
	WindowUtils.LoadScale(W)
	WindowUtils.SetWindowTitle(W, L"Corks' Combat Meter")

	local C = M.COLOR
	M.SetLabel(W .. "EnemiesHeading", "Enemies (damage dealt by you, your pets and friends)", C.gold)
	M.SetLabel(W .. "RecentHeading", "Recent", C.gold)
	M.SetLabel(W .. "FightsHeading", "Fights (click to show)", C.gold)
	M.SetLabel(W .. "SetupHeading", "Damage numbers over heads", C.gold)
	M.SetLabel(W .. "SetupNote", "Heals are worked out from your hit points, so they include potions, spells, bandages and leech. Smaller rises count as regeneration.", C.grey)
	LabelSetText(W .. "SetupLabel", L"Setup")
	LabelSetText(W .. "ResetLabel", L"Reset")

	M.Load()
	for _, filter in ipairs(M.FILTERS) do
		ButtonSetCheckButtonFlag(W .. "Filter" .. filter.row .. "Button", true)
		ButtonSetPressedFlag(W .. "Filter" .. filter.row .. "Button", M.Get(filter.key))
		M.SetLabel(W .. "Filter" .. filter.row .. "Label", filter.text, C[filter.color])
	end
	for _, check in ipairs(M.CHECKS) do
		ButtonSetCheckButtonFlag(W .. check.row .. "Button", true)
		M.SetLabel(W .. check.row .. "Label", check.text, C.white)
	end
	for _, slider in ipairs(M.SLIDERS) do
		M.SetLabel(W .. slider.row .. "Name", slider.text, C.white)
	end

	M.Initialized = true
	M.ShowSetup(false)
	M.ApplyClassicLook()
end

function CorksCombatMeter.Shutdown()
	WindowUtils.SaveWindowPosition(CorksCombatMeter.WINDOW)
	CorksGumpArt.ReleaseAll(CorksCombatMeter.GumpArt)
	CorksCombatMeter.Initialized = false
end

-- The Setup and Reset text is a label over each button, so it's coloured here:
-- pale gold while the mouse is over the button, white otherwise
function CorksCombatMeter.OnButtonOver()
	local label = string.gsub(SystemData.ActiveWindow.name, "Button$", "Label")
	LabelSetTextColor(label, 255, 220, 120)
	LabelSetText(label, LabelGetText(label))
end

function CorksCombatMeter.OnButtonOverEnd()
	local label = string.gsub(SystemData.ActiveWindow.name, "Button$", "Label")
	LabelSetTextColor(label, 255, 255, 255)
	LabelSetText(label, LabelGetText(label))
end

-- A check button changes its own pressed flag after the click handler, so clicks
-- are read on the window's next update
function CorksCombatMeter.OnWindowUpdate()
	local M = CorksCombatMeter
	if not M.Dirty then
		return
	end
	M.Dirty = false
	local W = M.WINDOW
	for _, filter in ipairs(M.FILTERS) do
		local on = ButtonGetPressedFlag(W .. "Filter" .. filter.row .. "Button")
		if on ~= M.Get(filter.key) then
			M.Set(filter.key, on)
		end
	end
	for _, check in ipairs(M.CHECKS) do
		local on = ButtonGetPressedFlag(W .. check.row .. "Button")
		if on ~= M.Get(check.key) then
			M.Set(check.key, on)
		end
	end
	if not M.ShowingSetup then
		M.Refresh()
	end
end

function CorksCombatMeter.OnCheckButton()
	CorksCombatMeter.Dirty = true
end

-- Clicking the text toggles its check box too
function CorksCombatMeter.OnCheckLabel()
	local button = string.gsub(SystemData.ActiveWindow.name, "Label$", "Button")
	ButtonSetPressedFlag(button, not ButtonGetPressedFlag(button))
	CorksCombatMeter.Dirty = true
end

function CorksCombatMeter.OnFightClick()
	local M = CorksCombatMeter
	local index = tonumber(string.match(SystemData.ActiveWindow.name, "Fight(%d+)$"))
	local fight = index and M.FightList()[index]
	if fight then
		M.Selected = fight
		M.Refresh()
	end
end

function CorksCombatMeter.OnSlide()
	local M = CorksCombatMeter
	if M.Syncing then
		return
	end
	local sliderName = SystemData.ActiveWindow.name
	local row = M.RowOf(sliderName, "Slider")
	for _, slider in ipairs(M.SLIDERS) do
		if slider.row == row then
			local position = SliderBarGetCurrentPosition(sliderName)
			local value = M.Clamp(slider, slider.min + position * (slider.max - slider.min))
			M.Set(slider.key, value)
			LabelSetText(M.WINDOW .. row .. "Value", StringToWString(M.SliderValueText(slider, value)))
			return
		end
	end
end

function CorksCombatMeter.StepSlider(suffix, direction)
	local M = CorksCombatMeter
	local row = M.RowOf(SystemData.ActiveWindow.name, suffix)
	for _, slider in ipairs(M.SLIDERS) do
		if slider.row == row then
			M.Set(slider.key, M.Clamp(slider, M.Get(slider.key) + direction * slider.step))
			M.ShowSlider(slider)
			return
		end
	end
end

function CorksCombatMeter.OnSliderMinus()
	CorksCombatMeter.StepSlider("Minus", -1)
end

function CorksCombatMeter.OnSliderPlus()
	CorksCombatMeter.StepSlider("Plus", 1)
end

function CorksCombatMeter.OnSetupButton()
	CorksCombatMeter.ShowSetup(not CorksCombatMeter.ShowingSetup)
end

-- Clears every fight and the recent list
function CorksCombatMeter.OnResetButton()
	local M = CorksCombatMeter
	M.Current = nil
	M.Fights = {}
	M.Selected = nil
	M.Recent = {}
	if not M.ShowingSetup then
		M.Refresh()
	end
end

function CorksCombatMeter.Toggle()
	local open = DoesWindowNameExist(CorksCombatMeter.WINDOW) and WindowGetShowing(CorksCombatMeter.WINDOW)
	CorksCombatMeter.SetOpen(not open)
end

-- Right-click closes the window until the action opens it again
function CorksCombatMeter.OnClose()
	CorksCombatMeter.SetOpen(false)
end

function CorksCombatMeter.SetOpen(open)
	local W = CorksCombatMeter.WINDOW
	Interface.SaveBoolean("CorksCombatMeterOpen", open)
	if not DoesWindowNameExist(W) then
		if open then
			CreateWindow(W, true)
		end
		return
	end
	WindowSetShowing(W, open)
	if open and not CorksCombatMeter.ShowingSetup then
		CorksCombatMeter.Refresh()
	end
end
