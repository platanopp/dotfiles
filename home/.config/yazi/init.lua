-- ── Dolphin's details view ──────────────────────────────────────────────
--
-- Size and date modified beside every name, the two columns Dolphin's
-- details view leads with. Yazi's own linemodes show one or the other.
-- Today's files say the time, this year's the day, older ones the year.
function Linemode:size_and_mtime()
	local time = math.floor(self._file.cha.mtime or 0)
	if time == 0 then
		time = ""
	elseif os.date("%Y-%m-%d", time) == os.date("%Y-%m-%d") then
		time = os.date("       %H:%M", time)
	elseif os.date("%Y", time) == os.date("%Y") then
		time = os.date("%d %b %H:%M", time)
	else
		time = os.date("%d %b  %Y", time)
	end

	-- A folder's size is only known once yazi has counted it; until then, a
	-- dash rather than the size of the folder entry itself.
	local size = self._file:size()
	return string.format("%8s  %s", size and ya.readable_size(size) or "-", time)
end

-- ── One folder on screen, as Dolphin opens ──────────────────────────────
--
-- The parent column hidden at start; F9 brings it back (keymap.toml). The
-- ratio in yazi.toml is kept, so F9 restores it as configured.
require("toggle-pane"):entry("min-parent")
