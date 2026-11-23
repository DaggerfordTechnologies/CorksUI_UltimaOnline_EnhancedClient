----------------------------------------------------------------
-- Corks' Alerts
----------------------------------------------------------------
-- Flashes a graphic in the middle of the screen when certain game messages
-- arrive (revealed, death strike, a stealther bumped you, an eruption...), and
-- lets each one be turned on or off, along with the alerts the default UI
-- already shows (webbed, server going down, artifact drops...).
--
-- The graphics use the default UI's CenterScreenTextImage window, the same one
-- the stock alerts and the Gear Watcher's Repair popup use. The new ones are in
-- Textures/cst_Corks*.dds, made by Tools/AlertTextures/make_alert_textures.py.
--
-- Stock alerts are switched off by wrapping CenterScreenText.SendCenterScreenTexture
-- (InstallHook). Alerts the stock UI doesn't have are matched in OnChatText,
-- which Interface.OnChatText calls after the stock TextParsing.CenterScreenText.

CorksAlerts = {}

-- Corks graphics: texture name and its size in pixels
CorksAlerts.TEXTURES = {
	calmed       = { "CST_CorksCalmed",       270, 84 },
	stripped     = { "CST_CorksStripped",     328, 84 },
	deathstrike  = { "CST_CorksDeathStrike",  356, 84 },
	revealed     = { "CST_CorksRevealed",     272, 84 },
	hitsplinter  = { "CST_CorksHitSplinter",  584, 84 },
	hitdisarm    = { "CST_CorksHitDisarm",    566, 84 },
	hiddenobject = { "CST_CorksHiddenObject", 482, 84 },
	stealther    = { "CST_CorksStealther",    346, 84 },
	meteor       = { "CST_CorksMeteor",       234, 84 },
	eruption     = { "CST_CorksEruption",     278, 84 },
	lavarock     = { "CST_CorksLavaRock",     302, 84 },
	ambush       = { "CST_CorksAmbush",       252, 84 },
	treat        = { "CST_CorksTreat",        226, 84 },
	cargo        = { "CST_CorksCargo",        434, 84 },
	krampus      = { "CST_CorksKrampus",      350, 84 },
	luckrunout   = { "CST_CorksLuckRanOut",   462, 84 },
	petals       = { "CST_CorksPetals",       534, 84 },
}

-- Sounds played with some alerts: { male, female } sound IDs, as the stock alerts use
CorksAlerts.SOUND_REWARD = { 1097, 823 }
CorksAlerts.SOUND_ALARM = { 1088, 814 }

-- The rows of the window, in order. Fields:
--   header   a group title row (no check box)
--   key      saved as the setting "CorksAlert" .. key
--   label    text in the window
--   stock    the default UI's own alert name. The default UI shows it by itself;
--            turning the row off stops it. Rows with ids/texts also show it for
--            those messages.
--   stockIds messages the default UI shows its "artifact" graphic for. Turning the
--            row off stops it for these messages only.
--   show     a Corks graphic (CorksAlerts.TEXTURES) to show for ids/texts
--   ids      game message numbers (cliloc) that show this alert
--   texts    lower-case text that shows this alert when a game message contains it
--   artifact the alert is the artifact graphic (Event Tracker checks these)
--   fromTarget only when the message comes from your last target
--   default  on or off before the player changes it (on if not given)
--   sound    { male, female } sound to play with it
CorksAlerts.List = {
	{ header = L"Things done to you" },
	{ key = "free",        label = L"You can move again",    stock = "free", ids = { 1111642 } },  -- "You manage to untangle yourself."
	{ key = "webbed",      label = L"Webbed",                stock = "webbed" },
	{ key = "stoned",      label = L"Turned to stone",       stock = "stoned" },
	{ key = "slowed",      label = L"Slowed",                stock = "slowed" },
	{ key = "panic",       label = L"Panic",                 stock = "panic" },
	{ key = "disarmed",    label = L"You are disarmed",      stock = "disarmed" },
	{ key = "calmed",      label = L"Calmed",                show = "calmed",
		ids = { 1072065, 500616 } },  -- dryad's beauty / lovely music: you forget to keep battling
	{ key = "stripped",    label = L"Stripped",              show = "stripped",
		ids = { 1072197, 1072196, 1150803 } },  -- "...your clothing is too confining." / "You begin to take off your clothing."
	{ key = "deathstrike", label = L"Hit by Death Strike",   show = "deathstrike", ids = { 1063093 } },
	{ key = "revealed",    label = L"Revealed",              show = "revealed",
		ids = { 1042873, 500816, 500814 } },  -- "You have been revealed!"
	{ key = "bloodoath",   label = L"Blood Oath on you",     stock = "bloodoath" },
	{ key = "honorwearoff", label = L"Honor wears off",      stock = "honorwearoff" },

	{ header = L"Your attacks" },
	{ key = "hitsplinter", label = L"Target splintered",     show = "hitsplinter", ids = { 1113077 } },  -- "A shard of your blade breaks off..."
	{ key = "hitdisarm",   label = L"Target disarmed",       show = "hitdisarm",   ids = { 1060092 } },  -- "You disarm their weapon!"

	{ header = L"Nearby" },
	{ key = "hiddenobject", label = L"Something hidden nearby", show = "hiddenobject", ids = { 1153493 } },  -- "Your keen senses detect something hidden..."
	{ key = "stealther",   label = L"Bumped a stealther",    show = "stealther",   ids = { 1019043 } },  -- "...you shove something invisible out of the way."
	{ key = "meteor",      label = L"Meteor",                show = "meteor",
		ids = { 1112362 }, texts = { "you will burn to a pile of ash!" } },
	{ key = "ambush",      label = L"Trade route ambush",    show = "ambush",      ids = { 1155479 } },

	{ header = L"Loot" },
	{ key = "virtueartifact", label = L"Artifact for valor",  artifact = true, stockIds = { 1062317 } },
	{ key = "specialgift", label = L"Special gift",           artifact = true, stockIds = { 502088 } },
	{ key = "minaxartifact", label = L"Minax artifact",       artifact = true, stockIds = { 1154530, 1154554 } },
	{ key = "fellowship",  label = L"Fellowship artifact",    artifact = true, stock = "artifact", ids = { 1159318 } },
	{ key = "dynamic",     label = L"Cult and lost kingdom treasure", artifact = true, stock = "artifact",
		ids = { 1158673 },
		texts = {
			"you discover equipment bearing the crest of a long lost kingdom",
			"you discover an artifact",
			"you discover a piece of equipment",
		} },
	{ key = "reward",      label = L"Reward put in your backpack", artifact = true, stock = "artifact",
		ids = { 1152339, 1153440, 1072223 } },  -- "A reward of ~1_ITEM~..." / "An artifact has been placed..." / "An item has been placed..."
	{ key = "treat",       label = L"Trick or treat",         show = "treat", ids = { 1076776 }, fromTarget = true,
		sound = CorksAlerts.SOUND_REWARD },  -- "Want something really special? Of course you do!"
	{ key = "cargo",       label = L"Cargo crate",            show = "cargo",
		ids = { 1158907 }, texts = { "you recover maritime trade cargo!" }, sound = CorksAlerts.SOUND_REWARD },
	{ key = "lavarock",    label = L"Lava rock",              show = "lavarock", ids = { 1156507 } },

	{ header = L"Events" },
	{ key = "voidbegins",  label = L"Void Pool battle begins", stock = "battlebegin" },
	{ key = "voidlost",    label = L"Void Pool battle lost",   stock = "battlelost" },
	{ key = "vvv",         label = L"Vice vs Virtue battle",   stock = "battlebegin", ids = { 1154721 }, default = false },
	{ key = "beacon",      label = L"Minax's Beacon vulnerable", stock = "beacon" },
	{ key = "eruption",    label = L"Volcano eruption",        show = "eruption", ids = { 1156506 } },
	{ key = "krampus",     label = L"Krampus spotted",         show = "krampus", ids = { 1158790, 1158832 },
		sound = CorksAlerts.SOUND_ALARM },

	{ header = L"Items" },
	{ key = "gorgon",      label = L"Gorgon lenses crumble",   stock = "gorgon" },
	{ key = "machete",     label = L"Bone machete snaps",      stock = "machete" },
	{ key = "luckrunout",  label = L"Luck ran out",            show = "luckrunout", ids = { 1079552 } },
	{ key = "petals",      label = L"Orange petals wore off",  show = "petals",
		ids = { 1053091 }, texts = { "you feel the effects of your poison resistance wearing off" } },
	{ key = "backpackfull", label = L"Container full",         stock = "backpackfull" },

	{ header = L"Server" },
	{ key = "serverdown",  label = L"Server going down",       stock = "serverdown" },
	{ key = "gmarrived",   label = L"A GM is talking to you",  stock = "gmarrived" },
}

-- Rows defined in CorksAlerts.xml; keep in sync
CorksAlerts.MAX_ROWS = 50
CorksAlerts.ROW_HEIGHT = 24
CorksAlerts.ROW_WIDTH = 300

-- Built by Build: lookups from a stock alert name or message number to its row
CorksAlerts.ByStock = {}      -- stock name -> row whose switch controls it (not "artifact")
CorksAlerts.ByStockId = {}    -- message number -> row (stock artifact messages)
CorksAlerts.ById = {}         -- message number -> list of rows
CorksAlerts.TextRows = {}     -- rows with texts
CorksAlerts.Built = false

CorksAlerts.On = {}           -- key -> true/false
CorksAlerts.Loaded = false
CorksAlerts.Original = nil    -- the default UI's SendCenterScreenTexture
CorksAlerts.Dirty = false
CorksAlerts.Initialized = false

----------------------------------------------------------------
-- Settings
----------------------------------------------------------------

function CorksAlerts.Build()
	if CorksAlerts.Built then
		return
	end
	for _, row in ipairs(CorksAlerts.List) do
		if row.key then
			-- The row that only turns a stock alert off owns that stock name. A row
			-- that shows a stock graphic for its own messages (VvV, untangle) doesn't.
			if row.stock and row.stock ~= "artifact" and not row.ids then
				CorksAlerts.ByStock[row.stock] = row
			end
			if row.stockIds then
				for _, id in ipairs(row.stockIds) do
					CorksAlerts.ByStockId[id] = row
				end
			end
			if row.ids then
				for _, id in ipairs(row.ids) do
					CorksAlerts.ById[id] = CorksAlerts.ById[id] or {}
					table.insert(CorksAlerts.ById[id], row)
				end
			end
			if row.texts then
				table.insert(CorksAlerts.TextRows, row)
			end
		end
	end
	-- "free" is shown by the stock UI for "You can move again" and by this row for
	-- untangling, so the same switch controls both.
	CorksAlerts.ByStock["free"] = CorksAlerts.RowByKey("free")
	CorksAlerts.Built = true
end

function CorksAlerts.RowByKey(key)
	for _, row in ipairs(CorksAlerts.List) do
		if row.key == key then
			return row
		end
	end
end

function CorksAlerts.Load()
	if CorksAlerts.Loaded then
		return
	end
	CorksAlerts.Build()
	for _, row in ipairs(CorksAlerts.List) do
		if row.key then
			CorksAlerts.On[row.key] = Interface.LoadBoolean("CorksAlert" .. row.key, row.default ~= false)
		end
	end
	CorksAlerts.Loaded = true
end

function CorksAlerts.IsOn(row)
	CorksAlerts.Load()
	return CorksAlerts.On[row.key] == true
end

function CorksAlerts.SetOn(row, on)
	CorksAlerts.On[row.key] = on
	Interface.SaveBoolean("CorksAlert" .. row.key, on)
end

----------------------------------------------------------------
-- Showing alerts
----------------------------------------------------------------

-- Stops the stock alerts whose row is turned off. Runs once; Interface.lua calls it.
function CorksAlerts.InstallHook()
	if CorksAlerts.Original or not CenterScreenText or type(CenterScreenText.SendCenterScreenTexture) ~= "function" then
		return
	end
	CorksAlerts.Original = CenterScreenText.SendCenterScreenTexture
	CenterScreenText.SendCenterScreenTexture = function(message, ...)
		local ok, allowed = pcall(CorksAlerts.StockAllowed, message)
		if ok and allowed == false then
			return
		end
		return CorksAlerts.Original(message, ...)
	end
end

function CorksAlerts.StockAllowed(message)
	CorksAlerts.Load()
	local row
	if message == "artifact" then
		row = CorksAlerts.ByStockId[SystemData.TextID]
	else
		row = CorksAlerts.ByStock[message]
	end
	if row then
		return CorksAlerts.IsOn(row)
	end
	return true
end

-- Shows a stock alert whether or not its row is on (previews, Event Tracker)
function CorksAlerts.ShowStock(message)
	local send = CorksAlerts.Original or CenterScreenText.SendCenterScreenTexture
	send(message)
end

function CorksAlerts.ShowTexture(name)
	local texture = CorksAlerts.TEXTURES[name]
	if not texture then
		return
	end
	local image = "CenterScreenTextImage"
	DynamicImageSetTexture(image, texture[1], 0, 0)
	DynamicImageSetTextureDimensions(image, texture[2], texture[3])
	WindowSetDimensions(image, texture[2], texture[3])
	WindowStopAlphaAnimation(image)
	WindowSetAlpha(image, 0)
	WindowStartAlphaAnimation(image, Window.AnimationType.LOOP, 0.5, 1, 1, false, 0, 3)
	-- The stock alerts do this so a Low Life warning starts flashing again afterwards
	CenterScreenText.LOWHPMEStarted = false
	CenterScreenText.LOWHPPetStarted = false
end

function CorksAlerts.PlaySound(sound)
	local female = false
	pcall(function()
		local data = Interface.GetMobileData(WindowData.PlayerStatus.PlayerId)
		female = data ~= nil and data.Gender == 1
	end)
	local id = sound[1]
	if female and sound[2] then
		id = sound[2]
	end
	local where = WindowData.PlayerLocation
	PlaySound(1, id, where.x, where.y, where.z)
end

-- Shows a row's alert, on or off
function CorksAlerts.Show(row)
	if row.show then
		CorksAlerts.ShowTexture(row.show)
	elseif row.stock then
		CorksAlerts.ShowStock(row.stock)
	elseif row.artifact then
		CorksAlerts.ShowStock("artifact")
	end
	if row.sound then
		pcall(CorksAlerts.PlaySound, row.sound)
	end
end

----------------------------------------------------------------
-- Game messages
----------------------------------------------------------------

-- Some game messages arrive on other channels than SYSTEM, but they all carry a
-- TextID; text players type never does.
function CorksAlerts.IsGameMessage()
	return SystemData.TextChannelID == SystemData.ChatLogFilters.SYSTEM
		or (SystemData.TextID ~= nil and SystemData.TextID ~= 0)
end

-- The rows (with ids or texts) the current message shows, on or off
function CorksAlerts.Matches()
	CorksAlerts.Load()
	local found = {}
	if not SystemData.Text or not CorksAlerts.IsGameMessage() then
		return found
	end
	local rows = CorksAlerts.ById[SystemData.TextID]
	if rows then
		for _, row in ipairs(rows) do
			found[row] = true
		end
	end
	if table.getn(CorksAlerts.TextRows) > 0 then
		local text = string.lower(WStringToString(SystemData.Text))
		for _, row in ipairs(CorksAlerts.TextRows) do
			for _, part in ipairs(row.texts) do
				if string.find(text, part, 1, true) then
					found[row] = true
					break
				end
			end
		end
	end
	return found
end

function CorksAlerts.OnChatText()
	for row in pairs(CorksAlerts.Matches()) do
		local show = CorksAlerts.IsOn(row)
		if row.fromTarget and SystemData.TextSourceID ~= Interface.LastTarget then
			show = false
		end
		-- Same as the stock "You can move again": not while still paralyzed
		if row.key == "free" and BuffDebuff and BuffDebuff.Timers and BuffDebuff.Timers[10037] then
			show = false
		end
		if show then
			CorksAlerts.Show(row)
			return
		end
	end
end

-- True when the current message already shows the artifact graphic through an
-- alert that's turned on. Event Tracker shows it itself otherwise.
function CorksAlerts.CoversArtifact()
	CorksAlerts.Load()
	local row = CorksAlerts.ByStockId[SystemData.TextID]
	if row and CorksAlerts.IsOn(row) then
		return true
	end
	for match in pairs(CorksAlerts.Matches()) do
		if match.artifact and CorksAlerts.IsOn(match) then
			return true
		end
	end
	return false
end

----------------------------------------------------------------
-- Window
----------------------------------------------------------------

function CorksAlerts.RowName(index)
	return "CorksAlertsListScrollChildRow" .. index
end

function CorksAlerts.Initialize()
	SnapUtils.SnappableWindows["CorksAlerts"] = true
	WindowUtils.RestoreWindowPosition("CorksAlerts", false)
	WindowUtils.LoadScale("CorksAlerts")
	WindowUtils.SetWindowTitle("CorksAlerts", L"Corks' Alerts")

	LabelSetTextColor("CorksAlertsHint", 200, 200, 200)
	LabelSetText("CorksAlertsHint", L"Check the alerts to show. Click a name to see it.")
	ButtonSetText("CorksAlertsAllOnButton", L"All On")
	ButtonSetText("CorksAlertsAllOffButton", L"All Off")

	for i = 1, CorksAlerts.MAX_ROWS do
		ButtonSetCheckButtonFlag(CorksAlerts.RowName(i) .. "Button", true)
	end

	CorksAlerts.Load()
	CorksAlerts.BuildRows()
	CorksAlerts.Initialized = true
end

function CorksAlerts.Shutdown()
	WindowUtils.SaveWindowPosition("CorksAlerts")
	CorksAlerts.SyncFromButtons()
end

function CorksAlerts.BuildRows()
	local total = table.getn(CorksAlerts.List)
	for i = 1, CorksAlerts.MAX_ROWS do
		local rowName = CorksAlerts.RowName(i)
		local row = CorksAlerts.List[i]
		WindowSetShowing(rowName, row ~= nil)
		if row then
			-- A label takes its color when its text is set, so set the color first
			if row.header then
				WindowSetShowing(rowName .. "Button", false)
				LabelSetTextColor(rowName .. "Label", 255, 200, 50)
				LabelSetText(rowName .. "Label", row.header)
				WindowClearAnchors(rowName .. "Label")
				WindowAddAnchor(rowName .. "Label", "left", rowName, "left", 5, 0)
			else
				WindowSetShowing(rowName .. "Button", true)
				ButtonSetPressedFlag(rowName .. "Button", CorksAlerts.IsOn(row))
				LabelSetTextColor(rowName .. "Label", 255, 255, 255)
				LabelSetText(rowName .. "Label", row.label)
			end
		end
	end
	WindowSetDimensions("CorksAlertsListScrollChild", CorksAlerts.ROW_WIDTH, math.max(total, 1) * CorksAlerts.ROW_HEIGHT)
	ScrollWindowUpdateScrollRect("CorksAlertsList")
end

-- A check button changes its own pressed flag, possibly after the click handler
-- runs, so clicks only mark the list dirty and OnUpdate reads the buttons next frame.
function CorksAlerts.SyncFromButtons()
	if not CorksAlerts.Initialized then
		return
	end
	for i, row in ipairs(CorksAlerts.List) do
		local button = CorksAlerts.RowName(i) .. "Button"
		if row.key and i <= CorksAlerts.MAX_ROWS and DoesWindowNameExist(button) then
			local on = ButtonGetPressedFlag(button)
			if on ~= CorksAlerts.IsOn(row) then
				CorksAlerts.SetOn(row, on)
			end
		end
	end
end

function CorksAlerts.SetAll(on)
	CorksAlerts.Load()
	for _, row in ipairs(CorksAlerts.List) do
		if row.key then
			CorksAlerts.SetOn(row, on)
		end
	end
	CorksAlerts.BuildRows()
end

function CorksAlerts.OnUpdate()
	if CorksAlerts.Dirty then
		CorksAlerts.Dirty = false
		CorksAlerts.SyncFromButtons()
	end
end

function CorksAlerts.OnRowButton()
	CorksAlerts.Dirty = true
end

-- Clicking an alert's name shows it, so the player can see what it looks like
function CorksAlerts.OnRowLabel()
	local rowName = WindowGetParent(SystemData.ActiveWindow.name)
	local index = tonumber(string.match(rowName, "Row(%d+)$"))
	local row = index and CorksAlerts.List[index]
	if row and row.key then
		CorksAlerts.Show(row)
	end
end

function CorksAlerts.OnAllOn()
	CorksAlerts.SetAll(true)
end

function CorksAlerts.OnAllOff()
	CorksAlerts.SetAll(false)
end

function CorksAlerts.Toggle()
	local open = DoesWindowNameExist("CorksAlerts") and WindowGetShowing("CorksAlerts")
	CorksAlerts.SetOpen(not open)
end

-- Right-click closes the window until the action opens it again
function CorksAlerts.OnClose()
	CorksAlerts.SetOpen(false)
end

function CorksAlerts.SetOpen(open)
	Interface.SaveBoolean("CorksAlertsOpen", open)
	if not DoesWindowNameExist("CorksAlerts") then
		if open then
			CreateWindow("CorksAlerts", true)
		end
		return
	end
	if not open then
		CorksAlerts.SyncFromButtons()
	end
	WindowSetShowing("CorksAlerts", open)
end
