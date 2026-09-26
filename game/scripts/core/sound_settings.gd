class_name SoundSettings
extends RefCounted
## Volume sliders for everything, the music and the sound effects. Used by the
## main menu and the in-match menu; changes are saved right away (see Audio).

const ROWS := [["Master", "Volume"], ["Music", "Music"], ["SFX", "Effects"]]


static func build() -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 4)
	for row: Array in ROWS:
		var bus: String = row[0]
		grid.add_child(UiTheme.label(row[1], 9))
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.value = Audio.volumes[bus]
		slider.custom_minimum_size = Vector2(130, 14)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.value_changed.connect(func(v: float) -> void: Audio.set_volume(bus, v))
		if bus != "Music":
			# Let you hear how loud effects are now.
			slider.drag_ended.connect(func(_changed: bool) -> void: Audio.play("pickup"))
		grid.add_child(slider)
	return grid
