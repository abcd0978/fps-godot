extends CharacterBody3D
## First-person player controller: movement, sprint (double-tap W), look,
## health, aim-down-sights, recoil, firing, an animated 3rd-person body (seen
## by other players), name, kill reporting and 5s respawn.

const WALK_SPEED := 6.0
const SPRINT_SPEED := 11.0
const JUMP_VELOCITY := 5.5
const GRAVITY := 14.0
const MOUSE_SENS := 0.0025
const DOUBLE_TAP_MS := 280
const MAX_HEALTH := 100
const HIP_FOV := 75.0
const RESPAWN_TIME := 5.0

signal health_changed(value: int)

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var weapon: Node3D = $Head/Camera3D/Weapon
@onready var visual: Node3D = $Visual

var health := MAX_HEALTH
var pname := "Player"

var _sprinting := false
var _last_w_tap := -10000
var _w_was_down := false
var _recoil_pitch := 0.0
var _recoil_yaw := 0.0
var _aiming := false
var _scoped := false
var _dead := false
var _invincible := false
var _bob := 0.0
var _bob_amt := 0.0
var _bob_pitch := 0.0
var _bob_yaw := 0.0
var _last_pos := Vector3.ZERO
var _hud: CanvasLayer = null


func _enter_tree() -> void:
	set_multiplayer_authority(name.to_int())


func _ready() -> void:
	add_to_group("player")
	visual.build(name.to_int())  # stable skin per peer id (same on every client)
	_last_pos = global_position
	if is_multiplayer_authority():
		camera.current = true
		camera.fov = HIP_FOV
		visual.visible = false  # don't render our own body in first person
		weapon.ignore_collider(self)
		pname = Net.player_name
		weapon.shooter_name = pname
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_connect_hud()
	else:
		weapon.visible = false


func _connect_hud() -> void:
	var hud := get_tree().get_first_node_in_group("hud")
	if hud == null:
		return
	_hud = hud
	health_changed.connect(hud.set_health)
	weapon.weapon_changed.connect(hud.set_weapon)
	weapon.ammo_changed.connect(hud.set_ammo)
	hud.set_health(health)
	hud.set_weapon(weapon.current_name())
	hud.set_ammo(weapon.current_ammo(), weapon.current_mag())


# Runs on every peer: drives the 3rd-person animation from synced state.
func _process(delta: float) -> void:
	if health <= 0:
		visual.play_die()
	else:
		visual.revive()
		var d := global_position - _last_pos
		visual.set_locomotion(Vector2(d.x, d.z).length() / maxf(delta, 0.001))
	_last_pos = global_position


func _unhandled_input(event: InputEvent) -> void:
	if not is_multiplayer_authority() or _dead:
		return

	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens: float = Settings.mouse_sens
		if _scoped:
			sens *= 0.35
		elif _aiming:
			sens *= 0.6
		rotate_y(-event.relative.x * sens)
		head.rotate_x(-event.relative.y * sens)
		head.rotation.x = clamp(head.rotation.x, -1.4, 1.4)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: weapon.equip(0)
			KEY_2: weapon.equip(1)
			KEY_3: weapon.equip(2)
			KEY_4: weapon.equip(3)
			KEY_5: weapon.equip(4)
			KEY_R: weapon.reload()
			KEY_ESCAPE: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if not is_multiplayer_authority() or _dead:
		return

	_update_sprint()

	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	elif Input.is_physical_key_pressed(KEY_SPACE):
		velocity.y = JUMP_VELOCITY

	var input_dir := _movement_input()
	var dir := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := SPRINT_SPEED if _sprinting else WALK_SPEED
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	move_and_slide()

	_handle_combat(delta)


func _handle_combat(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

	_aiming = captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	_scoped = _aiming and weapon.has_scope()
	weapon.set_aiming(_aiming)
	weapon.show_model(not _scoped)
	if _hud:
		_hud.set_scope(_scoped)
	var target_fov: float = weapon.aim_fov() if _aiming else HIP_FOV
	camera.fov = lerp(camera.fov, target_fov, delta * 12.0)

	if captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var kick: float = weapon.fire()
		if kick > 0.0:
			_recoil_pitch += kick
			_recoil_yaw += randf_range(-kick * 0.4, kick * 0.4)

	_recoil_pitch = lerp(_recoil_pitch, 0.0, delta * 10.0)
	_recoil_yaw = lerp(_recoil_yaw, 0.0, delta * 10.0)
	_apply_bob(delta)
	camera.rotation.x = -_recoil_pitch + _bob_pitch
	camera.rotation.y = _recoil_yaw + _bob_yaw


# Head/weapon bob while moving — stronger when sprinting, damped when aiming.
func _apply_bob(delta: float) -> void:
	var moving := is_on_floor() and Vector2(velocity.x, velocity.z).length() > 0.5
	var target := 0.0
	if moving:
		target = 1.0 if _sprinting else 0.4
	if _aiming:
		target *= 0.2
	_bob_amt = lerp(_bob_amt, target, delta * 8.0)
	_bob += delta * (14.0 if _sprinting else 9.0)
	var x := cos(_bob) * 0.06 * _bob_amt
	var y := absf(sin(_bob)) * 0.05 * _bob_amt
	weapon.position = Vector3(x, -y, 0.0)
	_bob_pitch = -y * 0.15
	_bob_yaw = x * 0.15


func _movement_input() -> Vector2:
	var d := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		d.y -= 1.0
	if Input.is_physical_key_pressed(KEY_S):
		d.y += 1.0
	if Input.is_physical_key_pressed(KEY_A):
		d.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		d.x += 1.0
	return d


func _update_sprint() -> void:
	var w := Input.is_physical_key_pressed(KEY_W)
	if w and not _w_was_down:
		var now := Time.get_ticks_msec()
		if now - _last_w_tap <= DOUBLE_TAP_MS:
			_sprinting = true
		_last_w_tap = now
	if not w:
		_sprinting = false
	_w_was_down = w


# Called by an attacker's weapon/bot. Runs on this player's authority peer only.
@rpc("any_peer", "call_local", "reliable")
func take_damage(amount: int, attacker_name: String, weapon_name: String, attacker_pos: Vector3) -> void:
	if not is_multiplayer_authority() or _dead or _invincible:
		return
	if _hud:
		var local := global_transform.affine_inverse() * attacker_pos
		_hud.flash_damage(atan2(local.x, -local.z))
	health = max(health - amount, 0)
	if health == 0:
		_die(attacker_name, weapon_name)
	else:
		health_changed.emit(health)


func _die(attacker_name: String, weapon_name: String) -> void:
	_dead = true
	velocity = Vector3.ZERO
	health_changed.emit(0)
	Net.report_kill.rpc(attacker_name, pname, weapon_name)
	if _hud:
		_hud.set_dead(true)
	await get_tree().create_timer(RESPAWN_TIME).timeout
	_respawn()


# --- Pickups (called by the server on this player's authority) ---
@rpc("any_peer", "call_local", "reliable")
func add_health(amount: int) -> void:
	if not is_multiplayer_authority() or _dead:
		return
	health = min(health + amount, MAX_HEALTH)
	health_changed.emit(health)


@rpc("any_peer", "call_local", "reliable")
func give_ammo() -> void:
	if is_multiplayer_authority():
		weapon.refill_all()


@rpc("any_peer", "call_local", "reliable")
func give_weapon(index: int) -> void:
	if is_multiplayer_authority():
		weapon.refill_all()
		weapon.equip(index)


# Called by the Match manager when a new round starts.
func match_reset() -> void:
	_dead = false
	_respawn()


func _respawn() -> void:
	health = MAX_HEALTH
	# random spawn across the arena
	position = Vector3(randf_range(-28.0, 28.0), 3.0, randf_range(-28.0, 28.0))
	velocity = Vector3.ZERO
	_dead = false
	_invincible = true
	health_changed.emit(health)
	if _hud:
		_hud.set_dead(false)
		_hud.set_invincible(true)
	await get_tree().create_timer(3.0).timeout
	_invincible = false
	if _hud:
		_hud.set_invincible(false)
