
----------------------------------------------------------------
-- Gump style preview: a throwaway window showing EC skin pieces and
-- classic UO gump art side by side, to pick a look for the Corks gumps.
-- Open/close with /gumppreview in chat; right-click closes it.
----------------------------------------------------------------

CorksGumpPreview = {}

CorksGumpPreview.Window = "CorksGumpPreviewWindow"
CorksGumpPreview.Columns = 6
CorksGumpPreview.CellWidth = 190
CorksGumpPreview.CellHeight = 112
CorksGumpPreview.ArtWidth = 190
CorksGumpPreview.ArtHeight = 90
CorksGumpPreview.Gap = 10
CorksGumpPreview.Top = 40

CorksGumpPreview.ECStyles = {
	{ template = "CorksPreviewEC_Current",  caption = L"Current (inner frame)" },
	{ template = "CorksPreviewEC_Simple",   caption = L"Simple frame" },
	{ template = "CorksPreviewEC_MainMenu", caption = L"Main menu frame" },
	{ template = "CorksPreviewEC_Outer",    caption = L"Outer frame" },
	{ template = "CorksPreviewEC_Sliders",  caption = L"Default / book slider" },
}

-- Fonts to sample, shown on the classic background below
CorksGumpPreview.FontBackground = 2620
CorksGumpPreview.Fonts = {
	"UO_DefaultText_15pt", "UO_DefaultText", "UO_Title", "UO_Subtitle",
	"UO_GoldButtonText", "UO_Book_18pt", "UO_NeueText", "UO_NeueText_18pt",
	"UO_CondensedText_15pt", "Arial_Black_12", "Arial_Black_Shadow_12", "UO_Overhead_Chat",
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

-- Gump art loaded by the preview, released when it closes (see CorksGumpArt)
CorksGumpPreview.Requested = {}
CorksGumpPreview.CellCount = 0

----------------------------------------------------------------
-- Open / close
----------------------------------------------------------------

-- Says in chat what happened, so a failure is never silent
function CorksGumpPreview.Say(text)
	pcall(WindowUtils.ChatPrint, StringToWString("Gump preview: " .. text), SystemData.ChatLogFilters.SYSTEM)
end

function CorksGumpPreview.Toggle()
	local ok, err = pcall(function()
		if DoesWindowNameExist(CorksGumpPreview.Window) then
			DestroyWindow(CorksGumpPreview.Window)
			CorksGumpPreview.Say("closed")
		else
			CreateWindow(CorksGumpPreview.Window, true)
			if DoesWindowNameExist(CorksGumpPreview.Window) then
				CorksGumpPreview.Say("opened")
			else
				CorksGumpPreview.Say("the window could not be created")
			end
		end
	end)
	if not ok then
		CorksGumpPreview.Say("error: " .. tostring(err))
	end
end

function CorksGumpPreview.Close()
	DestroyWindow(CorksGumpPreview.Window)
end

function CorksGumpPreview.Shutdown()
	CorksGumpArt.ReleaseAll(CorksGumpPreview.Requested)
end

----------------------------------------------------------------
-- Building the samples
----------------------------------------------------------------

function CorksGumpPreview.Initialize()
	CorksGumpPreview.CellCount = 0
	WindowUtils.SetWindowTitle(CorksGumpPreview.Window, L"Gump Style Preview")

	for _, font in ipairs(CorksGumpPreview.Fonts) do
		CorksGumpPreview.Protected(CorksGumpPreview.AddFont, font)
	end
	for _, style in ipairs(CorksGumpPreview.ECStyles) do
		CorksGumpPreview.Protected(CorksGumpPreview.AddECStyle, style)
	end
	for _, id in ipairs(CorksGumpPreview.ClassicBackgrounds) do
		CorksGumpPreview.Protected(CorksGumpPreview.AddClassicBackground, id)
	end
	CorksGumpPreview.Protected(CorksGumpPreview.AddClassicChecks)

	-- Re-apply the scale to the whole window so the classic art lines up (as the
	-- mouse-wheel resize does)
	CorksGumpPreview.Protected(CorksGumpArt.Rescale, CorksGumpPreview.Window)
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

function CorksGumpPreview.AddFont(font)
	local P = CorksGumpPreview
	local cell = P.NewCell(StringToWString(font))
	local art = cell .. "Art"
	CorksGumpArt.Background(art, P.FontBackground, P.ArtWidth, P.ArtHeight, P.Requested)
	local label = cell .. "Sample"
	CreateWindowFromTemplate(label, "CorksPreviewFontLabel", art)
	WindowAddAnchor(label, "topleft", art, "topleft", 10, 10)
	LabelSetFont(label, font, WindowUtils.FONT_DEFAULT_TEXT_LINESPACING)
	LabelSetText(label, L"Innocent (Blue)\nTarget Text: orc\nMax Distance: 21")
	P.FinishCell(cell)
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
	if not CorksGumpArt.Background(cell .. "Art", baseId, P.ArtWidth, P.ArtHeight, P.Requested) then
		LabelSetText(cell .. "Caption", StringToWString("Classic " .. baseId .. " (not found)"))
	end
	P.FinishCell(cell)
end

function CorksGumpPreview.AddClassicChecks()
	local P = CorksGumpPreview
	-- Only the unchecked ID of each pair, left to right: the full "210/211 ..."
	-- list is wider than the cell and spilled over the sample beside it.
	local captionIds = {}
	for _, pair in ipairs(P.ClassicChecks) do
		table.insert(captionIds, pair[1])
	end
	local cell = P.NewCell(StringToWString("Checks " .. table.concat(captionIds, " ")))
	local art = cell .. "Art"
	-- dark backing so the art is visible
	CreateWindowFromTemplate(cell .. "Style", "CorksPreviewEC_Current", art)
	WindowAddAnchor(cell .. "Style", "topleft", art, "topleft", 0, 0)
	for i, pair in ipairs(P.ClassicChecks) do
		for row, id in ipairs(pair) do
			local piece = CorksGumpArt.Request(id, P.Requested)
			if piece then
				-- fit into a 28x28 box, keeping the art's own size when it's smaller
				local w = math.min(piece.w, 28)
				local h = math.min(piece.h, 28)
				CorksGumpArt.Image(art, piece.tex, 10 + (i - 1) * 35, 12 + (row - 1) * 36, w, h, piece.w, piece.h)
			end
		end
	end
	P.FinishCell(cell)
end
