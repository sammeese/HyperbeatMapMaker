# res://fx_settings_panel.gd
# Post-Processing Effects Settings Panel
# 
# Usage:
# 1. Attach this script to a Control node in your scene
# 2. In midi_editor, set fx_settings_panel to reference this Control node
# 3. In midi_editor, set fx_shader_material to reference your ColorRect's ShaderMaterial
# 4. Click the ⏱ button to toggle the panel
#
extends Control

signal settings_changed

var shader_material: ShaderMaterial

# Control references
var enable_bloom_check: CheckBox
var bloom_intensity_slider: HSlider
var bloom_threshold_slider: HSlider
var bloom_spread_slider: HSlider

var enable_crt_check: CheckBox
var crt_curvature_slider: HSlider
var scanline_intensity_slider: HSlider
var scanline_count_slider: HSlider
var vignette_intensity_slider: HSlider
var chromatic_aberration_slider: HSlider

var enable_vhs_check: CheckBox
var vhs_distortion_slider: HSlider
var vhs_noise_slider: HSlider
var vhs_line_speed_slider: HSlider

var enable_color_check: CheckBox
var color_saturation_slider: HSlider
var color_contrast_slider: HSlider
var color_tint_picker: ColorPickerButton

var enable_posterize_check: CheckBox
var color_steps_slider: HSlider

var enable_pixelate_check: CheckBox
var pixel_size_slider: HSlider

var enable_grain_check: CheckBox
var grain_intensity_slider: HSlider

var enable_glitch_check: CheckBox
var glitch_intensity_slider: HSlider

var enable_hue_shift_check: CheckBox
var hue_shift_speed_slider: HSlider

func _ready():
	# Set up the control to fill its parent or have a reasonable size
	custom_minimum_size = Vector2(512, 512)
	
	# Create scroll container
	var scroll = ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	
	var vbox = VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	
	# === BLOOM SECTION ===
	add_section_header(vbox, "✨ BLOOM")
	enable_bloom_check = add_checkbox(vbox, "Enable Bloom", true, "enable_bloom")
	bloom_intensity_slider = add_slider(vbox, "Intensity", 0.0, 5.0, 0.1, 0.7, "bloom_intensity")
	bloom_threshold_slider = add_slider(vbox, "Threshold", 0.0, 1.0, 0.01, 0.8, "bloom_threshold")
	bloom_spread_slider = add_slider(vbox, "Spread", 1.0, 30.0, 1.0, 15.0, "bloom_spread")
	add_separator(vbox)
	
	# === CRT SECTION ===
	add_section_header(vbox, "📺 CRT EFFECTS")
	enable_crt_check = add_checkbox(vbox, "Enable CRT", false, "enable_crt")
	crt_curvature_slider = add_slider(vbox, "Curvature", 3.0, 10.0, 0.1, 6.0, "crt_curvature")
	scanline_intensity_slider = add_slider(vbox, "Scanline Intensity", 0.0, 1.0, 0.01, 0.3, "scanline_intensity")
	scanline_count_slider = add_slider(vbox, "Scanline Count", 100.0, 1000.0, 10.0, 400.0, "scanline_count")
	vignette_intensity_slider = add_slider(vbox, "Vignette", 0.0, 1.0, 0.01, 0.4, "vignette_intensity")
	chromatic_aberration_slider = add_slider(vbox, "Chromatic Aberration", 0.0, 0.005, 0.0001, 0.003, "chromatic_aberration")
	add_separator(vbox)
	
	# === VHS SECTION ===
	add_section_header(vbox, "📼 VHS EFFECTS")
	enable_vhs_check = add_checkbox(vbox, "Enable VHS", false, "enable_vhs")
	vhs_distortion_slider = add_slider(vbox, "Distortion", 0.0, 1.0, 0.01, 0.3, "vhs_distortion")
	vhs_noise_slider = add_slider(vbox, "Noise", 0.0, 1.0, 0.01, 0.15, "vhs_noise")
	vhs_line_speed_slider = add_slider(vbox, "Line Speed", 0.0, 10.0, 0.1, 2.0, "vhs_line_speed")
	add_separator(vbox)
	
	# === COLOR GRADING SECTION ===
	add_section_header(vbox, "🎨 COLOR GRADING")
	enable_color_check = add_checkbox(vbox, "Enable Color Grading", false, "enable_color_grading")
	color_saturation_slider = add_slider(vbox, "Saturation", 0.0, 3.0, 0.01, 1.5, "color_saturation")
	color_contrast_slider = add_slider(vbox, "Contrast", 0.0, 3.0, 0.01, 1.2, "color_contrast")
	color_tint_picker = add_color_picker(vbox, "Tint Color", Color(1.0, 0.6, 0.9), "color_tint")
	add_separator(vbox)
	
	# === POSTERIZATION SECTION ===
	add_section_header(vbox, "🎭 POSTERIZATION")
	enable_posterize_check = add_checkbox(vbox, "Enable Posterize", false, "enable_posterize")
	color_steps_slider = add_slider(vbox, "Color Steps", 2.0, 32.0, 1.0, 16.0, "color_steps")
	add_separator(vbox)
	
	# === PIXELATION SECTION ===
	add_section_header(vbox, "🔲 PIXELATION")
	enable_pixelate_check = add_checkbox(vbox, "Enable Pixelate", false, "enable_pixelate")
	pixel_size_slider = add_slider(vbox, "Pixel Size", 1.0, 6.0, 1.0, 2.0, "pixel_size")
	add_separator(vbox)
	
	# === FILM GRAIN SECTION ===
	add_section_header(vbox, "🎞️ FILM GRAIN")
	enable_grain_check = add_checkbox(vbox, "Enable Grain", false, "enable_grain")
	grain_intensity_slider = add_slider(vbox, "Intensity", 0.0, 1.0, 0.01, 0.15, "grain_intensity")
	add_separator(vbox)
	
	# === GLITCH SECTION ===
	add_section_header(vbox, "⚡ GLITCH")
	enable_glitch_check = add_checkbox(vbox, "Enable Glitch", false, "enable_glitch")
	glitch_intensity_slider = add_slider(vbox, "Intensity", 0.0, 1.0, 0.01, 0.1, "glitch_intensity")
	add_separator(vbox)
	
	# === HUE SHIFT SECTION ===
	add_section_header(vbox, "🌈 HUE SHIFT")
	enable_hue_shift_check = add_checkbox(vbox, "Enable Hue Shift", false, "enable_hue_shift")
	hue_shift_speed_slider = add_slider(vbox, "Speed", 0.0, 2.0, 0.01, 0.5, "hue_shift_speed")
	add_separator(vbox)
	
	# === PRESET BUTTONS ===
	add_section_header(vbox, "🎯 PRESETS")
	var preset_hbox = HBoxContainer.new()
	vbox.add_child(preset_hbox)
	
	var preset_vaporwave = Button.new()
	preset_vaporwave.text = "Vaporwave"
	preset_vaporwave.pressed.connect(_apply_vaporwave_preset)
	preset_hbox.add_child(preset_vaporwave)
	
	var preset_crt = Button.new()
	preset_crt.text = "Classic CRT"
	preset_crt.pressed.connect(_apply_crt_preset)
	preset_hbox.add_child(preset_crt)
	
	var preset_vhs = Button.new()
	preset_vhs.text = "VHS Tape"
	preset_vhs.pressed.connect(_apply_vhs_preset)
	preset_hbox.add_child(preset_vhs)
	
	var preset_off = Button.new()
	preset_off.text = "All Off"
	preset_off.pressed.connect(_apply_off_preset)
	preset_hbox.add_child(preset_off)
	
	# Start hidden
	visible = false

func set_shader_material(material: ShaderMaterial):
	shader_material = material
	if shader_material:
		# Load current values from shader
		load_shader_values()

func load_shader_values():
	if not shader_material:
		return
	
	# Load all current shader values into controls
	enable_bloom_check.button_pressed = shader_material.get_shader_parameter("enable_bloom")
	bloom_intensity_slider.value = shader_material.get_shader_parameter("bloom_intensity")
	bloom_threshold_slider.value = shader_material.get_shader_parameter("bloom_threshold")
	bloom_spread_slider.value = shader_material.get_shader_parameter("bloom_spread")
	
	enable_crt_check.button_pressed = shader_material.get_shader_parameter("enable_crt")
	crt_curvature_slider.value = shader_material.get_shader_parameter("crt_curvature")
	scanline_intensity_slider.value = shader_material.get_shader_parameter("scanline_intensity")
	scanline_count_slider.value = shader_material.get_shader_parameter("scanline_count")
	vignette_intensity_slider.value = shader_material.get_shader_parameter("vignette_intensity")
	chromatic_aberration_slider.value = shader_material.get_shader_parameter("chromatic_aberration")
	
	enable_vhs_check.button_pressed = shader_material.get_shader_parameter("enable_vhs")
	vhs_distortion_slider.value = shader_material.get_shader_parameter("vhs_distortion")
	vhs_noise_slider.value = shader_material.get_shader_parameter("vhs_noise")
	vhs_line_speed_slider.value = shader_material.get_shader_parameter("vhs_line_speed")
	
	enable_color_check.button_pressed = shader_material.get_shader_parameter("enable_color_grading")
	color_saturation_slider.value = shader_material.get_shader_parameter("color_saturation")
	color_contrast_slider.value = shader_material.get_shader_parameter("color_contrast")
	
	var tint = shader_material.get_shader_parameter("color_tint")
	if tint is Vector3:
		color_tint_picker.color = Color(tint.x, tint.y, tint.z)
	
	enable_posterize_check.button_pressed = shader_material.get_shader_parameter("enable_posterize")
	color_steps_slider.value = shader_material.get_shader_parameter("color_steps")
	
	enable_pixelate_check.button_pressed = shader_material.get_shader_parameter("enable_pixelate")
	pixel_size_slider.value = shader_material.get_shader_parameter("pixel_size")
	
	enable_grain_check.button_pressed = shader_material.get_shader_parameter("enable_grain")
	grain_intensity_slider.value = shader_material.get_shader_parameter("grain_intensity")
	
	enable_glitch_check.button_pressed = shader_material.get_shader_parameter("enable_glitch")
	glitch_intensity_slider.value = shader_material.get_shader_parameter("glitch_intensity")
	
	enable_hue_shift_check.button_pressed = shader_material.get_shader_parameter("enable_hue_shift")
	hue_shift_speed_slider.value = shader_material.get_shader_parameter("hue_shift_speed")

func add_section_header(parent: VBoxContainer, text: String):
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 16)
	parent.add_child(label)

func add_separator(parent: VBoxContainer):
	var sep = HSeparator.new()
	parent.add_child(sep)

func add_checkbox(parent: VBoxContainer, label_text: String, default_value: bool, param_name: String) -> CheckBox:
	var hbox = HBoxContainer.new()
	parent.add_child(hbox)
	
	var checkbox = CheckBox.new()
	checkbox.text = label_text
	checkbox.button_pressed = default_value
	checkbox.toggled.connect(func(value): _on_param_changed(param_name, value))
	hbox.add_child(checkbox)
	
	return checkbox

func add_slider(parent: VBoxContainer, label_text: String, min_val: float, max_val: float, step: float, default_value: float, param_name: String) -> HSlider:
	var hbox = HBoxContainer.new()
	parent.add_child(hbox)
	
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 150
	hbox.add_child(label)
	
	var slider = HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = step
	slider.value = default_value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(value): _on_param_changed(param_name, value))
	hbox.add_child(slider)
	
	var value_label = Label.new()
	value_label.text = "%.2f" % default_value
	value_label.custom_minimum_size.x = 50
	slider.value_changed.connect(func(value): value_label.text = "%.2f" % value)
	hbox.add_child(value_label)
	
	return slider

func add_color_picker(parent: VBoxContainer, label_text: String, default_color: Color, param_name: String) -> ColorPickerButton:
	var hbox = HBoxContainer.new()
	parent.add_child(hbox)
	
	var label = Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 150
	hbox.add_child(label)
	
	var picker = ColorPickerButton.new()
	picker.color = default_color
	picker.edit_alpha = false
	picker.color_changed.connect(func(color): _on_color_changed(param_name, color))
	picker.text = "click me"
	hbox.add_child(picker)
	
	return picker

func _on_param_changed(param_name: String, value):
	if shader_material:
		shader_material.set_shader_parameter(param_name, value)

func _on_color_changed(param_name: String, color: Color):
	if shader_material:
		shader_material.set_shader_parameter(param_name, Vector3(color.r, color.g, color.b))

# Preset functions
func _apply_vaporwave_preset():
	enable_bloom_check.button_pressed = true
	enable_crt_check.button_pressed = false
	enable_vhs_check.button_pressed = false
	enable_color_check.button_pressed = true
	enable_posterize_check.button_pressed = false
	enable_pixelate_check.button_pressed = false
	enable_grain_check.button_pressed = true
	enable_glitch_check.button_pressed = true
	enable_hue_shift_check.button_pressed = true
	
	bloom_intensity_slider.value = 3.5
	bloom_threshold_slider.value = 0.4
	bloom_spread_slider.value = 20.0
	
	color_saturation_slider.value = 2.0
	color_contrast_slider.value = 1.3
	color_tint_picker.color = Color(1.0, 0.5, 0.9)
	
	grain_intensity_slider.value = 0.1
	glitch_intensity_slider.value = 0.2
	hue_shift_speed_slider.value = 0.3

func _apply_crt_preset():
	enable_bloom_check.button_pressed = true
	enable_crt_check.button_pressed = true
	enable_vhs_check.button_pressed = false
	enable_color_check.button_pressed = false
	enable_posterize_check.button_pressed = false
	enable_pixelate_check.button_pressed = false
	enable_grain_check.button_pressed = false
	enable_glitch_check.button_pressed = false
	enable_hue_shift_check.button_pressed = false
	
	bloom_intensity_slider.value = 1.5
	crt_curvature_slider.value = 3.0
	scanline_intensity_slider.value = 0.4
	scanline_count_slider.value = 500.0
	vignette_intensity_slider.value = 0.5
	chromatic_aberration_slider.value = 0.005

func _apply_vhs_preset():
	enable_bloom_check.button_pressed = true
	enable_crt_check.button_pressed = false
	enable_vhs_check.button_pressed = true
	enable_color_check.button_pressed = true
	enable_posterize_check.button_pressed = true
	enable_pixelate_check.button_pressed = false
	enable_grain_check.button_pressed = true
	enable_glitch_check.button_pressed = true
	enable_hue_shift_check.button_pressed = false
	
	bloom_intensity_slider.value = 2.0
	vhs_distortion_slider.value = 0.5
	vhs_noise_slider.value = 0.25
	vhs_line_speed_slider.value = 3.0
	
	color_saturation_slider.value = 0.8
	color_contrast_slider.value = 1.1
	color_steps_slider.value = 32.0
	
	grain_intensity_slider.value = 0.2
	glitch_intensity_slider.value = 0.4

func _apply_off_preset():
	enable_bloom_check.button_pressed = false
	enable_crt_check.button_pressed = false
	enable_vhs_check.button_pressed = false
	enable_color_check.button_pressed = false
	enable_posterize_check.button_pressed = false
	enable_pixelate_check.button_pressed = false
	enable_grain_check.button_pressed = false
	enable_glitch_check.button_pressed = false
	enable_hue_shift_check.button_pressed = false
	
	bloom_intensity_slider.value = 0.7
	bloom_threshold_slider.value = 0.8
	bloom_spread_slider.value = 15.0
