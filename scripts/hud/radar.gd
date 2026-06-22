extends Control
## Always-on minimap / zombie radar. Player-centred and rotated so the local
## player always faces up. Plots zombies (coloured by kind) and co-op players as
## blips; targets beyond range are pinned to the rim so their direction shows.

const RANGE := 70.0  # world metres mapped to the radar rim

const KIND_COLORS := {
	0: Color(0.50, 0.95, 0.50),  # normal
	1: Color(0.90, 0.95, 0.30),  # runner
	2: Color(0.95, 0.35, 0.30),  # brute
	3: Color(0.40, 0.85, 0.95),  # jumper
	4: Color(0.80, 0.55, 1.00),  # spitter
}

# Cached map footprints {xform, hx, hz} for the minimap topology (built once).
var _walls: Array = []
var _scanned := false


func _process(_delta: float) -> void:
	if visible:
		queue_redraw()


# Collect the level's box structures (walls/towers/buildings) for the minimap.
func _scan_walls() -> void:
	_scanned = true
	var world := get_tree().get_first_node_in_group("gameworld")
	if world == null:
		return
	for n in world.get_children():
		if n is CSGBox3D:
			var sz: Vector3 = n.size
			if sz.x > 150.0 or sz.z > 150.0:
				continue  # skip the floor
			_walls.append({"xf": n.global_transform, "hx": sz.x * 0.5, "hz": sz.z * 0.5})


func _draw() -> void:
	var r := size.x * 0.5
	var c := Vector2(r, r)
	draw_circle(c, r, Color(0, 0, 0, 0.45))
	draw_arc(c, r * 0.5, 0, TAU, 32, Color(0.5, 0.9, 0.5, 0.15), 1.0)
	draw_arc(c, r, 0, TAU, 48, Color(0.5, 0.9, 0.5, 0.5), 2.0)

	var p := _local_player()
	if p == null:
		return
	var inv := p.global_transform.affine_inverse()
	var s := r / RANGE

	# Map topology: draw each box structure's footprint (rotated with the player).
	if not _scanned:
		_scan_walls()
	for w in _walls:
		var xf: Transform3D = w["xf"]
		var hx: float = w["hx"]
		var hz: float = w["hz"]
		var corners := PackedVector2Array()
		var any_near := false
		for cx in [-hx, hx]:
			for cz in [-hz, hz]:
				var lp: Vector3 = inv * (xf * Vector3(cx, 0.0, cz))
				var v := Vector2(lp.x, lp.z) * s
				corners.append(c + v)
				if v.length() < r * 1.4:
					any_near = true
		if any_near:
			# reorder to a proper quad (corners come out as TL,BL,TR,BR)
			var quad := PackedVector2Array([corners[0], corners[1], corners[3], corners[2]])
			draw_colored_polygon(quad, Color(0.55, 0.55, 0.62, 0.5))

	for z in get_tree().get_nodes_in_group("zombie"):
		var lp: Vector3 = inv * z.global_position
		var v := Vector2(lp.x, lp.z) * s
		var k: int = z.kind
		var col: Color = KIND_COLORS.get(k, KIND_COLORS[0])
		var dot := 4.0 if k == 2 else 2.5
		if v.length() > r:
			v = v.normalized() * r
			col.a = 0.55
		draw_circle(c + v, dot, col)

	for op in get_tree().get_nodes_in_group("player"):
		if op == p:
			continue
		var lp: Vector3 = inv * op.global_position
		var v := Vector2(lp.x, lp.z) * s
		if v.length() > r:
			v = v.normalized() * r
		draw_circle(c + v, 3.0, Color(0.4, 0.7, 1.0))

	# Local player arrow at centre, pointing up (forward).
	var pts := PackedVector2Array([c + Vector2(0, -7), c + Vector2(-5, 5), c + Vector2(5, 5)])
	draw_colored_polygon(pts, Color(1, 1, 1))


func _local_player() -> Node3D:
	for p in get_tree().get_nodes_in_group("player"):
		if p.is_multiplayer_authority():
			return p
	return null
