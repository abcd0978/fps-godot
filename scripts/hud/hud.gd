extends CanvasLayer
## In-game HUD. The local player connects its signals here on spawn.

@onready var bar: ProgressBar = $Root/HealthBar
@onready var hp_label: Label = $Root/HealthBar/Value
@onready var weapon_label: Label = $Root/WeaponLabel
@onready var ammo_label: Label = $Root/AmmoLabel
@onready var crosshair: Control = $Root/Crosshair
@onready var scope: ColorRect = $Root/Scope
@onready var kill_log: VBoxContainer = $Root/KillLog
@onready var death_label: Label = $Root/DeathLabel
@onready var damage: ColorRect = $Root/Damage
@onready var timer_label: Label = $Root/TimerLabel
@onready var scoreboard: Panel = $Root/Scoreboard
@onready var score_text: Label = $Root/Scoreboard/Text
@onready var winner_label: Label = $Root/WinnerLabel
@onready var zombie_count: Label = $Root/ZombieCount
@onready var radar: Control = $Root/Radar
@onready var weapon_wheel: Control = $Root/WeaponWheel
@onready var points_label: Label = $Root/PointsLabel
@onready var upgrade_toast: Label = $Root/UpgradeToast

var _hit := 0.0
var _dir_hit := 0.0
var _dmg_mat: ShaderMaterial


func _ready() -> void:
	_dmg_mat = damage.material as ShaderMaterial


func _process(delta: float) -> void:
	if _hit > 0.0 or _dir_hit > 0.0:
		_hit = maxf(_hit - delta * 1.8, 0.0)
		_dir_hit = maxf(_dir_hit - delta * 2.4, 0.0)
		_dmg_mat.set_shader_parameter("intensity", _hit)
		_dmg_mat.set_shader_parameter("dir_intensity", _dir_hit)
	_update_match()


func _update_match() -> void:
	var over := false
	var zombie_mode := Match.mode == "zombie"
	zombie_count.visible = zombie_mode
	radar.visible = zombie_mode
	points_label.visible = zombie_mode
	if zombie_mode:
		timer_label.text = "PHASE %d" % Match.phase
		zombie_count.text = "남은 좀비: %d" % get_tree().get_nodes_in_group("zombie").size()
		winner_label.visible = false
	else:
		timer_label.text = "%d:%02d" % [int(Match.time_left) / 60, int(Match.time_left) % 60]
		over = (not Match.running) and Match.winner != ""
		winner_label.visible = over
		if over:
			winner_label.text = "WINNER: %s\n곧 재시작..." % Match.winner
	var show_sb: bool = over or Input.is_physical_key_pressed(KEY_TAB)
	scoreboard.visible = show_sb
	if show_sb:
		score_text.text = _format_scores()


func _format_scores() -> String:
	var arr := []
	for k in Match.scores:
		arr.append([k, int(Match.scores[k])])
	arr.sort_custom(func(a, b): return a[1] > b[1])
	var s := "킬  (목표 %d)\n──────────────\n" % Match.KILL_TARGET
	for e in arr:
		s += "%-16s %d\n" % [e[0], e[1]]
	return s


func clear_kills() -> void:
	for c in kill_log.get_children():
		c.queue_free()


# angle: hit direction relative to the player's facing (radians, 0 = front).
func flash_damage(angle: float) -> void:
	_hit = 1.0
	_dir_hit = 1.0
	_dmg_mat.set_shader_parameter("dir", angle)
	_dmg_mat.set_shader_parameter("intensity", 1.0)
	_dmg_mat.set_shader_parameter("dir_intensity", 1.0)


func set_scope(on: bool) -> void:
	scope.visible = on


# Crosshair is shown only while hip-firing — hidden when aiming down the sights.
func set_crosshair(on: bool) -> void:
	crosshair.visible = on


# --- Weapon wheel (radial selector held with F) ---
func open_weapon_wheel(names: PackedStringArray, selected: int, unlocked: Array = []) -> void:
	weapon_wheel.show_wheel(names, selected, unlocked)


func update_weapon_wheel(selected: int) -> void:
	weapon_wheel.update_selection(selected)


func close_weapon_wheel() -> void:
	weapon_wheel.hide_wheel()


# Boxhead points + upgrade readout. up = [damage, rate, mag] levels (current gun).
func set_points(value: int, barricade_lv: int, up: Array) -> void:
	points_label.text = "포인트 %d   현재무기Lv 뎀%d/연사%d/탄창%d   [Z]지뢰40 [X]바리80 [H]내구%d   (무기·업글은 아이템)" % [
		value, up[0], up[1], up[2], barricade_lv]


# Brief on-screen toast when an upgrade item is collected.
func flash_upgrade(msg: String) -> void:
	upgrade_toast.text = "▲ 업그레이드!  %s" % msg
	upgrade_toast.visible = true
	upgrade_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(1.2)
	tw.tween_property(upgrade_toast, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func(): upgrade_toast.visible = false)


func set_dead(on: bool) -> void:
	death_label.visible = on
	if on:
		death_label.text = "사망 — 5초 후 부활"


func set_invincible(on: bool) -> void:
	death_label.visible = on
	if on:
		death_label.text = "부활 — 3초 무적"


func add_kill(killer: String, victim: String, weapon: String) -> void:
	var line := Label.new()
	line.text = "%s  ⟪%s⟫  %s" % [killer, weapon, victim]
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	kill_log.add_child(line)
	while kill_log.get_child_count() > 6:
		kill_log.get_child(0).free()
	await get_tree().create_timer(5.0).timeout
	if is_instance_valid(line):
		line.queue_free()


func set_health(value: int) -> void:
	bar.value = value
	hp_label.text = "HP %d" % value


func set_weapon(weapon_name: String) -> void:
	weapon_label.text = "[ %s ]" % weapon_name


func set_ammo(current: int, maximum: int) -> void:
	if maximum == -2:
		ammo_label.text = "수류탄 %d" % current
	elif maximum < 0:
		ammo_label.text = "∞"
	else:
		ammo_label.text = "%d / %d" % [current, maximum]
