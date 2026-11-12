----------------------------------------------------------------
-- Global Variables
----------------------------------------------------------------

CorksDropAlerts = {}

-- Game messages that show the artifact graphic over your head, for event drops the
-- default UI doesn't know about. Each entry is part of the message, in lowercase.
-- The default UI already shows the graphic for its own messages (TextParsing.lua),
-- so don't repeat those here or the graphic plays twice.
CorksDropAlerts.Messages = {
	"you recover an artifact bearing the mark of the unhallowed",
}

----------------------------------------------------------------
-- Functions
----------------------------------------------------------------

-- Called for every journal line from Interface.NewChatText.
-- Only game messages count, so a player saying the phrase won't show the graphic.
-- Some game messages arrive on other channels than SYSTEM, but they all carry a
-- TextID; text players type never does.
function CorksDropAlerts.OnChatText()
	if not SystemData.Text then
		return
	end
	local isGameMessage = SystemData.TextChannelID == SystemData.ChatLogFilters.SYSTEM
		or (SystemData.TextID ~= nil and SystemData.TextID ~= 0)
	if not isGameMessage then
		return
	end

	local text = string.lower(WStringToString(SystemData.Text))
	for _, message in ipairs(CorksDropAlerts.Messages) do
		if string.find(text, message, 1, true) then
			CenterScreenText.SendCenterScreenTexture("artifact")
			return
		end
	end
end
