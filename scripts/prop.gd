extends StaticBody3D
## Generic cover prop: instances a model and auto-fits a box collider around it.

@export var model: PackedScene
@export var model_scale := 1.0

func _ready() -> void:
	if model == null:
		return
	var m: Node3D = model.instantiate()
	m.scale = Vector3.ONE * model_scale
	add_child(m)
	var aabb := _merged_aabb(m)
	if aabb.size == Vector3.ZERO:
		return
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = aabb.size
	cs.shape = box
	cs.position = aabb.position + aabb.size * 0.5
	add_child(cs)


func _merged_aabb(root: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var a: AABB = mi.get_aabb()
		var xf: Transform3D = global_transform.affine_inverse() * mi.global_transform
		var world_box: AABB = xf * a
		if first:
			out = world_box
			first = false
		else:
			out = out.merge(world_box)
	return out
