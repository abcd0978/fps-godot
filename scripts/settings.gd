extends Node
## Global settings (autoload "Settings"). Persists to user://settings.cfg.
## Owns the dim/"hide" overlay, the settings UI overlay, and the panic key.

const PATH := "user://settings.cfg"

var mouse_sens := 0.0025
var crosshair_size := 10.0
var crosshair_thickness := 2.0
var opacity := 0.0            # 0 = normal, up to ~0.9 = screen mostly hidden
var panic_keycode := KEY_C    # default panic combo = Ctrl+C (quits the program)
var panic_ctrl := true
var panic_shift := false
var panic_alt := false

var listening := false        # true while the UI is capturing a new panic key

var _ui: CanvasLayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	_ui = preload("res://scenes/settings_ui.tscn").instantiate()
	add_child(_ui)


# Window opacity is applied by root.gd reading `opacity` each frame.
func apply_dim() -> void:
	pass


func open_ui() -> void:
	if _ui:
		_ui.open()


func panic_text() -> String:
	var s := ""
	if panic_ctrl: s += "Ctrl+"
	if panic_shift: s += "Shift+"
	if panic_alt: s += "Alt+"
	return s + OS.get_keycode_string(panic_keycode)


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if listening:
		return  # UI is rebinding; ignore here
	if event.keycode == KEY_F1 or event.keycode == KEY_ESCAPE:
		if _ui:
			_ui.toggle()
		return
	# Panic key -> quit the whole program immediately
	if event.keycode == panic_keycode \
			and event.ctrl_pressed == panic_ctrl \
			and event.shift_pressed == panic_shift \
			and event.alt_pressed == panic_alt:
		get_tree().quit()


func save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("s", "mouse_sens", mouse_sens)
	cf.set_value("s", "crosshair_size", crosshair_size)
	cf.set_value("s", "crosshair_thickness", crosshair_thickness)
	cf.set_value("s", "opacity", opacity)
	cf.set_value("s", "panic_keycode", panic_keycode)
	cf.set_value("s", "panic_ctrl", panic_ctrl)
	cf.set_value("s", "panic_shift", panic_shift)
	cf.set_value("s", "panic_alt", panic_alt)
	cf.save(PATH)


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	mouse_sens = cf.get_value("s", "mouse_sens", mouse_sens)
	crosshair_size = cf.get_value("s", "crosshair_size", crosshair_size)
	crosshair_thickness = cf.get_value("s", "crosshair_thickness", crosshair_thickness)
	opacity = cf.get_value("s", "opacity", opacity)
	panic_keycode = cf.get_value("s", "panic_keycode", panic_keycode)
	panic_ctrl = cf.get_value("s", "panic_ctrl", panic_ctrl)
	panic_shift = cf.get_value("s", "panic_shift", panic_shift)
	panic_alt = cf.get_value("s", "panic_alt", panic_alt)
