extends CanvasLayer
## Settings panel overlay. Toggled by ESC / F1 / the menu button.

@onready var panel: Panel = $Panel
@onready var sens: HSlider = $Panel/V/Sens
@onready var csize: HSlider = $Panel/V/CSize
@onready var cthick: HSlider = $Panel/V/CThick
@onready var opacity: HSlider = $Panel/V/Opacity
@onready var rebind_btn: Button = $Panel/V/RebindBtn
@onready var close_btn: Button = $Panel/V/CloseBtn

var _listening := false


func _ready() -> void:
	layer = 210
	panel.visible = false
	sens.min_value = 0.0005
	sens.max_value = 0.006
	sens.step = 0.0001
	csize.min_value = 2.0
	csize.max_value = 30.0
	csize.step = 1.0
	cthick.min_value = 1.0
	cthick.max_value = 8.0
	cthick.step = 1.0
	opacity.min_value = 0.0
	opacity.max_value = 0.9
	opacity.step = 0.05
	sens.value_changed.connect(_on_sens)
	csize.value_changed.connect(_on_csize)
	cthick.value_changed.connect(_on_cthick)
	opacity.value_changed.connect(_on_opacity)
	rebind_btn.pressed.connect(_start_rebind)
	close_btn.pressed.connect(close)


func _on_sens(v: float) -> void:
	Settings.mouse_sens = v
	Settings.save()


func _on_csize(v: float) -> void:
	Settings.crosshair_size = v
	Settings.save()


func _on_cthick(v: float) -> void:
	Settings.crosshair_thickness = v
	Settings.save()


func _on_opacity(v: float) -> void:
	Settings.opacity = v
	Settings.apply_dim()
	Settings.save()


func open() -> void:
	_refresh()
	panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close() -> void:
	panel.visible = false
	_listening = false
	Settings.listening = false


func toggle() -> void:
	if panel.visible:
		close()
	else:
		open()


func _refresh() -> void:
	sens.value = Settings.mouse_sens
	csize.value = Settings.crosshair_size
	cthick.value = Settings.crosshair_thickness
	opacity.value = Settings.opacity
	rebind_btn.text = "긴급정지 키: %s" % Settings.panic_text()


func _start_rebind() -> void:
	_listening = true
	Settings.listening = true
	rebind_btn.text = "키를 누르세요..."


func _input(event: InputEvent) -> void:
	if not _listening:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		Settings.panic_keycode = event.keycode
		Settings.panic_ctrl = event.ctrl_pressed
		Settings.panic_shift = event.shift_pressed
		Settings.panic_alt = event.alt_pressed
		_listening = false
		Settings.listening = false
		Settings.save()
		_refresh()
		get_viewport().set_input_as_handled()
