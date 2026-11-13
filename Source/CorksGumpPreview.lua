
----------------------------------------------------------------
-- Gump style preview: a throwaway window showing EC skin pieces and
-- classic UO gump art side by side, to pick a look for the Corks gumps.
-- Open/close with /gumppreview in chat; right-click closes it.
----------------------------------------------------------------

CorksGumpPreview = {}

CorksGumpPreview.Window = "CorksGumpPreviewWindow"
CorksGumpPreview.Columns = 5
CorksGumpPreview.CellWidth = 150
CorksGumpPreview.CellHeight = 112
CorksGumpPreview.ArtWidth = 150
CorksGumpPreview.ArtHeight = 90
CorksGumpPreview.Gap = 10
CorksGumpPreview.Top = 40
-- More tiles than this for one piece and it is stretched instead (keeps window count sane)
CorksGumpPreview.MaxTiles = 40

CorksGumpPreview.ECStyles = {
	{ template = "CorksPreviewEC_Current",  caption = L"Current (inner frame)" },
	{ template = "CorksPreviewEC_Simple",   caption = L"Simple frame" },
	{ template = "CorksPreviewEC_MainMenu", caption = L"Main menu frame" },
	{ template = "CorksPreviewEC_Outer",    caption = L"Outer frame" },
	{ template = "CorksPreviewEC_Sliders",  caption = L"Default / book slider" },
}

-- Base IDs of classic 9-piece backgrounds (corners, edges, centre = base .. base+8)
CorksGumpPreview.ClassicBackgrounds = {
	83, 2600, 2620, 3000, 3500, 3600, 5054, 5120,
	5150, 9200, 9250, 9260, 9270, 9300, 9350, 9380,
}

-- Classic checkbox art: { unchecked, checked }
CorksGumpPreview.ClassicChecks = {
	{ 210, 211 }, { 208, 209 }, { 2151, 2153 }, { 9720, 9723 },
}

CorksGumpPreview.Requested = {}
CorksGumpPreview.CellCount = 0
CorksGumpPreview.ImageCount = 0

----------------------------------------------------------------
-- Open / close
----------------------------------------------------------------

function CorksGumpPreview.Toggle()
	if DoesWindowNameExist(CorksGumpPreview.Window) then
		DestroyWindow(CorksGumpPreview.Window)
	else
		CreateWindow(CorksGumpPreview.Window, true)
	end
end

function CorksGumpPreview.Close()
	DestroyWindow(CorksGumpPreview.Window)
end

function CorksGumpPreview.Shutdown()
	for id in pairs(CorksGumpPreview.Requested) do
		pcall(ReleaseGumpArt, id)
	end
	CorksGumpPreview.Requested = {}
end

----------------------------------------------------------------
-- Building the samples
----------------------------------------------------------------

function CorksGumpPreview.Initialize()
	CorksGumpPreview.CellCount = 0
	CorksGumpPreview.ImageCount = 0
	WindowUtils.SetWindowTitle(CorksGumpPreview.Window, L"Gump Style Preview")

	for _, style in ipairs(CorksGumpPreview.ECStyles) do
		CorksGumpPreview.Protected(CorksGumpPreview.AddECStyle, style)
	end
	for _, id in ipairs(CorksGumpPreview.ClassicBackgrounds) do
		CorksGumpPreview.Protected(CorksGumpPreview.AddClassicBackground, id)
	end
	CorksGumpPreview.Protected(CorksGumpPreview.AddClassicChecks)
end

-- One bad sample must not stop the rest from showing
function CorksGumpPreview.Protected(func, arg)
	local ok, err = pcall(func, arg)
	if not ok then
		pcall(WindowUtils.ChatPrint, StringToWString("Gump preview: " .. tostring(err)), SystemData.ChatLogFilters.SYSTEM)
	end
end

-- Creates the next grid cell and returns its name
function CorksGumpPreview.NewCell(caption)
	local P = CorksGumpPreview
	P.CellCount = P.CellCount + 1
	local index = P.CellCount - 1
	local col = index % P.Columns
	local row = math.floor(index / P.Columns)
	local name = "CorksPreviewCell" .. P.CellCount
	CreateWindowFromTemplate(name, "CorksPreviewCell", P.Window)
	WindowAddAnchor(name, "topleft", P.Window, "topleft",
		P.Gap + col * (P.CellWidth + P.Gap), P.Top + row * (P.CellHeight + P.Gap))
	LabelSetText(name .. "Caption", caption)
	return name
end

-- Windows created from Lua don't pick up the gump's scale, so match it once built
function CorksGumpPreview.FinishCell(cell)
	WindowSetScale(cell, WindowGetScale(CorksGumpPreview.Window))
end

function CorksGumpPreview.AddECStyle(style)
	local cell = CorksGumpPreview.NewCell(style.caption)
	local art = cell .. "Art"
	CreateWindowFromTemplate(cell .. "Style", style.template, art)
	WindowAddAnchor(cell .. "Style", "topleft", art, "topleft", 0, 0)
	CorksGumpPreview.FinishCell(cell)
end

function CorksGumpPreview.AddClassicBackground(baseId)
	local cell = CorksGumpPreview.NewCell(StringToWString("Classic " .. baseId))
	local P = CorksGumpPreview
	if not P.ClassicBackground(cell .. "Art", baseId, P.ArtWidth, P.ArtHeight) then
		LabelSetText(cell .. "Caption", StringToWString("Classic " .. baseId .. " (not found)"))
	end
	P.FinishCell(cell)
end

function CorksGumpPreview.AddClassicChecks()
	local P = CorksGumpPreview
	local captionIds = {}
	for _, pair in ipairs(P.ClassicChecks) do
		table.insert(captionIds, pair[1] .. "/" .. pair[2])
	end
	local cell = P.NewCell(StringToWString("Checks " .. table.concat(captionIds, " ")))
	local art = cell .. "Art"
	-- dark backing so the art is visible
	CreateWindowFromTemplate(cell .. "Style", "CorksPreviewEC_Current", art)
	WindowAddAnchor(cell .. "Style", "topleft", art, "topleft", 0, 0)
	for i, pair in ipairs(P.ClassicChecks) do
		for row, id in ipairs(pair) do
			local piece = P.Request(id)
			if piece then
				-- fit into a 28x28 box, keeping the art's own size when it's smaller
				local w = math.min(piece.w, 28)
				local h = math.min(piece.h, 28)
				P.Image(art, piece.tex, 10 + (i - 1) * 35, 12 + (row - 1) * 36, w, h, piece.w, piece.h)
			end
		end
	end
	P.FinishCell(cell)
end

----------------------------------------------------------------
-- Classic gump art helpers (reusable if a classic look is picked)
----------------------------------------------------------------

-- Loads one piece of gump art; nil when the ID has no art
function CorksGumpPreview.Request(id)
	local tex, w, h = RequestGumpArt(id)
	CorksGumpPreview.Requested[id] = true
	if tex == nil or tex == "" or w == nil or h == nil or w <= 0 or h <= 0 then
		return nil
	end
	return { tex = tex, w = w, h = h }
end

-- Places one image; srcW/srcH is how much of the texture to show (stretched to w x h)
function CorksGumpPreview.Image(parent, tex, x, y, w, h, srcW, srcH)
	local P = CorksGumpPreview
	P.ImageCount = P.ImageCount + 1
	local name = "CorksPreviewImg" .. P.ImageCount
	CreateWindowFromTemplate(name, "CorksPreviewImage", parent)
	WindowSetDimensions(name, w, h)
	DynamicImageSetTexture(name, tex, 0, 0)
	DynamicImageSetTextureDimensions(name, srcW or w, srcH or h)
	WindowAddAnchor(name, "topleft", parent, "topleft", x, y)
end

-- Fills a rectangle by repeating a piece (cropping the last row/column),
-- or stretches it when tiling would take too many windows.
function CorksGumpPreview.Tile(parent, piece, x1, y1, x2, y2)
	local P = CorksGumpPreview
	if x2 <= x1 or y2 <= y1 then
		return
	end
	local across = math.ceil((x2 - x1) / piece.w)
	local down = math.ceil((y2 - y1) / piece.h)
	if across * down > P.MaxTiles then
		P.Image(parent, piece.tex, x1, y1, x2 - x1, y2 - y1, piece.w, piece.h)
		return
	end
	local y = y1
	while y < y2 do
		local th = math.min(piece.h, y2 - y)
		local x = x1
		while x < x2 do
			local tw = math.min(piece.w, x2 - x)
			P.Image(parent, piece.tex, x, y, tw, th)
			x = x + tw
		end
		y = y + th
	end
end

-- Draws a classic 9-piece background (base .. base+8) filling w x h.
-- Returns false if any piece is missing.
function CorksGumpPreview.ClassicBackground(parent, baseId, w, h)
	local P = CorksGumpPreview
	local p = {}
	for i = 0, 8 do
		p[i] = P.Request(baseId + i)
		if not p[i] then
			return false
		end
	end
	-- centre first, then edges, then corners on top
	P.Tile(parent, p[4], p[3].w, p[1].h, w - p[5].w, h - p[7].h)
	P.Tile(parent, p[1], p[0].w, 0, w - p[2].w, p[1].h)
	P.Tile(parent, p[7], p[6].w, h - p[7].h, w - p[8].w, h)
	P.Tile(parent, p[3], 0, p[0].h, p[3].w, h - p[6].h)
	P.Tile(parent, p[5], w - p[5].w, p[2].h, w, h - p[8].h)
	P.Image(parent, p[0].tex, 0, 0, p[0].w, p[0].h)
	P.Image(parent, p[2].tex, w - p[2].w, 0, p[2].w, p[2].h)
	P.Image(parent, p[6].tex, 0, h - p[6].h, p[6].w, p[6].h)
	P.Image(parent, p[8].tex, w - p[8].w, h - p[8].h, p[8].w, p[8].h)
	return true
end
