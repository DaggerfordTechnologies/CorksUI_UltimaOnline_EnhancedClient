----------------------------------------------------------------
-- Corks' UOAM Players
--
-- Shows the other players of your UOAM group on the Atlas and radar, with a
-- tinted party icon and their name. The UOAM Bridge (Tools/UOAMBridge) relays
-- UOAM's link to its hub and writes the group's positions to
-- logs/CorksUOAMBridge.txt, which is read here every couple of seconds:
--
--   UOAM|<update number>
--   <facet>|<x>|<y>|<name>        one line per player
--
-- When the update number stops changing (the bridge or UOAM was closed), the
-- players are taken off the map.
----------------------------------------------------------------

CorksUOAMBridge = {}

CorksUOAMBridge.FILE = "./logs/CorksUOAMBridge.txt"
-- Seconds between reads of the file
CorksUOAMBridge.READ_EVERY = 2
-- Seconds without a new update before the players are taken off the map
CorksUOAMBridge.STALE_AFTER = 30
-- Waypoint IDs for the players. The map's own IDs are below 10000 (server
-- waypoints), 10001+ (built-in places) and 50001+ (tracking arrows).
CorksUOAMBridge.FIRST_ID = 40000
CorksUOAMBridge.MAX_PLAYERS = 200
-- The party member icon, tinted so UOAM players stand out from your party
CorksUOAMBridge.ICON = 100114
CorksUOAMBridge.ICON_SCALE = 0.6
CorksUOAMBridge.COLOR = { r = 90, g = 200, b = 255 }

-- { facet, x, y, name } for each player, as last read
CorksUOAMBridge.Players = {}
CorksUOAMBridge.Clock = 0
CorksUOAMBridge.NextRead = 0
CorksUOAMBridge.LastText = nil
CorksUOAMBridge.LastUpdate = nil
CorksUOAMBridge.LastUpdateAt = 0
-- The players as one string, to tell when they've changed
CorksUOAMBridge.Shown = ""

-- The file's text as { update = number, players = { {facet, x, y, name} } },
-- or nil when it isn't one of ours
function CorksUOAMBridge.Parse(text)
	if type(text) ~= "string" then
		return nil
	end
	local result = nil
	for line in string.gmatch(text, "[^\r\n]+") do
		if not result then
			local update = string.match(line, "^UOAM|(%d+)$")
			if not update then
				return nil
			end
			result = { update = tonumber(update), players = {} }
		else
			local facet, x, y, name = string.match(line, "^(%d+)|(%d+)|(%d+)|(.*)$")
			if facet and name ~= "" and #result.players < CorksUOAMBridge.MAX_PLAYERS then
				table.insert(result.players, { facet = tonumber(facet), x = tonumber(x), y = tonumber(y), name = name })
			end
		end
	end
	return result
end

-- The players as one string, for spotting changes
function CorksUOAMBridge.Describe(players)
	local parts = {}
	for i, p in ipairs(players) do
		parts[i] = p.facet .. "|" .. p.x .. "|" .. p.y .. "|" .. p.name
	end
	return table.concat(parts, "\n")
end

-- The player a waypoint ID belongs to, or nil
function CorksUOAMBridge.PlayerForId(id)
	if type(id) ~= "number" then
		return nil
	end
	return CorksUOAMBridge.Players[id - CorksUOAMBridge.FIRST_ID]
end

function CorksUOAMBridge.IsOurId(id)
	return type(id) == "number" and id > CorksUOAMBridge.FIRST_ID and id <= CorksUOAMBridge.FIRST_ID + CorksUOAMBridge.MAX_PLAYERS
end

-- The file's text, or nil when it can't be read
function CorksUOAMBridge.ReadFile()
	local ok, text = pcall(LoadTextFile, CorksUOAMBridge.FILE)
	if not ok or text == nil then
		return nil
	end
	if type(text) ~= "string" then
		text = WStringToString(text)
	end
	return text
end

-- Takes in a new read of the file (text may be nil) at time now. True when
-- the players to show have changed.
function CorksUOAMBridge.Take(text, now)
	local J = CorksUOAMBridge
	if text ~= J.LastText then
		J.LastText = text
		local data = J.Parse(text)
		if data then
			if data.update ~= J.LastUpdate then
				J.LastUpdate = data.update
				J.LastUpdateAt = now
			end
			J.Players = data.players
		else
			J.Players = {}
		end
	end
	if #J.Players > 0 and now - J.LastUpdateAt > J.STALE_AFTER then
		J.Players = {}
	end
	local shown = J.Describe(J.Players)
	if shown ~= J.Shown then
		J.Shown = shown
		return true
	end
	return false
end

-- Update loop (called from Interface.OnUpdate)
function CorksUOAMBridge.OnUpdate(timePassed)
	local J = CorksUOAMBridge
	J.Clock = J.Clock + (timePassed or 0)
	if J.Clock < J.NextRead then
		return
	end
	J.NextRead = J.Clock + J.READ_EVERY
	if J.Take(J.ReadFile(), J.Clock) then
		-- Redraw the map's icons on its next update
		MapCommon.ForcedUpdate = true
		MapCommon.WaypointsDirty = true
	end
end

----------------------------------------------------------------
-- Map icons
----------------------------------------------------------------

-- Adds the players to a map view (ATLAS or RADAR) the map has just redrawn
function CorksUOAMBridge.Draw(displayMode)
	local J = CorksUOAMBridge
	local info = MapCommon.WaypointViewInfo[displayMode]
	if not info or #J.Players == 0 then
		return
	end
	local parent = info.Parent
	if not DoesWindowNameExist(parent) then
		return
	end
	local facet = UOGetPhysicalRadarFacet()
	local visible = info.VisibleFunc
	for i, p in ipairs(J.Players) do
		if p.facet == facet and (visible == nil or visible(2, p.x, p.y)) then
			local id = J.FIRST_ID + i
			local windowName = "Waypoint" .. id .. displayMode
			if DoesWindowNameExist(windowName) then
				DestroyWindow(windowName)
			end
			CreateWindowFromTemplate(windowName, "WaypointIconTemplate", parent)
			-- Listed with the map's own icons, so its next redraw removes it
			info.Windows[id] = windowName
			WindowSetId(windowName, id)
			MapCommon.WaypointsIconScale[id] = J.ICON_SCALE
			local mapX, mapY = UOGetWorldPosToRadar(p.x, p.y)
			WindowClearAnchors(windowName)
			WindowAddAnchor(windowName, "topleft", parent, "center", mapX, mapY)
			MapCommon.UpdateWaypointIcon(J.ICON, windowName, displayMode, id, J.COLOR)

			CreateWindowFromTemplate(windowName .. "Text", "WPText", windowName)
			WindowAddAnchor(windowName .. "Text", "top", windowName, "bottom", 0, -10)
			LabelSetText(windowName .. "Text", StringToWString(p.name))
			LabelSetTextColor(windowName .. "Text", J.COLOR.r, J.COLOR.g, J.COLOR.b)
		end
	end
end

-- Hover over a UOAM player: their name and location, like the map's own icons
function CorksUOAMBridge.ShowInfo(id, p)
	if DoesWindowExist("WaypointInfo") then
		DestroyWindow("WaypointInfo")
	end
	MapCommon.WaypointIsMouseOver = true
	local windowName = "Waypoint" .. id .. MapCommon.ActiveView
	CreateWindowFromTemplate("WaypointInfo", "WaypointInfoTemplate", "Root")
	WindowClearAnchors("WaypointInfo")
	WindowAddAnchor("WaypointInfo", "center", windowName, "bottomleft", 0, 0)
	LabelSetText("WaypointInfoDetails", StringToWString(p.name) .. L" (UOAM)")
	local latStr, longStr, latDir, longDir = MapCommon.GetSextantLocationStrings(p.x, p.y, p.facet)
	LabelSetText("WaypointInfoLocation", latStr .. L"'" .. latDir .. L" " .. longStr .. L"'" .. longDir .. L"\n" .. p.x .. L", " .. p.y)
	local w1, h1 = LabelGetTextDimensions("WaypointInfoDetails")
	local w2, h2 = LabelGetTextDimensions("WaypointInfoLocation")
	WindowSetDimensions("WaypointInfo", math.max(w1, w2) + 6, h1 + h2 + 9)
end

-- Adds the players after each map redraw, and handles hovering and
-- right-clicking them (the map's own handlers would look them up as server
-- waypoints and fail). Called once at startup, after MapCommon has loaded.
function CorksUOAMBridge.InstallMapHook()
	if CorksUOAMBridge.Hooked then
		return
	end
	CorksUOAMBridge.Hooked = true

	local updateWaypoints = MapCommon.UpdateWaypoints
	MapCommon.UpdateWaypoints = function(displayMode)
		updateWaypoints(displayMode)
		-- It sets WaypointUpdateRequest when it put the redraw off
		if displayMode and not MapCommon.WaypointUpdateRequest then
			local ok, err = pcall(CorksUOAMBridge.Draw, displayMode)
			if not ok then
				Debug.Print("CorksUOAMBridge.Draw: " .. tostring(err))
			end
		end
	end

	local mouseOver = MapCommon.WaypointMouseOver
	MapCommon.WaypointMouseOver = function()
		local id = WindowGetId(SystemData.ActiveWindow.name)
		if CorksUOAMBridge.IsOurId(id) then
			local p = CorksUOAMBridge.PlayerForId(id)
			if p and MapCommon.ActiveView ~= nil then
				CorksUOAMBridge.ShowInfo(id, p)
			end
			return
		end
		return mouseOver()
	end

	local rightClick = MapCommon.WaypointOnRButtonUp
	MapCommon.WaypointOnRButtonUp = function(...)
		if CorksUOAMBridge.IsOurId(WindowGetId(SystemData.ActiveWindow.name)) then
			return
		end
		return rightClick(...)
	end
end
