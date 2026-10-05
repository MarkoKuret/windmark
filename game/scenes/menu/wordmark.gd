extends VBoxContainer
## The placeholder wordmark (menus.md §1): WINDMARK in Barlow Semi Condensed Bold, all caps, wide tracking, navy,
## with the line under it. One scene (wordmark.tscn), so the logo replaces it without touching the menu; it keeps
## the logo's room (up to 420 x 96 px).

const TEXT := "WINDMARK"
const LINE := "Tactical sailing races"
const SIZE := 54
const TRACKING := 0.18


func _ready() -> void:
	add_theme_constant_override("separation", 0)
	custom_minimum_size = Vector2(0, 96)
	var title := MenuTheme.label(TEXT, SIZE, MenuTheme.NAVY, 700, TRACKING)
	title.name = "Title"
	add_child(title)
	var line := MenuTheme.label(LINE, MenuTheme.ROW_SIZE, MenuTheme.INK, 600, 0.04)
	line.name = "Line"
	add_child(line)
