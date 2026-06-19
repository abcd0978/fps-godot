extends Node3D
## Reusable animated character visual (Kenney Mini Characters, CC0).
## Used by both players (3rd-person body seen by others) and bots.
## Picks a skin, exposes locomotion (idle/walk/run) and death animation.

const SKINS := [
	preload("res://assets/characters/char_a.glb"),
	preload("res://assets/characters/char_b.glb"),
	preload("res://assets/characters/char_c.glb"),
]
const MODEL_SCALE := 2.5
const WALK_THRESHOLD := 0.6
const RUN_THRESHOLD := 8.0
const THIRD_GUN := preload("res://assets/weapons/rifle.glb")  # weapon others see in your hand
const ATTACK_ANIM := "attack-melee-right"

var _anim: AnimationPlayer = null
var _dead := false
var _attacking := false
var _state := ""


# index < 0 => random skin. Players pass a stable index (peer id) so every
# peer renders the same skin for the same player.
func build(index: int, tint := Color(1, 1, 1, 1), with_gun := true) -> void:
	var i: int = (randi() % SKINS.size()) if index < 0 else (index % SKINS.size())
	var skin: Node3D = SKINS[i].instantiate()
	skin.rotation.y = PI          # face -Z (CharacterBody3D forward)
	skin.scale = Vector3.ONE * MODEL_SCALE
	add_child(skin)

	if tint != Color(1, 1, 1, 1):
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = preload("res://assets/characters/Textures/colormap.png")
		mat.albedo_color = tint
		mat.emission_enabled = true
		mat.emission = Color(0.0, 0.25, 0.0, 1)
		mat.emission_energy_multiplier = 0.4
		for mi in skin.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = mat

	# Attach a gun to the right arm so other players see the held weapon.
	if with_gun:
		var skel := skin.find_child("Skeleton3D", true, false) as Skeleton3D
		if skel:
			var ba := BoneAttachment3D.new()
			ba.bone_name = "arm-right"
			skel.add_child(ba)
			var gun: Node3D = THIRD_GUN.instantiate()
			gun.scale = Vector3.ONE * 0.25
			gun.position = Vector3(0.0, -0.2, 0.0)
			ba.add_child(gun)

	_anim = skin.find_child("AnimationPlayer", true, false) as AnimationPlayer
	if _anim:
		for a in ["idle", "walk", "sprint"]:
			if _anim.has_animation(a):
				_anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
		_play("idle")


func set_locomotion(speed: float) -> void:
	if _dead or _attacking:
		return
	var a := "idle"
	if speed > RUN_THRESHOLD:
		a = "sprint"
	elif speed > WALK_THRESHOLD:
		a = "walk"
	_play(a)


# Play the melee swing once, stretched to `duration` seconds, then idle.
func play_attack(duration := 0.5) -> void:
	if _dead or _anim == null or not _anim.has_animation(ATTACK_ANIM):
		return
	_attacking = true
	_state = ATTACK_ANIM
	var anim := _anim.get_animation(ATTACK_ANIM)
	anim.loop_mode = Animation.LOOP_NONE
	var speed := (anim.length / duration) if duration > 0.0 else 1.0
	_anim.play(ATTACK_ANIM, -1.0, speed)
	await get_tree().create_timer(duration).timeout
	_attacking = false
	if not _dead:
		_play("idle")


func play_die() -> void:
	if _dead:
		return
	_dead = true
	_state = "die"
	if _anim and _anim.has_animation("die"):
		_anim.play("die")


func revive() -> void:
	if not _dead:
		return
	_dead = false
	_play("idle")


func _play(a: String) -> void:
	if _state == a or _anim == null or not _anim.has_animation(a):
		return
	_state = a
	_anim.play(a)
