----------------------------------------------------------------
-- Global Variables
----------------------------------------------------------------

MapWindow = {}

----------------------------------------------------------------
-- Local Variables
----------------------------------------------------------------

MapWindow.Big = false
MapWindow.ComboBCK = false

MapWindow.Rotation = 45
MapWindow.ZoomScale = 0.1
MapWindow.IsDragging = false
MapWindow.IsMouseOver = false
MapWindow.TypeEnabled = {}
MapWindow.LegendVisible = false
MapWindow.CenterOnPlayer = true
MapWindow.Tilt = false
MapWindow.IsNLS = false

MapWindow.WINDOW_WIDTH_MAX = 716
MapWindow.WINDOW_HEIGHT_MAX = 776
MapWindow.MAP_WIDTH_DIFFERENCE = 26
MapWindow.MAP_HEIGHT_DIFFERENCE = 111

MapWindow.LegendItemTextColors = { normal={r=255,g=255,b=255}, disabled={r=80,g=80,b=80} }

MapWindow.NLS_Only = {
	[1160692] = true; --Trinsic Flagship
	[1160693] = true; --Ancient Tomb
	[1160694] = true; --Library Cellar
	[1160695] = true; --Rat's Nest
	[1160696] = true; --Ocllo Crypt
	[1160713] = true; --A Mysterious Place
	[1160909] = true; --Secret Room
	[1160836] = true; --Ethereal Moonglow
	[1160973] = true; --Inferno Caverns
	[1160977] = true; --Shadow Reaver Lair
	[1160058] = true; --Guild Hunt
	[1160075] = true; --Dungeon Outpost
	[1161512] = true; --Ocllo Mines
	[1161354] = true; --Ironheart Depths
	[1162506] = true; --Netherpools
	[1162507] = true; --Hidden Library
	[1162238] = true; --Crimson Stronghold
	[1161962] = true; --Silken Ruins
	[1163435] = true; --Titanweave Spider Lair
	[1163010] = true; --Alchemist's Lab
	[1163120] = true; --Musical Purist Dungeon
	[1163121] = true; --The Conductor's Quarters
    [1164009] = true; -- The Manticore Passage
    [1164010] = true; -- Fiery Caves
    [1164011] = true; -- River of Ooze
    [1164012] = true; -- Magistrate's Lair
}

MapWindow.NLS_Exclude = {
    [1111759] = true;
    [1076026] = true;
    [1074806] = true;
    [1074805] = true;
    [1074807] = true;
    [1111755] = true;
    [1149576] = true;
    [1154337] = true;
}

MapWindow.Areas = {}
MapWindow.Facets = {}
MapWindow.AreaIndices = {}
MapWindow.CurrentFacet = 0
MapWindow.CurrentArea = 0
MapWindow.Locked = false

-----------------------------------------------------------------
-- MapCommon Helper Functions
-----------------------------------------------------------------

----------------------------------------------------------------
-- Event Functions
----------------------------------------------------------------

function MapWindow.Initialize()
	WindowUtils.RestoreWindowPosition("MapWindow", true)
	MapWindow.OnResizeEnd("MapWindow")

    -- Static text initialization
    WindowUtils.SetWindowTitle("MapWindow",GetStringFromTid(MapCommon.TID.Atlas))

    -- Update registration
    RegisterWindowData(WindowData.Radar.Type,0)
    RegisterWindowData(WindowData.WaypointDisplay.Type,0)
    RegisterWindowData(WindowData.WaypointList.Type,0)

    WindowRegisterEventHandler("MapWindow", WindowData.Radar.Event, "MapWindow.UpdateMap")
    WindowRegisterEventHandler("MapWindow", WindowData.WaypointList.Event, "MapWindow.UpdateWaypoints")

    local isVisible = WindowGetShowing("MapWindow")
    CreateWindow("LegendWindow",isVisible)

    MapWindow.IsNLS = IsConnectedToNLServer()
    MapWindow.CurrentFacet = WindowData.PlayerLocation.facet or 0
    MapWindow.CurrentArea = 0
    MapWindow.UpdateFacetCombo()
    ComboBoxSetSelectedMenuItem( "MapWindowFacetCombo", MapWindow.Facets[MapWindow.CurrentFacet] + 1 )

    LabelSetText("MapWindowTiltLabel", GetStringFromTid(1154867))
    ButtonSetCheckButtonFlag( "MapWindowTiltButton", true )
    ButtonSetPressedFlag( "MapWindowTiltButton", MapWindow.Tilt )

    LabelSetText("MapWindowCenterOnPlayerLabel", GetStringFromTid(1112059))
    ButtonSetCheckButtonFlag( "MapWindowCenterOnPlayerButton", true )
    ButtonSetPressedFlag( "MapWindowCenterOnPlayerButton", MapWindow.CenterOnPlayer )

    WindowSetScale("MapWindowCoordsText", 0.9 * InterfaceCore.scale)
    if (SystemData.Settings.Language.type ~= SystemData.Settings.Language.LANGUAGE_ENU) then
        WindowSetDimensions("MapWindowPlayerCoordsText", 250, 70)
    end
    WindowSetScale("MapWindowPlayerCoordsText", 0.9 * InterfaceCore.scale)
    WindowSetScale("MapWindowCenterOnPlayerButton", 0.9 * InterfaceCore.scale)
    WindowSetScale("MapWindowCenterOnPlayerLabel", 0.9 * InterfaceCore.scale)
    WindowSetScale("MapWindowTiltButton", 0.9 * InterfaceCore.scale)
    WindowSetScale("MapWindowTiltLabel", 0.9 * InterfaceCore.scale)

    local this = "MapWindow"
    local texture = "UO_Core"
    if ( MapWindow.Locked ) then
        ButtonSetTexture(this.."Lock", InterfaceCore.ButtonStates.STATE_NORMAL, texture, 69, 341)
        ButtonSetTexture(this.."Lock", InterfaceCore.ButtonStates.STATE_NORMAL_HIGHLITE, texture, 92, 341)
        ButtonSetTexture(this.."Lock", InterfaceCore.ButtonStates.STATE_PRESSED, texture, 92, 341)
        ButtonSetTexture(this.."Lock", InterfaceCore.ButtonStates.STATE_PRESSED_HIGHLITE, texture, 92, 341)
    else
        ButtonSetTexture(this.."Lock", InterfaceCore.ButtonStates.STATE_NORMAL, texture, 117, 341)
        ButtonSetTexture(this.."Lock", InterfaceCore.ButtonStates.STATE_NORMAL_HIGHLITE, texture, 142, 341)
        ButtonSetTexture(this.."Lock", InterfaceCore.ButtonStates.STATE_PRESSED, texture, 142, 341)
        ButtonSetTexture(this.."Lock", InterfaceCore.ButtonStates.STATE_PRESSED_HIGHLITE, texture, 142, 341)
    end
    WindowAddAnchor("MapWindowLock", "topright", "MapWindow", "topright", 0, -5)
    WindowSetShowing("MapWindowLegendToggle", false)
    MapWindow.PopulateMapLegend()
    SnapUtils.SnappableWindows["MapWindow"] = true
    WindowSetShowing("MapWindowToggleRadarButton", false)

    CreateWindowFromTemplate("MapCompass", "MapCompass", "MapWindow")
    DynamicImageSetTexture( "MapCompass", "CompassTexture", 0, 0 )
    local compassScale = 0.65
    local cx, cy = WindowGetDimensions( "MapCompass" )
    WindowSetDimensions("MapCompass", cx * compassScale, cy * compassScale)
    DynamicImageSetRotation( "MapCompass", WindowData.Radar.TexRotation )
    WindowSetAlpha("MapCompass", 1)
    WindowAddAnchor("MapCompass", "topright", "MapWindowPlayerCoordsText", "topright", 0, -(cy * compassScale))
end

function MapWindow.ToggleCombos(value)
    Interface.ShowMapCombos = value
    Interface.SaveBoolean( "ShowMapCombos", Interface.ShowMapCombos )
    WindowSetShowing("MapWindowFacetCombo", Interface.ShowMapCombos)
    WindowSetShowing("MapWindowFacetNextButton", Interface.ShowMapCombos)
    WindowSetShowing("MapWindowFacetPrevButton", Interface.ShowMapCombos)
    WindowSetShowing("MapWindowAreaCombo", Interface.ShowMapCombos)
    WindowSetShowing("MapWindowAreaNextButton", Interface.ShowMapCombos)
    WindowSetShowing("MapWindowAreaPrevButton", Interface.ShowMapCombos)
    WindowClearAnchors("Map")
    if (not Interface.ShowMapCombos) then
        WindowAddAnchor("Map", "topleft", "MapWindow", "topleft", 12, 35)
        WindowAddAnchor("Map", "bottomright", "MapWindow", "bottomright", -12, -13)
        MapWindow.MAP_HEIGHT_DIFFERENCE = 56
    else
        MapWindow.MAP_HEIGHT_DIFFERENCE = 111
        WindowAddAnchor("Map", "bottom", "MapWindowAreaCombo", "top", 0, 3)
        local windowWidth, windowHeight = WindowGetDimensions("MapWindow")
        WindowSetDimensions("Map", windowWidth - MapWindow.MAP_WIDTH_DIFFERENCE, windowHeight - MapWindow.MAP_HEIGHT_DIFFERENCE)
    end
    MapCommon.ForcedUpdate = true
    MapWindow.UpdateWaypoints()
end

function MapWindow.LockTooltip()
    if ( MapWindow.Locked ) then
        Tooltips.CreateTextOnlyTooltip(SystemData.ActiveWindow.name, GetStringFromTid(1154868))
    else
        Tooltips.CreateTextOnlyTooltip(SystemData.ActiveWindow.name, GetStringFromTid(1154871))
    end
    Tooltips.Finalize()
    Tooltips.AnchorTooltip( Tooltips.ANCHOR_WINDOW_TOP )
end

function MapWindow.Lock()
    MapWindow.Locked = not MapWindow.Locked
    Interface.SaveBoolean( "MapWindowLocked", MapWindow.Locked )
    local this = WindowUtils.GetActiveDialog()
    local texture = "UO_Core"
    if ( MapWindow.Locked ) then
        ButtonSetTexture(this.."Lock", InterfaceCore.ButtonStates.STATE_NORMAL, texture, 69, 341)
        ButtonSetTexture(this.."Lock", InterfaceCore.ButtonStates.STATE_NORMAL_HIGHLITE, texture, 92, 341)
        ButtonSetTexture(this.."Lock", InterfaceCore.ButtonStates.STATE_PRESSED, texture, 92, 341)
        ButtonSetTexture(this.."Lock", InterfaceCore.ButtonStates.STATE_PRESSED_HIGHLITE, texture, 92, 341)
    else
        ButtonSetTexture(this.."Lock", InterfaceCore.ButtonStates.STATE_NORMAL, texture, 117, 341)
        ButtonSetTexture(this.."Lock", InterfaceCore.ButtonStates.STATE_NORMAL_HIGHLITE, texture, 142, 341)
        ButtonSetTexture(this.."Lock", InterfaceCore.ButtonStates.STATE_PRESSED, texture, 142, 341)
        ButtonSetTexture(this.."Lock", InterfaceCore.ButtonStates.STATE_PRESSED_HIGHLITE, texture, 142, 341)
    end
end

function MapWindow.Shutdown()
    if (MapWindow.Big) then
        MapWindow.BigToggle()
    end
	WindowUtils.SaveWindowPosition("MapWindow")
    UnregisterWindowData(WindowData.Radar.Type,0)
    UnregisterWindowData(WindowData.WaypointDisplay.Type,0)
    UnregisterWindowData(WindowData.WaypointList.Type,0)
    SnapUtils.SnappableWindows["MapWindow"] = nil
end

function MapWindow.OnMouseDrag()
    if (not MapWindow.Locked) then
        SnapUtils.StartWindowSnap("MapWindow")
        WindowSetMoving("MapWindow", true)
    else
        WindowSetMoving("MapWindow", false)
    end
end

function MapWindow.UpdateMap()
    if (WindowGetShowing("MapWindow") == true) then
        if( MapCommon.ActiveView == MapCommon.MAP_MODE_NAME ) then
            local oldArea  = ( ComboBoxGetSelectedMenuItem( "MapWindowAreaCombo"  ) - 1 )
            local oldFacet = ( ComboBoxGetSelectedMenuItem( "MapWindowFacetCombo" ) - 1 )

            MapWindow.CurrentFacet = UOGetRadarFacet()
            MapWindow.CurrentArea  = UOGetRadarArea()
            MapWindow.UpdateAreaCombo()
            if (MapWindow.CurrentArea ~= nil and MapWindow.Areas[MapWindow.CurrentArea] ~= nil) then
                ComboBoxSetSelectedMenuItem( "MapWindowAreaCombo", MapWindow.Areas[MapWindow.CurrentArea] + 1 )
            else
                ComboBoxSetSelectedMenuItem( "MapWindowAreaCombo", 1 )
                MapWindow.CurrentArea = MapWindow.AreaIndices[0] or 0
            end

            DynamicImageSetTextureScale("MapImage", WindowData.Radar.TexScale)
            DynamicImageSetTexture("MapImage", "radar_texture", WindowData.Radar.TexCoordX, WindowData.Radar.TexCoordY)
            if MapWindow.Tilt then
                DynamicImageSetRotation("MapImage", 0)
                if (DoesWindowNameExist("MapCompass")) then
                    DynamicImageSetRotation( "MapCompass", 0 )
                end
            else
                DynamicImageSetRotation("MapImage", WindowData.Radar.TexRotation)
                if (DoesWindowNameExist("MapCompass")) then
                    DynamicImageSetRotation( "MapCompass", WindowData.Radar.TexRotation )
                end
            end

            MapCommon.ForcedUpdate = (oldArea ~= MapWindow.CurrentArea) or (oldFacet ~= MapWindow.CurrentFacet)
            if (MapCommon.ForcedUpdate) then
                for waypointId, value in pairs(MapCommon.WaypointsIconFacet) do
                    local windowName = "Waypoint"..waypointId..MapCommon.ActiveView
                    if (value ~= MapWindow.CurrentFacet) then
                        if (DoesWindowNameExist(windowName)) then
                            MapCommon.WaypointViewInfo[MapCommon.ActiveView].Windows[waypointId] = nil
                            DestroyWindow(windowName)
                        end
                    end
                end
            end
            MapWindow.UpdateWaypoints()
        end
    end

    -- Enhanced Map position logging
    waypointX = WindowData.PlayerLocation.x
    waypointY = WindowData.PlayerLocation.y
    waypointFacet = WindowData.PlayerLocation.facet
    TextLogCreate("pos", 1)
    TextLogSetEnabled("pos", true)
    TextLogClear("pos")
    TextLogSetIncrementalSaving( "pos", true, "logs/pos.log")
    TextLogAddFilterType( "pos", 1, L"XY: " )
    TextLogAddEntry("pos", 1, L" "..waypointFacet..L"|"..waypointX..L"|"..waypointY..L"!")
    TextLogDestroy("pos")
end

function MapWindow.UpdateWaypoints()
    if (WindowGetShowing("MapWindow") == true and MapCommon.ActiveView == MapCommon.MAP_MODE_NAME) then
        MapCommon.WaypointsDirty = true
    end
end

function MapWindow.PopulateMapLegend()
    if( WindowData.WaypointDisplay.displayTypes.ATLAS ~= nil and WindowData.WaypointDisplay.typeNames ~= nil ) then
        local prevWindowName = nil

        for index=1, table.getn(WindowData.WaypointDisplay.typeNames) do
            if WindowData.WaypointDisplay.displayTypes.ATLAS[index].isDisplayed then
                local windowName = "MapLegend"..index

                CreateWindowFromTemplate(windowName,"MapLegendItemTemplate", "LegendWindow" )
                WindowSetId(windowName, index)

                if( prevWindowName == nil ) then
                    WindowAddAnchor(windowName, "top", "LegendWindow", "top", 10, 10)
                else
                    WindowAddAnchor(windowName, "bottom", prevWindowName, "top", 0, 0)
                end
                prevWindowName = windowName

                local waypointName = WindowData.WaypointDisplay.typeNames[index]
                LabelSetText(windowName.."Text", waypointName)

                local iconId = WindowData.WaypointDisplay.displayTypes.ATLAS[index].iconId
                MapCommon.UpdateWaypointIcon(iconId,windowName.."Icon")

                MapWindow.TypeEnabled[index] = true
            end
        end
    end
end

function MapWindow.ActivateMap()
    if( MapCommon.ActiveView ~= MapCommon.MAP_MODE_NAME ) then
        local mapTextureWidth, mapTextureHeight = WindowGetDimensions("MapImage")

	    UORadarSetWindowSize(mapTextureWidth, mapTextureHeight, false, MapWindow.CenterOnPlayer)
        if MapWindow.Tilt then
            UOSetRadarRotation(0)
        else
            UOSetRadarRotation(MapWindow.Rotation)
        end
	    UORadarSetWindowOffset(0, 0)

	    WindowSetShowing("RadarWindow", false)
	    WindowSetShowing("MapWindow", true)

	    MapCommon.ActiveView = MapCommon.MAP_MODE_NAME
	    UOSetWaypointDisplayMode(MapCommon.MAP_MODE_NAME)

	    local facet = UOGetRadarFacet()
	    local area = UOGetRadarArea()
	    MapCommon.UpdateZoomValues(facet, area)
        local savedZoom = Interface.LoadNumber( "MapZoom", -100 )
        if savedZoom ~= -100 then
            MapCommon.AdjustZoom(savedZoom)
        else
            if(MapWindow.CenterOnPlayer == true) then
                MapCommon.AdjustZoom(-4)
            else
                MapCommon.AdjustZoom(0)
            end
        end

	    MapWindow.UpdateMap()
	    MapWindow.UpdateWaypoints()
        MapWindow.ToggleCombos(Interface.ShowMapCombos)
	end
end

-----------------------------------------------------------------
-- Input Event Handlers
-----------------------------------------------------------------

function MapWindow.MapOnMouseWheel(x, y, delta)
   	MapCommon.AdjustZoom(-delta)
end

function MapWindow.ZoomOutOnLButtonUp()
   	MapCommon.AdjustZoom(1)
end

function MapWindow.ZoomOutOnMouseOver()
	Tooltips.CreateTextOnlyTooltip(SystemData.ActiveWindow.name, GetStringFromTid(MapCommon.TID.ZoomOut))
	Tooltips.Finalize()
	Tooltips.AnchorTooltip( Tooltips.ANCHOR_WINDOW_TOP )
end

function MapWindow.ZoomInOnLButtonUp()
    MapCommon.AdjustZoom(-1)
end

function MapWindow.ZoomInOnMouseOver()
	Tooltips.CreateTextOnlyTooltip(SystemData.ActiveWindow.name, GetStringFromTid(MapCommon.TID.ZoomIn))
	Tooltips.Finalize()
	Tooltips.AnchorTooltip( Tooltips.ANCHOR_WINDOW_TOP )
end

function MapWindow.MapMouseDrag(flags,deltaX,deltaY)
    if( MapWindow.IsDragging and (deltaX ~= 0 or deltaY ~= 0) ) then
        MapCommon.SetWaypointsEnabled(MapCommon.ActiveView, false)

        local facet = UOGetRadarFacet()
        local area = UOGetRadarArea()

        local top, bottom, left, right = MapCommon.GetRadarBorders(facet, area)

        if ( (deltaX < 0 and right < MapCommon.MapBorder.RIGHT ) or ( deltaX >= 0 and left > MapCommon.MapBorder.LEFT ) ) then
			deltaX = 0
        end

        if ( ( deltaY < 0 and bottom < MapCommon.MapBorder.BOTTOM ) or ( deltaY >= 0 and top > MapCommon.MapBorder.TOP ) ) then
			deltaY = 0
        end

		local mapCenterX, mapCenterY = UOGetRadarCenter()
		local winCenterX, winCenterY = UOGetWorldPosToRadar(mapCenterX,mapCenterY)

		local offsetX = winCenterX - deltaX
		local offsetY = winCenterY - deltaY
		local useScale = false

		local newCenterX, newCenterY = UOGetRadarPosToWorld(offsetX,offsetY,useScale)

		UOCenterRadarOnLocation(newCenterX, newCenterY, facet, area)

        MapCommon.ForcedUpdate = true
		MapWindow.UpdateWaypoints()
    end
end

function MapWindow.ToggleRadarOnLButtonUp()
    RadarWindow.ActivateRadar()
end

function MapWindow.ToggleRadarOnMouseOver()
	Tooltips.CreateTextOnlyTooltip(SystemData.ActiveWindow.name, GetStringFromTid(MapCommon.TID.ShowRadar))
	Tooltips.Finalize()
	Tooltips.AnchorTooltip( Tooltips.ANCHOR_WINDOW_TOP )
end

function MapWindow.ToggleFacetUpOnLButtonUp()
    local currentFacet = UOGetRadarFacet()
    local newFacet = currentFacet + 1

    if (newFacet >= MapCommon.NumFacets) then
        newFacet = 0
    end

    if MapWindow.Facets[newFacet] == nil then
        return
    end

    MapWindow.CurrentFacet = newFacet
    ComboBoxSetSelectedMenuItem( "MapWindowFacetCombo", MapWindow.Facets[newFacet] + 1 )

	MapWindow.CenterOnPlayer = false
    ButtonSetPressedFlag( "MapWindowCenterOnPlayerButton", MapWindow.CenterOnPlayer )
    UORadarSetCenterOnPlayer(MapWindow.CenterOnPlayer)
	MapCommon.ChangeMap(newFacet, 0)
end

function MapWindow.ToggleFacetDownOnLButtonUp()
    local currentFacet = UOGetRadarFacet()
    local newFacet = currentFacet - 1

    if (newFacet < 0) then
        newFacet = MapCommon.NumFacets - 1
    end

    if MapWindow.Facets[newFacet] == nil then
        return
    end

    MapWindow.CurrentFacet = newFacet
    ComboBoxSetSelectedMenuItem( "MapWindowFacetCombo", MapWindow.Facets[newFacet] + 1 )

	MapWindow.CenterOnPlayer = false
    ButtonSetPressedFlag( "MapWindowCenterOnPlayerButton", MapWindow.CenterOnPlayer )
    UORadarSetCenterOnPlayer(MapWindow.CenterOnPlayer)
	MapCommon.ChangeMap(newFacet, 0)
end

function MapWindow.ToggleAreaUpOnLButtonUp()
    local curIdx = MapWindow.Areas[MapWindow.CurrentArea]
    if curIdx == nil then
        return
    end

    curIdx = curIdx + 1
    if curIdx >= #MapWindow.AreaIndices then
        curIdx = 0
    end

    MapWindow.CurrentArea = MapWindow.AreaIndices[curIdx]
    ComboBoxSetSelectedMenuItem("MapWindowAreaCombo", curIdx + 1)

	MapWindow.CenterOnPlayer = false
    ButtonSetPressedFlag( "MapWindowCenterOnPlayerButton", MapWindow.CenterOnPlayer )
    UORadarSetCenterOnPlayer(MapWindow.CenterOnPlayer)
	MapCommon.ChangeMap(MapWindow.CurrentFacet, MapWindow.CurrentArea)
end

function MapWindow.ToggleAreaDownOnLButtonUp()
    local curIdx = MapWindow.Areas[MapWindow.CurrentArea]
    if curIdx == nil then
        return
    end

    curIdx = curIdx - 1
    if curIdx < 0 then
        curIdx = #MapWindow.AreaIndices - 1
    end

    MapWindow.CurrentArea = MapWindow.AreaIndices[curIdx]
    ComboBoxSetSelectedMenuItem("MapWindowAreaCombo", curIdx + 1)

	MapWindow.CenterOnPlayer = false
    ButtonSetPressedFlag( "MapWindowCenterOnPlayerButton", MapWindow.CenterOnPlayer )
    UORadarSetCenterOnPlayer(MapWindow.CenterOnPlayer)
	MapCommon.ChangeMap(MapWindow.CurrentFacet, MapWindow.CurrentArea)
end

function MapWindow.MapOnRButtonUp(flags,x,y)
    local useScale = false
    local scale = WindowGetScale("MapWindow")
    local waypointX, waypointY = UOGetRadarPosToWorld(x/scale, y/scale, useScale)
    local params = {x=waypointX, y=waypointY, facetId=UOGetRadarFacet()}

    local facet = UOGetRadarFacet()
    local area = UOGetRadarArea()
    local x1, y1, x2, y2 = UORadarGetAreaDimensions(facet, area)

    if (x1 < waypointX and y1 < waypointY and x2 > waypointX and y2 > waypointY) then
        ContextMenu.CreateLuaContextMenuItem(MapCommon.TID.CreateWaypoint, 0, MapCommon.ContextReturnCodes.CREATE_WAYPOINT, params)
        ContextMenu.CreateLuaContextMenuItemWithString(GetStringFromTid(1154860), 0, "magnetize", params, false)

        if (not Interface.ShowMapCombos) then
            ContextMenu.CreateLuaContextMenuItemWithString(L"", 0, 0, "null", false)
        end
    end
    if (not Interface.ShowMapCombos) then
        local subMenu = {}
        local currfacet = UOGetRadarFacet()
        for f = 0, (MapCommon.NumFacets - 1) do
            if (MapWindow.Facets[f] ~= nil) then
                table.insert(subMenu, { str=GetStringFromTid(UORadarGetFacetLabel(f)), flags=0, returnCode="callFacet"..f, pressed=f==currfacet })
            end
        end
        ContextMenu.CreateLuaContextMenuItemWithString(GetStringFromTid(1155476), 0, 0, "null", false, subMenu)

        subMenu = {}
        local currArea = UOGetRadarArea()
        for areaIndex = 0, (UORadarGetAreaCount(currfacet) - 1) do
            local areaTID = UORadarGetAreaLabel(currfacet, areaIndex)
            if (MapWindow.Areas[areaIndex] ~= nil) then
                if (MapWindow.IsNLS) then
                    if (not MapWindow.NLS_Exclude[areaTID]) then
                        table.insert(subMenu, { str=GetStringFromTid(areaTID), flags=0, returnCode="callArea"..areaIndex, pressed=areaIndex==currArea })
                    end
                else
                    if (not MapWindow.NLS_Only[areaTID]) then
                        table.insert(subMenu, { str=GetStringFromTid(areaTID), flags=0, returnCode="callArea"..areaIndex, pressed=areaIndex==currArea })
                    end
                end
            end
        end
        ContextMenu.CreateLuaContextMenuItemWithString(GetStringFromTid(1155477), 0, 0, "null", false, subMenu)
    end
    ContextMenu.ActivateLuaContextMenu(MapCommon.ContextMenuCallback)
end

function MapWindow.LegendIconOnLButtonUp()
    local windowName = SystemData.ActiveWindow.name
    local waypointType = WindowGetId(windowName)

    MapWindow.TypeEnabled[waypointType] = not MapWindow.TypeEnabled[waypointType]

    local alpha = 1.0
    local color = MapWindow.LegendItemTextColors.normal
    if( MapWindow.TypeEnabled[waypointType] == false ) then
		alpha = 0.5
		color = MapWindow.LegendItemTextColors.disabled
	end
    WindowSetAlpha(windowName,alpha)
    LabelSetTextColor(windowName.."Text",color.r,color.g,color.b)

    MapWindow.UpdateWaypoints()
end

function MapWindow.CenterOnPlayerOnLButtonUp()
	MapWindow.CenterOnPlayer = ButtonGetPressedFlag( "MapWindowCenterOnPlayerButton" )
	UORadarSetCenterOnPlayer(MapWindow.CenterOnPlayer)
    for waypointId, value in pairs(MapCommon.WaypointsIconFacet) do
        local windowName = "Waypoint"..waypointId..MapCommon.ActiveView
        if (value ~= MapWindow.CurrentFacet) then
            if (DoesWindowNameExist(windowName)) then
                MapCommon.WaypointViewInfo[MapCommon.ActiveView].Windows[waypointId] = nil
                DestroyWindow(windowName)
            end
        end
    end
    MapCommon.ForcedUpdate = true
    MapWindow.UpdateWaypoints()
end

function MapWindow.TiltOnLButtonUp()
    MapWindow.Tilt = ButtonGetPressedFlag( "MapWindowTiltButton" )
    Interface.SaveBoolean( "MapWindowTilt", MapWindow.Tilt )
    if MapWindow.Tilt then
        UOSetRadarRotation(0)
    else
        UOSetRadarRotation(MapWindow.Rotation)
    end
end

function MapWindow.MapOnLButtonDown()
    MapWindow.IsDragging = true

    MapWindow.CenterOnPlayer = false
    ButtonSetPressedFlag( "MapWindowCenterOnPlayerButton", MapWindow.CenterOnPlayer )
    UORadarSetCenterOnPlayer(MapWindow.CenterOnPlayer)
    MapCommon.SetWaypointsEnabled(MapCommon.ActiveView, false)
end

function MapWindow.MapOnLButtonUp()
    MapWindow.IsDragging = false
    MapCommon.SetWaypointsEnabled(MapCommon.ActiveView, true)
end

function MapWindow.MapOnLButtonDblClk(flags,x,y)
    local useScale = false
    local scale = WindowGetScale("MapWindow")
    local worldX, worldY = UOGetRadarPosToWorld(x/scale, y/scale, useScale)
    local facet = UOGetRadarFacet()
    local area = UOGetRadarArea()
    if( UORadarIsLocationInArea(worldX, worldY, facet, area) ) then
        UOCenterRadarOnLocation(worldX, worldY, facet, area, true)
    end

    MapWindow.CenterOnPlayer = false
    ButtonSetPressedFlag( "MapWindowCenterOnPlayerButton", MapWindow.CenterOnPlayer )
    UORadarSetCenterOnPlayer(MapWindow.CenterOnPlayer)
end

function MapWindow.OnMouseOver()
	MapWindow.IsMouseOver = true
end

function MapWindow.OnMouseOverEnd()
    MapWindow.IsDragging = false
    MapWindow.IsMouseOver = false
    MapCommon.SetWaypointsEnabled(MapCommon.ActiveView, true)
end

function MapWindow.SelectArea()
	local facet = UOGetRadarFacet()
    local area = ( ComboBoxGetSelectedMenuItem( "MapWindowAreaCombo" ) - 1 )

    if( area ~= UOGetRadarArea() ) then
		MapWindow.CenterOnPlayer = false
        ButtonSetPressedFlag( "MapWindowCenterOnPlayerButton", MapWindow.CenterOnPlayer )
        UORadarSetCenterOnPlayer(MapWindow.CenterOnPlayer)
        MapCommon.ChangeMap(facet, area )
    end
end

function MapWindow.SelectFacet()
    local facet = ( ComboBoxGetSelectedMenuItem( "MapWindowFacetCombo" ) - 1 )
    local area = UOGetRadarArea()

    if( facet ~= UOGetRadarFacet() ) then
		MapWindow.CenterOnPlayer = false
        ButtonSetPressedFlag( "MapWindowCenterOnPlayerButton", MapWindow.CenterOnPlayer )
        UORadarSetCenterOnPlayer(MapWindow.CenterOnPlayer)
        MapCommon.ChangeMap(facet, 0 )
    end
end

function MapWindow.OnLegendToggle()
	MapWindow.LegendVisible = not MapWindow.LegendVisible
	--Debug.Print("LegendWindow Visible: "..tostring(MapWindow.LegendVisible))
	ButtonSetPressedFlag("MapWindowLegendToggle", MapWindow.LegendVisible)
	WindowSetShowing("LegendWindow",MapWindow.LegendVisible)
end

function MapWindow.OnShown()
	if( MapWindow.LegendVisible == true ) then
		WindowSetShowing("LegendWindow",true)
	end
end

function MapWindow.OnUpdate(timePassed)
    if( DoesWindowNameExist("MapWindow") == true and WindowGetShowing("MapWindow") == true and MapWindow.IsMouseOver == true) then
        local windowX, windowY = WindowGetScreenPosition("MapImage")
        local mouseX = SystemData.MousePosition.x - windowX
        local mouseY = SystemData.MousePosition.y - windowY
        local useScale = false
        local scale = WindowGetScale("MapWindow")
        local x, y = UOGetRadarPosToWorld(mouseX/scale, mouseY/scale, useScale)

        local facet = UOGetRadarFacet()
        local area = UOGetRadarArea()
        local x1, y1, x2, y2 = UORadarGetAreaDimensions(facet, area)
        if (x1 < x and y1 < y and x2 > x and y2 > y) then
            local latStr, longStr, latDir, longDir = MapCommon.GetSextantLocationStrings(x, y, facet)
            local sextant = latStr..L"'"..latDir..L" "..longStr..L"'"..longDir..L"\n"..x..L", "..y
            LabelSetText("MapWindowCoordsText", sextant)
        else
            LabelSetText("MapWindowCoordsText", L"")
        end
    end
end

function MapWindow.OnHidden()
	WindowSetShowing("LegendWindow",false)
    SystemData.Settings.Interface.mapMode = MapCommon.MAP_HIDDEN
end

function MapWindow.CloseMap()
    WindowSetShowing("MapWindow", false)
    MapCommon.ActiveView = nil
end

function MapWindow.OnLegendButtonMouseOver()
	Tooltips.CreateTextOnlyTooltip(SystemData.ActiveWindow.name, GetStringFromTid(MapCommon.TID.ShowLegend))
	Tooltips.Finalize()
	Tooltips.AnchorTooltip( Tooltips.ANCHOR_WINDOW_TOP )
end

function MapWindow.OnResizeBegin()
	local windowName = WindowUtils.GetActiveDialog()
	local widthMin = 400
	local heightMin = 400
    WindowUtils.BeginResize( windowName, "topleft", widthMin, heightMin, false, MapWindow.OnResizeEnd)
end

function MapWindow.BigToggle()
    MapWindow.Big = not MapWindow.Big
    local mapZoom

    if (MapWindow.Big) then
        WindowUtils.SaveWindowPosition("MapWindow", false)
        mapZoom = Interface.LoadNumber( "MapZoomBig", -100 )
        local w = Interface.LoadNumber( "MapWindowBigW", 716 )
        local h = Interface.LoadNumber( "MapWindowBigH", 776 )
        WindowSetDimensions("MapWindow", w, h)
        MapWindow.OnResizeEnd("MapWindow")
        WindowUtils.LoadScale( "MapWindow" )
        MapWindow.ComboBCK = Interface.ShowMapCombos
        MapWindow.ToggleCombos(true)
        WindowClearAnchors("MapWindow")
        WindowAddAnchor("MapWindow", "center", "Root", "center", 0, 0)
        WindowUtils.RestoreWindowPosition("MapWindow", false, "mapwindowBig")
        MapCommon.ForcedUpdate = true
        MapWindow.UpdateWaypoints()
    else
        WindowUtils.SaveWindowPosition("MapWindow", false, "mapwindowBig")
        mapZoom = Interface.LoadNumber( "MapZoom", -100 )
        local w = Interface.LoadNumber( "MapWindowW", 716 )
        local h = Interface.LoadNumber( "MapWindowH", 776 )
        WindowSetDimensions("MapWindow", w, h)
        MapWindow.OnResizeEnd("MapWindow")
        WindowUtils.LoadScale( "MapWindow" )
        MapWindow.ToggleCombos(MapWindow.ComboBCK)
        WindowSetShowing("MapWindow".."ResizeButton", true)
        WindowUtils.RestoreWindowPosition("MapWindow", true)
        MapCommon.ForcedUpdate = true
        MapWindow.UpdateWaypoints()
    end
    if (mapZoom ~= nil and mapZoom ~= -100) then
        MapCommon.ZoomLevel[MapCommon.ActiveView].Current = mapZoom
        MapCommon.AdjustZoom(MapCommon.ZoomLevel[MapCommon.ActiveView].Current)
    end
end

function MapWindow.BigOnMouseOver()
    if (MapWindow.Big) then
        Tooltips.CreateTextOnlyTooltip(SystemData.ActiveWindow.name, GetStringFromTid(1154865))
    else
        Tooltips.CreateTextOnlyTooltip(SystemData.ActiveWindow.name, GetStringFromTid(1154866))
    end
    Tooltips.Finalize()
    Tooltips.AnchorTooltip( Tooltips.ANCHOR_WINDOW_TOP )
end

function MapWindow.OnResizeEnd(curWindow)
	local windowWidth, windowHeight = WindowGetDimensions("MapWindow")

	if(windowWidth > MapWindow.WINDOW_WIDTH_MAX) then
		windowWidth = MapWindow.WINDOW_WIDTH_MAX
	end

	if(windowHeight > MapWindow.WINDOW_HEIGHT_MAX) then
		windowHeight = MapWindow.WINDOW_HEIGHT_MAX
	end

	local legendScale = windowHeight / MapWindow.WINDOW_HEIGHT_MAX
    if (DoesWindowNameExist("LegendWindow")) then
        WindowSetScale("LegendWindow", legendScale * InterfaceCore.scale)
    end

	WindowSetDimensions("MapWindow", windowWidth, windowHeight)
    if (Interface) then
        if (MapWindow.Big) then
            Interface.SaveNumber( "MapWindowBigW", windowWidth )
            Interface.SaveNumber( "MapWindowBigH", windowHeight )
        else
            Interface.SaveNumber( "MapWindowW", windowWidth )
            Interface.SaveNumber( "MapWindowH", windowHeight )
        end
    end
    WindowSetDimensions("Map", windowWidth - MapWindow.MAP_WIDTH_DIFFERENCE, windowHeight - MapWindow.MAP_HEIGHT_DIFFERENCE)
    local topWidth, topHeight = WindowGetDimensions("MapWindowTop")
    WindowSetDimensions("MapWindowTop", windowWidth + 10, topHeight)
    local bottomWidth, bottomHeight = WindowGetDimensions("MapWindowBottom")
    WindowSetDimensions("MapWindowBottom", windowWidth, bottomHeight)
    MapCommon.ForcedUpdate = true
    MapWindow.UpdateWaypoints()
end

function MapWindow.UpdateAreaCombo()
    ComboBoxClearMenuItems( "MapWindowAreaCombo" )
    MapWindow.Areas = {}
    MapWindow.AreaIndices = {}
    local curIdx = 0
    for areaIndex = 0, (UORadarGetAreaCount(MapWindow.CurrentFacet) - 1) do
        local areaTID = UORadarGetAreaLabel(MapWindow.CurrentFacet, areaIndex)
        if (MapWindow.IsNLS) then
            if (not MapWindow.NLS_Exclude[areaTID]) then
                MapWindow.Areas[areaIndex] = curIdx
                MapWindow.AreaIndices[curIdx] = areaIndex
                curIdx = curIdx + 1
                ComboBoxAddMenuItem( "MapWindowAreaCombo", GetStringFromTid(areaTID) )
            end
        else
            if (not MapWindow.NLS_Only[areaTID]) then
                MapWindow.Areas[areaIndex] = curIdx
                MapWindow.AreaIndices[curIdx] = areaIndex
                curIdx = curIdx + 1
                ComboBoxAddMenuItem( "MapWindowAreaCombo", GetStringFromTid(areaTID) )
            end
        end
    end
end

function MapWindow.UpdateFacetCombo()
    ComboBoxClearMenuItems( "MapWindowFacetCombo" )
    MapWindow.Facets = {}
    local curIdx = 0
    for facet = 0, (MapCommon.NumFacets - 1) do
        if lastShardSelected == 12 and facet == 1 then
            -- Skip Trammel on Siege
        elseif MapWindow.IsNLS and facet >= 1 then
            -- Skip additional facets on NLS
        else
            MapWindow.Facets[facet] = curIdx
            curIdx = curIdx + 1
            ComboBoxAddMenuItem( "MapWindowFacetCombo", GetStringFromTid(UORadarGetFacetLabel(facet)) )
        end
    end
end
