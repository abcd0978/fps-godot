extends Control
## Wrapper that renders the whole game into a SubViewport and composites it
## onto a per-pixel-transparent window with adjustable alpha — giving real
## OS window see-through controlled by Settings.opacity.

@onready var game: SubViewportContainer = $Game


func _ready() -> void:
	get_tree().root.transparent_bg = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT, true)


func _process(_delta: float) -> void:
	# opacity 0 = fully opaque, higher = more see-through (floor so it never vanishes)
	game.modulate.a = clampf(1.0 - Settings.opacity, 0.12, 1.0)
