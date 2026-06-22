extends Control
## Radial weapon selector. Held open with F; the player aims the mouse toward a
## sector to highlight a weapon, then releases F to equip it. The player feeds it
## the weapon names and the currently highlighted index.

const RADIUS := 230.0
const HUB := 46.0

var names: PackedStringArray = []
var selected := -1
var unlocked: Array = []  # per-index; locked weapons are drawn dim


func show_wheel(weapon_names: PackedStringArray, sel: int, unlocked_arr: Array = []) -> void:
	names = weapon_names
	selected = sel
	unlocked = unlocked_arr
	visible = true
	queue_redraw()


func update_selection(sel: int) -> void:
	selected = sel
	queue_redraw()


func hide_wheel() -> void:
	visible = false


func _draw() -> void:
	var n := names.size()
	if n == 0:
		return
	var c := size * 0.5
	var font := get_theme_default_font()
	var fsize := 17
	draw_circle(c, RADIUS + 36.0, Color(0, 0, 0, 0.45))  # dim backdrop

	var step := TAU / n
	for i in n:
		var mid := step * i - PI * 0.5          # sector centre angle (i=0 at top)
		var a0 := mid - step * 0.5
		var a1 := mid + step * 0.5
		var is_locked: bool = i < unlocked.size() and not unlocked[i]
		var col := Color(0.12, 0.13, 0.17, 0.78)
		if is_locked:
			col = Color(0.06, 0.06, 0.08, 0.82)  # locked = dark
		if i == selected:
			col = Color(0.5, 0.2, 0.2, 0.9) if is_locked else Color(0.95, 0.72, 0.18, 0.9)
		# Filled wedge.
		var pts := PackedVector2Array([c])
		for t in 11:
			var a: float = lerp(a0, a1, t / 10.0)
			pts.append(c + Vector2(cos(a), sin(a)) * RADIUS)
		draw_colored_polygon(pts, col)
		# Separator line.
		draw_line(c, c + Vector2(cos(a0), sin(a0)) * RADIUS, Color(0, 0, 0, 0.5), 2.0)
		# Label.
		var lp := c + Vector2(cos(mid), sin(mid)) * (RADIUS * 0.68)
		var tcol := Color(1, 1, 1)
		if is_locked:
			tcol = Color(0.5, 0.5, 0.55)
		elif i == selected:
			tcol = Color(0, 0, 0)
		var w := font.get_string_size(names[i], HORIZONTAL_ALIGNMENT_CENTER, -1, fsize).x
		draw_string(font, lp - Vector2(w * 0.5, -fsize * 0.35), names[i], HORIZONTAL_ALIGNMENT_CENTER, -1, fsize, tcol)

	draw_circle(c, HUB, Color(0, 0, 0, 0.7))  # hub hole
	draw_arc(c, RADIUS, 0, TAU, 64, Color(1, 1, 1, 0.25), 2.0)
