
----------------------------------------------------------------
-- Classic UO gump art helpers, shared by the Corks gumps.
--
-- Classic backgrounds are 9 pieces: base+0..8 = top-left, top, top-right,
-- left, centre, right, bottom-left, bottom, bottom-right. Edges and centre
-- are tiled like the classic client draws them.
--
-- Every piece requested is recorded in an "owner" table; pass that table to
-- CorksGumpArt.ReleaseAll when the gump shuts down.
----------------------------------------------------------------

CorksGumpArt = {}

-- More tiles than this for one piece and it is stretched instead (keeps window count sane)
CorksGumpArt.MaxTiles = 40
CorksGumpArt.ImageCount = 0

-- Loads one piece of gump art; nil when the ID has no art
function CorksGumpArt.Request(id, owner)
	local tex, w, h = RequestGumpArt(id)
	owner[id] = true
	if tex == nil or tex == "" or w == nil or h == nil or w <= 0 or h <= 0 then
		return nil
	end
	return { tex = tex, w = w, h = h }
end

function CorksGumpArt.ReleaseAll(owner)
	for id in pairs(owner) do
		pcall(ReleaseGumpArt, id)
		owner[id] = nil
	end
end

-- Places one image; srcW/srcH is how much of the texture to show (stretched to w x h)
function CorksGumpArt.Image(parent, tex, x, y, w, h, srcW, srcH)
	CorksGumpArt.ImageCount = CorksGumpArt.ImageCount + 1
	local name = "CorksGumpArtImg" .. CorksGumpArt.ImageCount
	CreateWindowFromTemplate(name, "CorksGumpArtImage", parent)
	WindowSetDimensions(name, w, h)
	DynamicImageSetTexture(name, tex, 0, 0)
	DynamicImageSetTextureDimensions(name, srcW or w, srcH or h)
	WindowAddAnchor(name, "topleft", parent, "topleft", x, y)
	return name
end

-- Fills a rectangle by repeating a piece (cropping the last row/column),
-- or stretches it when tiling would take too many windows.
function CorksGumpArt.Tile(parent, piece, x1, y1, x2, y2)
	if x2 <= x1 or y2 <= y1 then
		return
	end
	local across = math.ceil((x2 - x1) / piece.w)
	local down = math.ceil((y2 - y1) / piece.h)
	if across * down > CorksGumpArt.MaxTiles then
		CorksGumpArt.Image(parent, piece.tex, x1, y1, x2 - x1, y2 - y1, piece.w, piece.h)
		return
	end
	local y = y1
	while y < y2 do
		local th = math.min(piece.h, y2 - y)
		local x = x1
		while x < x2 do
			local tw = math.min(piece.w, x2 - x)
			CorksGumpArt.Image(parent, piece.tex, x, y, tw, th)
			x = x + tw
		end
		y = y + th
	end
end

-- Draws a classic 9-piece background filling w x h of parent.
-- Returns false if any piece is missing.
function CorksGumpArt.Background(parent, baseId, w, h, owner)
	local p = {}
	for i = 0, 8 do
		p[i] = CorksGumpArt.Request(baseId + i, owner)
		if not p[i] then
			return false
		end
	end
	local Tile, Image = CorksGumpArt.Tile, CorksGumpArt.Image
	-- Too small for the border pieces (e.g. a text box): use the centre piece only
	if p[0].w + p[2].w > w or p[0].h + p[6].h > h then
		Tile(parent, p[4], 0, 0, w, h)
		return true
	end
	-- centre first, then edges, then corners on top
	Tile(parent, p[4], p[3].w, p[1].h, w - p[5].w, h - p[7].h)
	Tile(parent, p[1], p[0].w, 0, w - p[2].w, p[1].h)
	Tile(parent, p[7], p[6].w, h - p[7].h, w - p[8].w, h)
	Tile(parent, p[3], 0, p[0].h, p[3].w, h - p[6].h)
	Tile(parent, p[5], w - p[5].w, p[2].h, w, h - p[8].h)
	Image(parent, p[0].tex, 0, 0, p[0].w, p[0].h)
	Image(parent, p[2].tex, w - p[2].w, 0, p[2].w, p[2].h)
	Image(parent, p[6].tex, 0, h - p[6].h, p[6].w, p[6].h)
	Image(parent, p[8].tex, w - p[8].w, h - p[8].h, p[8].w, p[8].h)
	return true
end

-- Swaps a standard Corks gump (UO_DefaultWindow chrome named <window>Chrome) to a
-- classic background: hides the EC background, frame and title bar but keeps the
-- title text, then draws the classic art into the gump's <window>ClassicBG holder.
-- w, h are the gump's size as set in its XML (unscaled).
-- Returns false (and leaves the EC look) if the art couldn't be loaded.
function CorksGumpArt.ApplyClassic(window, baseId, w, h, owner)
	local holder = window .. "ClassicBG"
	if not CorksGumpArt.Background(holder, baseId, w, h, owner) then
		return false
	end
	local chrome = window .. "Chrome"
	WindowSetShowing(chrome .. "_UO_DefaultWindowBackground", false)
	WindowSetShowing(chrome .. "_UO_TitleBar", false)
	WindowSetShowing(chrome .. "_UO_DefaultWindowFrame", false)
	-- Windows created from Lua don't pick up the gump's saved scale
	WindowSetScale(holder, WindowGetScale(window))
	return true
end

-- Re-applies a window's scale to everything in it, the way the mouse-wheel resize
-- does, so classic art created after the scale was set lines up. The client ignores
-- setting the scale it already has, so nudge it first.
function CorksGumpArt.Rescale(window)
	local scale = WindowGetScale(window)
	WindowSetScale(window, scale + 0.01)
	WindowSetScale(window, scale)
end
