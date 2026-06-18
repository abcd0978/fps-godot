extends Control
## Draws a 4-line crosshair sized/weighted by Settings.

func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var ctr := size / 2.0
	var s: float = Settings.crosshair_size
	var t: float = Settings.crosshair_thickness
	var gap := 4.0
	var col := Color(1, 1, 1, 0.9)
	draw_line(ctr + Vector2(0, gap), ctr + Vector2(0, gap + s), col, t)
	draw_line(ctr - Vector2(0, gap), ctr - Vector2(0, gap + s), col, t)
	draw_line(ctr + Vector2(gap, 0), ctr + Vector2(gap + s, 0), col, t)
	draw_line(ctr - Vector2(gap, 0), ctr - Vector2(gap + s, 0), col, t)
