# res://midi_editor.gd
extends Control

@onready var file_menu: MenuButton = $ToolBar/FileMenu
@onready var bpm_input: SpinBox = $ToolBar/BPMSpinBox
@onready var division_selector: OptionButton = $ToolBar/DivisionSelector
@onready var tool_bar_2: HBoxContainer = $Control/ToolBar2
@onready var audio_offset_input: SpinBox = null  # Will be created in _ready
@onready var snap_toggle: CheckButton = null  # Will be created in _ready
@onready var lane_height_slider: HSlider = null  # Will be created in _ready
@onready var timeline_canvas: Control = $HSplit/Control/TimelinePanel/ScrollContainer/TimelineCanvas
@onready var scroll_container: ScrollContainer = $HSplit/Control/TimelinePanel/ScrollContainer

@onready var audio_player: AudioStreamPlayer = $HSplit/Control/TimelinePanel/AudioPlayer
@onready var play_button: Button = $ToolBar/buttons/play
@onready var pause_button: Button = $ToolBar/buttons/pause
@onready var time_label: Label = null  # Will be created in _ready
@onready var speed_selector: OptionButton = null  # Will be created in _ready
@onready var volume_slider: HSlider = null  # Will be created in _ready
@onready var tap_tempo_button: Button = null  # Will be created in _ready
@onready var waveform_amplitude_slider: HSlider = null  # Will be created in _ready
@onready var fx_button: Button = null  # Will be created in _ready
@onready var metronome_toggle: CheckButton = null  # Will be created in _ready
@onready var note_hits_toggle: CheckButton = null  # Will be created in _ready
@onready var metronome_volume_slider: HSlider = null  # Will be created in _ready
@onready var note_hits_volume_slider: HSlider = null  # Will be created in _ready
@onready var time_sig_numerator: SpinBox = null  # Will be created in _ready
@onready var time_sig_denominator: SpinBox = null  # Will be created in _ready

@export var fx_settings_panel: Control = null  # Set this to your fx_settings_panel Control node
@export var fx_color_rect: ColorRect = null  # Set this to your ColorRect with the shader

var time_begin: float
var time_delay: float
var playback_position: float = 0.0  # Store position for pause/resume

# Metronome tracking
var last_metronome_beat: int = -1
var metronome_player: AudioStreamPlayer = null

# Note hit tracking  
var triggered_notes: Array = []  # Track which notes have been triggered
var note_hit_player: AudioStreamPlayer = null

# Tap tempo tracking
var tap_times: Array[float] = []
var tap_audio_positions: Array[float] = []
const MAX_TAP_INTERVAL: float = 2.0  # Reset if more than 2 seconds between taps

const NUM_LANES = 21

func _ready():
	setup_file_menu()
	setup_division_selector()
	setup_tap_tempo()
	setup_time_display()
	setup_playback_speed_control()
	setup_volume_control()
	setup_waveform_amplitude_slider()
	setup_audio_offset_control()
	setup_snap_toggle()
	setup_lane_height_slider()
	setup_metronome_toggle()
	setup_note_hits_toggle()
	setup_time_signature_controls()
	setup_fx_button()
	setup_audio_players()
	EditorData.bpm_changed.connect(_on_bpm_changed)
	play_button.pressed.connect(_on_play_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	bpm_input.value_changed.connect(_on_bpm_input_changed)

func _on_bpm_input_changed(value: float):
	EditorData.bpm = value
	EditorData.bpm_changed.emit(value)

func setup_audio_offset_control():
	# Create label with symbol
	var label = Label.new()
	label.text = "⏱"  # Stopwatch symbol
	label.add_theme_font_size_override("font_size", 16)
	label.tooltip_text = "Audio offset"
	tool_bar_2.add_child(label)
	
	# Create spinbox for audio offset
	audio_offset_input = SpinBox.new()
	audio_offset_input.min_value = -10.0
	audio_offset_input.max_value = 10.0
	audio_offset_input.step = 0.01
	audio_offset_input.value = 0.0
	audio_offset_input.custom_minimum_size = Vector2(90, 0)
	audio_offset_input.tooltip_text = "Audio offset in seconds\nPositive = audio plays later"
	audio_offset_input.value_changed.connect(_on_audio_offset_changed)
	tool_bar_2.add_child(audio_offset_input)

func _on_audio_offset_changed(value: float):
	EditorData.audio_offset = value
	# If playing, restart to apply offset immediately
	if EditorData.is_playing:
		var current_pos = EditorData.current_time
		audio_player.stop()
		playback_position = current_pos
		audio_player.play(max(0.0, playback_position - EditorData.audio_offset))
		time_begin = Time.get_ticks_usec()
		time_delay = AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()
		time_begin -= int(playback_position * 1_000_000.0)

func setup_snap_toggle():
	# Create snap toggle checkbox
	snap_toggle = CheckButton.new()
	snap_toggle.text = "🔒"  # Lock symbol
	snap_toggle.button_pressed = true
	snap_toggle.tooltip_text = "Enable/disable grid snapping"
	snap_toggle.toggled.connect(_on_snap_toggled)
	tool_bar_2.add_child(snap_toggle)

func _on_snap_toggled(enabled: bool):
	EditorData.snap_enabled = enabled

func setup_lane_height_slider():
	# Create label with symbol
	var label = Label.new()
	label.text = "↕"  # Up-down arrow
	label.add_theme_font_size_override("font_size", 16)
	label.tooltip_text = "Lane height"
	tool_bar_2.add_child(label)
	
	# Create slider for lane height
	lane_height_slider = HSlider.new()
	lane_height_slider.min_value = 15
	lane_height_slider.max_value = 50
	lane_height_slider.step = 1
	lane_height_slider.value = 20
	lane_height_slider.custom_minimum_size = Vector2(80, 32)
	lane_height_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lane_height_slider.tooltip_text = "Adjust lane height"
	lane_height_slider.value_changed.connect(_on_lane_height_changed)
	tool_bar_2.add_child(lane_height_slider)

func setup_playback_speed_control():
	# Create label with symbol
	var label = Label.new()
	label.text = "⏳"  # Hourglass symbol
	label.add_theme_font_size_override("font_size", 16)
	label.tooltip_text = "Playback speed"
	$ToolBar.add_child(label)
	
	# Create option button for playback speed
	speed_selector = OptionButton.new()
	speed_selector.add_item("0.25x", 0)
	speed_selector.add_item("0.5x", 1)
	speed_selector.add_item("0.75x", 2)
	speed_selector.add_item("1x", 3)
	speed_selector.add_item("1.25x", 4)
	speed_selector.add_item("1.5x", 5)
	speed_selector.add_item("2x", 6)
	speed_selector.select(3)  # Default to 1x
	speed_selector.custom_minimum_size = Vector2(70, 0)
	speed_selector.tooltip_text = "Playback speed"
	speed_selector.item_selected.connect(_on_speed_changed)
	$ToolBar.add_child(speed_selector)

func _on_speed_changed(index: int):
	var speeds = [0.25, 0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
	var speed = speeds[index]
	var old_speed = EditorData.playback_speed
	
	audio_player.pitch_scale = speed
	EditorData.playback_speed = speed  # Store speed in EditorData
	
	# If currently playing, restart to apply new speed without jumping
	if EditorData.is_playing:
		var current_pos = EditorData.current_time
		audio_player.stop()
		
		# Ensure audio generator players are still running
		if metronome_player and not metronome_player.playing:
			metronome_player.play()
		if note_hit_player and not note_hit_player.playing:
			note_hit_player.play()
		
		# Start audio at correct position
		var audio_start_position = max(0.0, current_pos - EditorData.audio_offset)
		audio_player.play(audio_start_position)
		
		# Reset time_begin accounting for new speed
		time_begin = Time.get_ticks_usec() - int((current_pos / speed) * 1_000_000.0)
		time_delay = AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()
	
	print("Playback speed: %.2fx" % speed)

func setup_volume_control():
	# Create label with symbol
	var label = Label.new()
	label.text = "🔊"  # Speaker symbol
	label.add_theme_font_size_override("font_size", 16)
	label.tooltip_text = "Audio volume"
	$ToolBar.add_child(label)
	
	# Create slider for volume
	volume_slider = HSlider.new()
	volume_slider.min_value = 0
	volume_slider.max_value = 100
	volume_slider.step = 1
	volume_slider.value = 80  # Default 80%
	volume_slider.custom_minimum_size = Vector2(80, 32)
	volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	volume_slider.tooltip_text = "Audio volume"
	volume_slider.value_changed.connect(_on_volume_changed)
	$ToolBar.add_child(volume_slider)
	
	# Set initial volume
	_on_volume_changed(80)

func _on_volume_changed(value: float):
	# Convert 0-100 to dB scale
	# 0% = -80 dB (effectively silent)
	# 100% = 0 dB (full volume)
	if value <= 0:
		audio_player.volume_db = -80
	else:
		# Logarithmic scale: -40 dB at 10%, 0 dB at 100%
		audio_player.volume_db = linear_to_db(value / 100.0)

func setup_tap_tempo():
	# Create tap tempo button in main toolbar
	tap_tempo_button = Button.new()
	tap_tempo_button.text = "Tap Tempo"
	tap_tempo_button.tooltip_text = "Tap along to the beat to detect BPM and auto-set offset\n(Tap at least 4 times)"
	tap_tempo_button.pressed.connect(_on_tap_tempo_pressed)
	$ToolBar.add_child(tap_tempo_button)
	
	# Move to position after division selector
	$ToolBar.move_child(tap_tempo_button, 3)

func setup_waveform_amplitude_slider():
	# Create label with symbol
	var label = Label.new()
	label.text = "〰"  # Wave symbol
	label.add_theme_font_size_override("font_size", 16)
	label.tooltip_text = "Waveform amplitude"
	$ToolBar.add_child(label)
	
	# Create slider for waveform amplitude
	waveform_amplitude_slider = HSlider.new()
	waveform_amplitude_slider.min_value = 0.1
	waveform_amplitude_slider.max_value = 5.0
	waveform_amplitude_slider.step = 0.1
	waveform_amplitude_slider.value = 1.0  # Default 1x
	waveform_amplitude_slider.custom_minimum_size = Vector2(80, 32)
	waveform_amplitude_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	waveform_amplitude_slider.tooltip_text = "Adjust waveform amplitude display"
	waveform_amplitude_slider.value_changed.connect(_on_waveform_amplitude_changed)
	$ToolBar.add_child(waveform_amplitude_slider)

func _on_waveform_amplitude_changed(value: float):
	EditorData.waveform_amplitude = value
	timeline_canvas.queue_redraw()  # Redraw to update waveform

func setup_fx_button():
	# Create FX settings button in toolbar2 - will be last element
	fx_button = Button.new()
	fx_button.text = "◊"  # Diamond symbol
	fx_button.tooltip_text = "Post-Processing Effects"
	fx_button.pressed.connect(_on_fx_button_pressed)
	fx_button.custom_minimum_size = Vector2(40, 32)
	tool_bar_2.add_child(fx_button)

func _on_fx_button_pressed():
	if not fx_settings_panel:
		print("Error: fx_settings_panel not assigned. Please set it in the Inspector.")
		return
	
	if not fx_color_rect:
		print("Error: fx_color_rect not assigned. Please set it in the Inspector.")
		return
	
	# Toggle visibility of the panel
	fx_settings_panel.visible = !fx_settings_panel.visible
	
	# Load shader values when opening
	if fx_settings_panel.visible:
		if fx_color_rect.material and fx_color_rect.material is ShaderMaterial:
			fx_settings_panel.set_shader_material(fx_color_rect.material)
			fx_settings_panel.load_shader_values()
		else:
			print("Error: fx_color_rect doesn't have a ShaderMaterial")



func _on_tap_tempo_pressed():
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Get current audio position
	var audio_time = EditorData.current_time
	
	# Reset if too much time has passed since last tap
	if tap_times.size() > 0:
		var last_tap = tap_times[tap_times.size() - 1]
		if current_time - last_tap > MAX_TAP_INTERVAL:
			tap_times.clear()
			tap_audio_positions.clear()
			print("Tap tempo reset - start tapping again")
			return
	
	# Record this tap
	tap_times.append(current_time)
	tap_audio_positions.append(audio_time)
	
	print("Tap %d recorded" % tap_times.size())
	
	# Need at least 4 taps to calculate BPM accurately
	if tap_times.size() < 4:
		print("Keep tapping... (need %d more)" % (4 - tap_times.size()))
		return
	
	# Calculate BPM from tap intervals
	var intervals: Array[float] = []
	for i in range(1, tap_times.size()):
		var interval = tap_times[i] - tap_times[i - 1]
		intervals.append(interval)
	
	# Average interval
	var avg_interval = 0.0
	for interval in intervals:
		avg_interval += interval
	avg_interval /= intervals.size()
	
	# Convert to BPM (60 seconds / interval)
	var detected_bpm = 60.0 / avg_interval
	
	# Round to nearest 0.1
	detected_bpm = round(detected_bpm * 10.0) / 10.0
	
	# Calculate audio offset
	# The first tap indicates where beat 0 should be
	# offset = (audio_time at first tap) - (time since first tap in beats)
	var time_since_first_tap = tap_audio_positions[tap_audio_positions.size() - 1] - tap_audio_positions[0]
	var beats_since_first_tap = time_since_first_tap * detected_bpm / 60.0
	var fractional_beat = fmod(beats_since_first_tap, 1.0)
	
	# Calculate offset: how far into the first beat were we when we started tapping
	var beat_duration = 60.0 / detected_bpm
	var offset = tap_audio_positions[0] - (floor(beats_since_first_tap) * beat_duration)
	
	# IMPORTANT: Temporarily disable audio restart when changing offset
	var was_playing = EditorData.is_playing
	var saved_time = EditorData.current_time
	
	# Apply detected BPM first
	EditorData.bpm = detected_bpm
	bpm_input.value = detected_bpm
	
	# For offset, we want the first tap to align with a beat
	# So offset should be the audio time at first tap modulo beat duration
	var aligned_offset = fmod(tap_audio_positions[0], beat_duration)
	
	# Apply offset without triggering audio restart
	EditorData.audio_offset = -aligned_offset
	if audio_offset_input:
		# Block signal to prevent audio restart
		audio_offset_input.value_changed.disconnect(_on_audio_offset_changed)
		audio_offset_input.value = -aligned_offset
		audio_offset_input.value_changed.connect(_on_audio_offset_changed)
	
	print("✓ Tap tempo complete!")
	print("  Detected BPM: %.1f" % detected_bpm)
	print("  Audio offset: %.3f seconds" % -aligned_offset)
	print("  Based on %d taps" % tap_times.size())
	
	# Clear taps for next use
	tap_times.clear()
	tap_audio_positions.clear()
	
	# Update timeline
	EditorData.bpm_changed.emit(detected_bpm)
	timeline_canvas.queue_redraw()

func _on_lane_height_changed(value: float):
	EditorData.lane_height = int(value)
	EditorData.lane_height_changed.emit(int(value))
	timeline_canvas.queue_redraw()

func setup_time_display():
	# Create time label in main toolbar
	time_label = Label.new()
	time_label.text = "0:00/0:00"
	time_label.add_theme_font_size_override("font_size", 13)
	time_label.custom_minimum_size = Vector2(90, 0)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.tooltip_text = "Current time / Total duration"
	$ToolBar.add_child(time_label)
	
func setup_file_menu():
	var popup = file_menu.get_popup()
	popup.add_item("New", 0)
	popup.add_separator()
	popup.add_item("Import MIDI File...", 1)
	popup.add_item("Load Audio File...", 2)
	popup.add_separator()
	popup.add_item("Export MIDI File...", 3)
	popup.add_separator()
	popup.add_item("Fix Zero-Length Notes", 4)
	popup.id_pressed.connect(_on_file_menu_selected)

func setup_division_selector():
	division_selector.add_item("1/4", 0)
	division_selector.add_item("1/8", 1)
	division_selector.add_item("1/8T", 2)  # Eighth note triplets
	division_selector.add_item("1/16", 3)
	division_selector.add_item("1/16T", 4)  # Sixteenth note triplets (sextuplets)
	division_selector.add_item("1/32", 5)
	division_selector.add_item("1/32T", 6)  # 32nd note triplets
	division_selector.add_item("1/64", 7)
	division_selector.add_item("1/64T", 8)  # 64th note triplets
	division_selector.select(3)  # Default to 1/16
	division_selector.item_selected.connect(_on_division_changed)

func _on_division_changed(index: int):
	# Maps indices to divisions (notes per beat)
	# Regular: 1/4=1, 1/8=2, 1/16=4, 1/32=8, 1/64=16
	# Triplets: 1/8T=3, 1/16T=6, 1/32T=12, 1/64T=24
	var divisions = [1, 2, 3, 4, 6, 8, 12, 16, 24]
	EditorData.snap_division = divisions[index]
	timeline_canvas.queue_redraw()

func _on_file_menu_selected(id: int):
	match id:
		0: new_project()
		1: import_midi()
		2: load_audio_file()
		3: export_midi()
		4: timeline_canvas.fix_zero_length_notes()

func import_midi():
	# Import MIDI from external file system
	var dialog = FileDialog.new()
	add_child(dialog)
	dialog.access = FileDialog.ACCESS_FILESYSTEM  # Allow access to any file
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = ["*.mid, *.midi ; MIDI Files"]
	dialog.file_selected.connect(_on_midi_file_selected)
	dialog.popup_centered_ratio(0.6)

func _on_midi_file_selected(path: String):
	# Load using G0retZ library

	var midi_resource = load(path)
	
	if not midi_resource:
		push_error("Failed to load MIDI file")
		return
	
	# Check if we need to load from bytes instead
	if "data" in midi_resource:
		EditorData.midi_data = midi_resource.data
	else:
		EditorData.midi_data = midi_resource
	
	if not EditorData.midi_data:
		push_error("Failed to parse MIDI data")
		return
	
	
	var ppq_loaded = false
	if "header" in EditorData.midi_data:
		var header = EditorData.midi_data.header
		if header and "ticks_per_beat" in header:
			if header.ticks_per_beat > 0:
				EditorData.ppq = header.ticks_per_beat
				print("Loaded PPQ from MIDI file: ", EditorData.ppq)
				ppq_loaded = true
	
	if not ppq_loaded:
		print("Warning: Could not read PPQ from file, using default: ", EditorData.ppq)
	
	# Extract BPM from tempo events
	var bpm_found = false
	if "tracks" in EditorData.midi_data:
		for track in EditorData.midi_data.tracks:
			if not track or not "events" in track:
				continue
			for event in track.events:
				# Check for Tempo event object
				if event is MidiData.Tempo:
					var us_per_beat = event.us_per_beat
					EditorData.bpm = 60_000_000.0 / us_per_beat
					bpm_input.value = EditorData.bpm
					bpm_found = true
					print("Loaded BPM: ", EditorData.bpm)
					break
			if bpm_found:
				break
	
	if not bpm_found:
		print("No tempo event found in MIDI file, using default BPM: ", EditorData.bpm)
	
	# Convert MIDI events to editor notes
	parse_midi_to_notes()
	
	# Update canvas size for loaded notes
	timeline_canvas.update_canvas_size()
	
	# Reset undo history after loading
	timeline_canvas.reset_history()

func parse_midi_to_notes():
	EditorData.notes.clear()
	
	if not EditorData.midi_data:
		push_error("No MIDI data to parse")
		return
	
	if not "tracks" in EditorData.midi_data or not EditorData.midi_data.tracks:
		push_error("No tracks found in MIDI data")
		return
	
	print("\n=== MIDI Import Debug ===")
	print("PPQ: %d" % EditorData.ppq)
	print("BPM: %.2f" % EditorData.bpm)
	
	# First pass: look for audio offset text event
	var imported_offset = 0.0
	var offset_ticks = 0
	var offset_found = false
	for track in EditorData.midi_data.tracks:
		if not track or not "events" in track:
			continue
		for event in track.events:
			# Check for text meta event (MidiData.Text)
			if event is MidiData.Text:
				var text = event.text if "text" in event else ""
				if text.begins_with("AUDIO_OFFSET="):
					imported_offset = float(text.substr(13))  # Skip "AUDIO_OFFSET="
					var offset_beats = EditorData.seconds_to_beats(abs(imported_offset))
					offset_ticks = EditorData.beats_to_ticks(offset_beats)
					print("Found audio offset in MIDI: %.3f seconds (%d ticks)" % [imported_offset, offset_ticks])
					offset_found = true
					break
		if offset_found:
			break
	
	# Set offset (or reset to 0 if not found)
	if audio_offset_input:
		audio_offset_input.value = imported_offset
	EditorData.audio_offset = imported_offset
	if not offset_found:
		print("No audio offset found in MIDI, defaulting to 0.0")
	
	var debug_note_events = {}  # Track events for debugging {note_number: [events]}
	
	for track in EditorData.midi_data.tracks:
		if not track or not "events" in track:
			continue
			
		var current_tick = 0
		var active_notes = {}  # {note_number: {tick: int, velocity: int}}
		var completed_at_tick = {}  # Track which notes were completed at which tick
		
		for event in track.events:
			if not event:
				continue
				
			# All events have delta_time property
			if "delta_time" in event:
				current_tick += event.delta_time
			
			# Handle NoteOn events
			if event is MidiData.NoteOn:
				if event.velocity > 0:
					# Initialize debug tracking for this note if needed
					if not event.note in debug_note_events:
						debug_note_events[event.note] = []
					debug_note_events[event.note].append("Tick %d: NoteOn vel=%d" % [current_tick, event.velocity])
					
					# If note is already active, complete it first before starting new one
					if event.note in active_notes:
						debug_note_events[event.note].append("  -> Completing previous active note")
						create_note_from_active(active_notes, event.note, current_tick, offset_ticks)
						# Mark that we completed this note at this tick
						completed_at_tick[event.note] = current_tick
					# Store note-on event
					active_notes[event.note] = {
						"tick": current_tick,
						"velocity": event.velocity
					}
				else:
					# NoteOn with velocity 0 = NoteOff
					if not event.note in debug_note_events:
						debug_note_events[event.note] = []
					debug_note_events[event.note].append("Tick %d: NoteOn vel=0 (NoteOff)" % current_tick)
					# Check if we already completed this note at this tick
					if event.note in completed_at_tick and completed_at_tick[event.note] == current_tick:
						debug_note_events[event.note].append("  -> Skipping redundant NoteOff (already completed)")
						continue
					if event.note in active_notes:
						create_note_from_active(active_notes, event.note, current_tick, offset_ticks)
			
			# Handle NoteOff events
			elif event is MidiData.NoteOff:
				if not event.note in debug_note_events:
					debug_note_events[event.note] = []
				debug_note_events[event.note].append("Tick %d: NoteOff" % current_tick)
				# Check if we already completed this note at this tick
				if event.note in completed_at_tick and completed_at_tick[event.note] == current_tick:
					debug_note_events[event.note].append("  -> Skipping redundant NoteOff (already completed)")
					continue
				if event.note in active_notes:
					create_note_from_active(active_notes, event.note, current_tick, offset_ticks)
	
	# Print debug events for notes with bar note velocity (9)
	print("\n--- Event Sequence (first 3 notes of each type) ---")
	for note_num in debug_note_events.keys():
		var events = debug_note_events[note_num]
		if events.size() > 0:
			print("MIDI Note %d:" % note_num)
			for i in range(min(6, events.size())):  # First 6 events per note
				print("  " + events[i])
	print("---\n")
	
	print("Loaded %d notes from MIDI file" % EditorData.notes.size())
	print("========================\n")

func create_note_from_active(active_notes: Dictionary, note_number: int, current_tick: int, offset_ticks: int = 0):
	var note_on_data = active_notes[note_number]
	var start_tick = note_on_data["tick"]
	var duration_ticks = current_tick - start_tick
	
	# Shift note back by offset when importing
	start_tick = max(0, start_tick - offset_ticks)
	
	var beat_pos = EditorData.ticks_to_beats(start_tick)
	var duration_beats = EditorData.ticks_to_beats(duration_ticks)
	
	# Enforce minimum note duration
	duration_beats = max(duration_beats, EditorData.MIN_NOTE_DURATION)
	
	# Find which lane this MIDI note belongs to
	var lane = EditorData.LANE_MIDI_NOTES.find(note_number)
	if lane == -1:
		# Skip notes not in our lane mapping
		active_notes.erase(note_number)
		return
	
	var clock_pos = EditorData.get_clock_position_for_lane(lane)
	var vel = note_on_data["velocity"]
	
	# Debug first few notes
	if EditorData.notes.size() < 3:
		print("  Note: MIDI %d -> Lane %d, Beat %.3f, Duration %.3f beats (ticks: %d)" % 
			[note_number, lane, beat_pos, duration_beats, duration_ticks])
	
	var note_data = EditorData.NoteData.new(
		beat_pos, lane, clock_pos, vel, note_number, duration_beats
	)
	EditorData.add_note(note_data)
	
	active_notes.erase(note_number)

func new_project():
	EditorData.notes.clear()
	EditorData.bpm = 120.0
	bpm_input.value = 120.0
	EditorData.audio_offset = 0.0
	if audio_offset_input:
		audio_offset_input.value = 0.0
	EditorData.notes_changed.emit()
	
	# Reset undo history for new project
	timeline_canvas.reset_history()

func _on_bpm_changed(new_bpm: float):
	bpm_input.value = new_bpm
	timeline_canvas.queue_redraw()

func load_audio_file():
	var dialog = FileDialog.new()
	add_child(dialog)
	dialog.access = FileDialog.ACCESS_FILESYSTEM  # Allow access to any file
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.filters = ["*.ogg, *.mp3, *.wav ; Audio Files"]
	dialog.file_selected.connect(_on_audio_file_selected)
	dialog.popup_centered_ratio(0.6)

func _on_audio_file_selected(path: String):
	var extension = path.get_extension().to_lower()
	var stream = null
	
	if extension == "ogg":
		stream = AudioStreamOggVorbis.load_from_file(path)
	elif extension == "wav":
		stream = AudioStreamWAV.load_from_file(path)
	else:
		push_error("Unsupported audio format. Please use OGG or WAV files.")
		return
	
	if stream:
		audio_player.stream = stream
		EditorData.audio_file_path = path
		print("Audio loaded successfully: ", path)
		
		# Trigger waveform generation
		timeline_canvas.waveform_needs_update = true
		timeline_canvas.queue_redraw()
	else:
		push_error("Failed to load audio file. Make sure it's a valid audio file.")

func _on_play_pressed():
	if not audio_player.stream:
		push_warning("Load an audio file first")
		return
	
	# Play button only starts/resumes playback, never stops
	if not EditorData.is_playing:
		EditorData.is_playing = true
		time_begin = Time.get_ticks_usec()
		time_delay = AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()
		
		# Reset metronome and note hit tracking
		last_metronome_beat = -1
		triggered_notes.clear()
		
		# Start the audio generator players
		if metronome_player and not metronome_player.playing:
			metronome_player.play()
		if note_hit_player and not note_hit_player.playing:
			note_hit_player.play()
		
		# Apply audio offset: timeline position - offset = audio position
		# If offset is positive, audio plays later (start audio earlier in file)
		var audio_start_position = max(0.0, playback_position - EditorData.audio_offset)
		audio_player.play(audio_start_position)
		
		# Adjust time_begin to account for starting position AND playback speed
		# Since we multiply by speed in _process, we need to divide here
		time_begin -= int((playback_position / EditorData.playback_speed) * 1_000_000.0)

func _on_pause_pressed():
	# Pause button only pauses, never resumes
	if EditorData.is_playing:
		EditorData.is_playing = false
		playback_position = EditorData.current_time
		audio_player.stop()
		
		# Stop audio generator players
		if metronome_player:
			metronome_player.stop()
		if note_hit_player:
			note_hit_player.stop()

func toggle_playback():
	# Toggle between play and pause
	if not audio_player.stream:
		push_warning("Load an audio file first")
		return
	
	if EditorData.is_playing:
		_on_pause_pressed()
	else:
		_on_play_pressed()

func cycle_division(direction: int):
	# Cycle through snap divisions
	# direction: -1 for Q (decrease), +1 for E (increase)
	var current_index = division_selector.selected
	var new_index = current_index + direction
	
	# Wrap around
	if new_index < 0:
		new_index = division_selector.item_count - 1
	elif new_index >= division_selector.item_count:
		new_index = 0
	
	division_selector.select(new_index)
	_on_division_changed(new_index)
	
	# Print feedback
	var division_names = ["1/4", "1/8", "1/8T", "1/16", "1/16T", "1/32", "1/32T", "1/64", "1/64T"]
	print("Snap division: %s" % division_names[new_index])

func stop_playback():
	# Full stop - reset to beginning
	EditorData.is_playing = false
	audio_player.stop()
	
	# Stop audio generator players
	if metronome_player:
		metronome_player.stop()
	if note_hit_player:
		note_hit_player.stop()
	
	playback_position = 0.0
	EditorData.current_time = 0.0
	EditorData.playback_position_changed.emit(0.0)
	update_time_display()

func seek_to_time(time_seconds: float):
	# Seek to a specific time
	var was_playing = EditorData.is_playing
	
	if EditorData.is_playing:
		audio_player.stop()
	
	playback_position = clamp(time_seconds, 0.0, get_audio_duration())
	EditorData.current_time = playback_position
	EditorData.playback_position_changed.emit(playback_position)
	
	# Reset tracking for metronome and note hits
	last_metronome_beat = -1
	triggered_notes.clear()
	
	if was_playing:
		# Ensure audio generator players are running
		if metronome_player and not metronome_player.playing:
			metronome_player.play()
		if note_hit_player and not note_hit_player.playing:
			note_hit_player.play()
		
		# Resume playback from new position (with audio offset)
		var audio_start_position = max(0.0, playback_position - EditorData.audio_offset)
		audio_player.play(audio_start_position)
		# Account for playback speed when setting time_begin
		time_begin = Time.get_ticks_usec() - int((playback_position / EditorData.playback_speed) * 1_000_000.0)
		time_delay = AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()
	
	update_time_display()

func get_audio_duration() -> float:
	if audio_player.stream:
		return audio_player.stream.get_length()
	return 0.0

@warning_ignore("unused_parameter")
func _process(delta):
	if fx_color_rect and fx_color_rect.material and fx_color_rect.material is ShaderMaterial:
		var time = Time.get_ticks_msec() / 1000.0
		fx_color_rect.material.set_shader_parameter("time", time)
	
	if EditorData.is_playing:
		if audio_player.playing:
			var time = (Time.get_ticks_usec() - time_begin) / 1000000.0
			time -= time_delay
			time = max(0, time)
			
			# Factor in playback speed - slower speed means timeline moves slower
			time = time * EditorData.playback_speed
			
			EditorData.current_time = time
			EditorData.playback_position_changed.emit(time)
			
			# Handle metronome clicks
			if EditorData.metronome_enabled:
				handle_metronome(time)
			
			# Handle note hit sounds
			if EditorData.note_hits_enabled:
				handle_note_hits(time)
			
			# Auto-scroll timeline
			update_timeline_scroll()
			
			# Update time display
			update_time_display()
		else:
			# Audio finished playing
			stop_playback()
	else:
		# Not playing, but update time display if we have audio
		if audio_player.stream:
			update_time_display()

func update_time_display():
	if time_label and audio_player.stream:
		var current = format_time(EditorData.current_time)
		var total = format_time(get_audio_duration())
		time_label.text = "%s/%s" % [current, total]  # Compact format without spaces

func format_time(seconds: float) -> String:
	var mins = int(seconds) / 60
	var secs = int(seconds) % 60
	return "%d:%02d" % [mins, secs]

func update_timeline_scroll():
	var current_beat = EditorData.seconds_to_beats(EditorData.current_time)
	var pixel_pos = timeline_canvas.beat_to_pixel(current_beat)
	
	# Center the playhead in viewport
	var viewport_width = scroll_container.size.x
	scroll_container.scroll_horizontal = int(pixel_pos - viewport_width / 2)

# Add to midi_editor.gd

func export_midi():
	# Export MIDI to external file system
	if EditorData.notes.is_empty():
		push_warning("No notes to export")
		return
	
	var dialog = FileDialog.new()
	add_child(dialog)
	dialog.access = FileDialog.ACCESS_FILESYSTEM  # Allow saving anywhere
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.filters = ["*.mid ; MIDI Files"]
	dialog.file_selected.connect(_on_save_file_selected)
	dialog.popup_centered_ratio(0.6)

func _on_save_file_selected(path: String):
	var midi_bytes = create_midi_bytes()
	
	var file = FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_buffer(midi_bytes)
		file.close()
		print("MIDI saved successfully to: ", path)
	else:
		push_error("Failed to open file for writing: ", path)

func create_midi_bytes() -> PackedByteArray:
	var bytes = PackedByteArray()
	
	# Write MIDI header
	bytes.append_array("MThd".to_ascii_buffer())
	bytes.append_array(int_to_bytes(6, 4))  # Header size
	bytes.append_array(int_to_bytes(0, 2))  # Format 0 (single track)
	bytes.append_array(int_to_bytes(1, 2))  # Number of tracks (1 track with tempo + notes)
	bytes.append_array(int_to_bytes(EditorData.ppq, 2))  # Ticks per beat
	
	# Write single combined track with tempo and notes
	bytes.append_array(create_combined_track_bytes())
	
	return bytes

func create_combined_track_bytes() -> PackedByteArray:
	var track_data = PackedByteArray()
	
	# Start with tempo event at tick 0
	track_data.append_array(int_to_variable_length(0))  # Delta time = 0
	track_data.append(0xFF)  # Meta event
	track_data.append(0x51)  # Tempo
	track_data.append(0x03)  # Length = 3
	var us_per_beat = int(60_000_000.0 / EditorData.bpm)
	track_data.append((us_per_beat >> 16) & 0xFF)
	track_data.append((us_per_beat >> 8) & 0xFF)
	track_data.append(us_per_beat & 0xFF)
	
	# Add audio offset text event if offset is not zero
	var offset_ticks = 0
	if EditorData.audio_offset != 0.0:
		var offset_beats = EditorData.seconds_to_beats(abs(EditorData.audio_offset))
		offset_ticks = EditorData.beats_to_ticks(offset_beats)
		
		# Write text meta event: FF 01 <length> <text>
		track_data.append_array(int_to_variable_length(0))  # Delta time = 0 (right after tempo)
		track_data.append(0xFF)  # Meta event
		track_data.append(0x01)  # Text event
		var text = "AUDIO_OFFSET=%.3f" % EditorData.audio_offset
		track_data.append(text.length())  # Length
		track_data.append_array(text.to_ascii_buffer())
		
		print("Exporting with audio offset: %.3f seconds (%d ticks)" % [EditorData.audio_offset, offset_ticks])
	
	# Sort all notes by time
	var all_notes = EditorData.notes.duplicate()
	all_notes.sort_custom(func(a, b): return a.beat_position < b.beat_position)
	
	# Create note events and shift by offset
	var events = []
	for note in all_notes:
		var start_tick = EditorData.beats_to_ticks(note.beat_position) + offset_ticks
		var end_tick = EditorData.beats_to_ticks(note.beat_position + note.duration) + offset_ticks
		
		# Note On event
		events.append({
			"tick": start_tick,
			"type": "note_on",
			"note": note.midi_note,
			"velocity": note.velocity
		})
		
		# Note Off event
		events.append({
			"tick": end_tick,
			"type": "note_off",
			"note": note.midi_note
		})
	
	# Sort events by tick, with NoteOff before NoteOn at same tick
	# This ensures sustain notes properly end before new notes start
	events.sort_custom(func(a, b): 
		if a["tick"] != b["tick"]:
			return a["tick"] < b["tick"]
		# Same tick: NoteOff (type="note_off") comes before NoteOn (type="note_on")
		# Alphabetically "note_off" < "note_on" (since 'f' < 'n')
		return a["type"] < b["type"]
	)
	
	# Debug: Print sustain lane (MIDI note 36, lane 20) events to verify ordering
	print("\n=== Sustain Lane Events (MIDI Note 36) ===")
	for event in events:
		if event["note"] == 36:
			var event_type = "ON " if event["type"] == "note_on" else "OFF"
			var beat = EditorData.ticks_to_beats(event["tick"] - offset_ticks)
			print("Tick %d (Beat %.3f): %s" % [event["tick"], beat, event_type])
	print("==========================================\n")
	
	# Write note events with delta times (starting from tick 0 after tempo)
	var last_tick = 0
	for event in events:
		var delta = event["tick"] - last_tick
		
		if event["type"] == "note_on":
			track_data.append_array(int_to_variable_length(delta))
			track_data.append(0x90)  # Note on, channel 0
			track_data.append(event["note"])
			track_data.append(event["velocity"])
		else:  # note_off
			track_data.append_array(int_to_variable_length(delta))
			track_data.append(0x80)  # Note off, channel 0
			track_data.append(event["note"])
			track_data.append(0x00)  # Velocity 0 for note off
		
		last_tick = event["tick"]
	
	# End of track
	track_data.append_array(int_to_variable_length(0))
	track_data.append(0xFF)
	track_data.append(0x2F)
	track_data.append(0x00)
	
	# Wrap in MTrk chunk
	var bytes = PackedByteArray()
	bytes.append_array("MTrk".to_ascii_buffer())
	bytes.append_array(int_to_bytes(track_data.size(), 4))
	bytes.append_array(track_data)
	
	return bytes

func create_tempo_track_bytes() -> PackedByteArray:
	var track_data = PackedByteArray()
	
	# Tempo event (FF 51 03 tttttt)
	track_data.append_array(int_to_variable_length(0))  # Delta time = 0
	track_data.append(0xFF)  # Meta event
	track_data.append(0x51)  # Tempo
	track_data.append(0x03)  # Length = 3
	var us_per_beat = int(60_000_000.0 / EditorData.bpm)
	track_data.append((us_per_beat >> 16) & 0xFF)
	track_data.append((us_per_beat >> 8) & 0xFF)
	track_data.append(us_per_beat & 0xFF)
	
	# End of track (FF 2F 00)
	track_data.append_array(int_to_variable_length(0))
	track_data.append(0xFF)
	track_data.append(0x2F)
	track_data.append(0x00)
	
	# Wrap in MTrk chunk
	var bytes = PackedByteArray()
	bytes.append_array("MTrk".to_ascii_buffer())
	bytes.append_array(int_to_bytes(track_data.size(), 4))
	bytes.append_array(track_data)
	
	return bytes

func create_all_notes_track_bytes() -> PackedByteArray:
	var track_data = PackedByteArray()
	
	# Sort all notes by time
	var all_notes = EditorData.notes.duplicate()
	all_notes.sort_custom(func(a, b): return a.beat_position < b.beat_position)
	
	# Create events: each note gets a note-on and note-off
	var events = []
	
	for note in all_notes:
		var start_tick = EditorData.beats_to_ticks(note.beat_position)
		var end_tick = EditorData.beats_to_ticks(note.beat_position + note.duration)
		
		# Note On event
		events.append({
			"tick": start_tick,
			"type": "note_on",
			"note": note.midi_note,
			"velocity": note.velocity  # Use actual velocity
		})
		
		# Note Off event
		events.append({
			"tick": end_tick,
			"type": "note_off",
			"note": note.midi_note
		})
	
	# Sort events by tick
	events.sort_custom(func(a, b): return a["tick"] < b["tick"])
	
	# Write events with delta times
	var last_tick = 0
	for event in events:
		var delta = event["tick"] - last_tick
		
		if event["type"] == "note_on":
			track_data.append_array(int_to_variable_length(delta))
			track_data.append(0x90)  # Note on, channel 0
			track_data.append(event["note"])
			track_data.append(event["velocity"])  # This is the velocity!
		else:  # note_off
			track_data.append_array(int_to_variable_length(delta))
			track_data.append(0x80)  # Note off, channel 0
			track_data.append(event["note"])
			track_data.append(0x00)  # Velocity 0 for note off
		
		last_tick = event["tick"]
	
	# End of track
	track_data.append_array(int_to_variable_length(0))
	track_data.append(0xFF)
	track_data.append(0x2F)
	track_data.append(0x00)
	
	# Wrap in MTrk chunk
	var bytes = PackedByteArray()
	bytes.append_array("MTrk".to_ascii_buffer())
	bytes.append_array(int_to_bytes(track_data.size(), 4))
	bytes.append_array(track_data)
	
	return bytes

func show_message_popup(title: String, message: String):
	# Create a simple popup dialog to show messages to the user
	var dialog = AcceptDialog.new()
	dialog.title = title
	dialog.dialog_text = message
	dialog.min_size = Vector2(400, 200)
	add_child(dialog)
	dialog.popup_centered()
	
	# Auto-cleanup when closed
	dialog.confirmed.connect(func(): dialog.queue_free())
	dialog.canceled.connect(func(): dialog.queue_free())

func int_to_bytes(value: int, num_bytes: int) -> PackedByteArray:
	var bytes = PackedByteArray()
	for i in range(num_bytes):
		bytes.insert(0, value & 0xFF)
		value >>= 8
	return bytes

func int_to_variable_length(value: int) -> PackedByteArray:
	var bytes = PackedByteArray()
	bytes.append(value & 0x7F)
	value >>= 7
	
	while value > 0:
		bytes.insert(0, (value & 0x7F) | 0x80)
		value >>= 7
	
	return bytes

func setup_metronome_toggle():
	# Create metronome toggle in toolbar2
	metronome_toggle = CheckButton.new()
	
	# Try to load metronome icon
	var metronome_icon = load("res://resources/metronome.png")
	if metronome_icon:
		metronome_toggle.icon = metronome_icon

	else:
		metronome_toggle.text = "🎵"  # Fallback to music note
	
	metronome_toggle.button_pressed = false
	metronome_toggle.tooltip_text = "Metronome click during playback"
	metronome_toggle.toggled.connect(_on_metronome_toggled)
	tool_bar_2.add_child(metronome_toggle)
	
	# Volume slider for metronome
	metronome_volume_slider = HSlider.new()
	metronome_volume_slider.min_value = 0
	metronome_volume_slider.max_value = 100
	metronome_volume_slider.step = 1
	metronome_volume_slider.value = 50
	metronome_volume_slider.custom_minimum_size = Vector2(60, 32)
	metronome_volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	metronome_volume_slider.tooltip_text = "Metronome volume"
	metronome_volume_slider.value_changed.connect(_on_metronome_volume_changed)
	tool_bar_2.add_child(metronome_volume_slider)

func _on_metronome_volume_changed(value: float):
	if metronome_player:
		if value <= 0:
			metronome_player.volume_db = -80
		else:
			# Boost volume: 0 dB at 50%, up to +10 dB at 100%
			metronome_player.volume_db = linear_to_db(value / 100.0) + 5

func _on_metronome_toggled(enabled: bool):
	EditorData.metronome_enabled = enabled

func setup_note_hits_toggle():
	# Create note hits toggle in toolbar2
	note_hits_toggle = CheckButton.new()
	note_hits_toggle.text = "♪"  # Single music note
	note_hits_toggle.button_pressed = false
	note_hits_toggle.tooltip_text = "Play sound when notes trigger during playback"
	note_hits_toggle.toggled.connect(_on_note_hits_toggled)
	tool_bar_2.add_child(note_hits_toggle)
	
	# Volume slider for note hits
	note_hits_volume_slider = HSlider.new()
	note_hits_volume_slider.min_value = 0
	note_hits_volume_slider.max_value = 100
	note_hits_volume_slider.step = 1
	note_hits_volume_slider.value = 40
	note_hits_volume_slider.custom_minimum_size = Vector2(60, 32)
	note_hits_volume_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	note_hits_volume_slider.tooltip_text = "Note hit volume"
	note_hits_volume_slider.value_changed.connect(_on_note_hits_volume_changed)
	tool_bar_2.add_child(note_hits_volume_slider)

func _on_note_hits_volume_changed(value: float):
	if note_hit_player:
		if value <= 0:
			note_hit_player.volume_db = -80
		else:
			# Boost volume: 0 dB at 50%, up to +6 dB at 100%
			note_hit_player.volume_db = linear_to_db(value / 100.0) + 3

func _on_note_hits_toggled(enabled: bool):
	EditorData.note_hits_enabled = enabled

func setup_time_signature_controls():
	# Create label with symbol
	var label = Label.new()
	label.text = "♩"  # Quarter note
	label.add_theme_font_size_override("font_size", 16)
	label.tooltip_text = "Time signature"
	tool_bar_2.add_child(label)
	
	# Create numerator spinbox
	time_sig_numerator = SpinBox.new()
	time_sig_numerator.min_value = 1
	time_sig_numerator.max_value = 32
	time_sig_numerator.value = 4
	time_sig_numerator.custom_minimum_size = Vector2(50, 0)
	time_sig_numerator.tooltip_text = "Beats per measure"
	time_sig_numerator.value_changed.connect(_on_time_signature_changed)
	tool_bar_2.add_child(time_sig_numerator)
	
	# Create separator label
	var slash = Label.new()
	slash.text = "/"
	slash.add_theme_font_size_override("font_size", 14)
	tool_bar_2.add_child(slash)
	
	# Create denominator spinbox  
	time_sig_denominator = SpinBox.new()
	time_sig_denominator.min_value = 1
	time_sig_denominator.max_value = 64
	time_sig_denominator.value = 4
	time_sig_denominator.custom_minimum_size = Vector2(50, 0)
	time_sig_denominator.tooltip_text = "Beat unit (4 = quarter note, 8 = eighth note)"
	time_sig_denominator.value_changed.connect(_on_time_signature_changed)
	tool_bar_2.add_child(time_sig_denominator)

func _on_time_signature_changed(_value: float):
	EditorData.time_signature_numerator = int(time_sig_numerator.value)
	EditorData.time_signature_denominator = int(time_sig_denominator.value)
	EditorData.time_signature_changed.emit(EditorData.time_signature_numerator, EditorData.time_signature_denominator)
	timeline_canvas.queue_redraw()

func setup_audio_players():
	# Create metronome audio player
	metronome_player = AudioStreamPlayer.new()
	add_child(metronome_player)
	
	# Generate a simple click sound (sine wave beep)
	var click_stream = AudioStreamGenerator.new()
	click_stream.mix_rate = 22050
	click_stream.buffer_length = 0.05  # 50ms click
	metronome_player.stream = click_stream
	metronome_player.volume_db = 0  # Default volume, controlled by slider
	
	# Create note hit audio player
	note_hit_player = AudioStreamPlayer.new()
	add_child(note_hit_player)
	
	# Use same click sound for note hits
	var hit_stream = AudioStreamGenerator.new()
	hit_stream.mix_rate = 22050
	hit_stream.buffer_length = 0.03  # 30ms click
	note_hit_player.stream = hit_stream
	note_hit_player.volume_db = 0  # Default volume, controlled by slider
	
	# Apply initial volume from sliders
	_on_metronome_volume_changed(50)  # Default 50%
	_on_note_hits_volume_changed(40)  # Default 40%

func handle_metronome(time: float):
	if not metronome_player:
		return
	
	var current_beat = EditorData.seconds_to_beats(time)
	var beat_number = int(floor(current_beat))
	
	# Play click on each beat
	if beat_number != last_metronome_beat and beat_number >= 0:
		last_metronome_beat = beat_number
		
		# Play metronome click using AudioStreamGeneratorPlayback
		var playback: AudioStreamGeneratorPlayback = metronome_player.get_stream_playback()
		if playback:
			# Generate sharp, clicky sound
			var sample_rate = 22050.0
			var click_samples = int(sample_rate * 0.003)  # 3ms for sharp click
			
			# Check if on downbeat (first beat of measure)
			var beats_per_measure = EditorData.get_beats_per_measure()
			var beat_in_measure = fmod(current_beat, beats_per_measure)
			
			# Downbeat is higher pitch
			var freq = 800.0  # Regular beat
			if beat_in_measure < 0.5:  # First beat of measure
				freq = 1200.0  # Downbeat
			
			# Sharp click with quick decay envelope
			for i in range(click_samples):
				var t = float(i) / sample_rate
				var envelope = 1.0 - (float(i) / click_samples)  # Quick decay
				var sample = sin(2.0 * PI * freq * t) * envelope * 0.4
				playback.push_frame(Vector2(sample, sample))

func handle_note_hits(time: float):
	if not note_hit_player:
		return
	
	var current_beat = EditorData.seconds_to_beats(time)
	
	# Check for notes that should trigger
	for note in EditorData.notes:
		# Only trigger for edge notes (8-19) and center note (7)
		if note.lane < 7 or note.lane > 19:
			continue
		
		# Skip if already triggered
		if note in triggered_notes:
			continue
		
		# Check if note should trigger now
		if note.beat_position <= current_beat and note.beat_position + 0.1 >= current_beat:
			triggered_notes.append(note)
			
			# Play note hit sound
			var playback: AudioStreamGeneratorPlayback = note_hit_player.get_stream_playback()
			if playback:
				# Generate higher-pitched, punchier beep
				var sample_rate = 22050.0
				var hit_samples = int(sample_rate * 0.008)  # 8ms for punchier sound
				var freq = 900.0  # Higher base frequency
				
				# Vary pitch based on lane
				if note.lane >= 8 and note.lane <= 19:  # Edge notes
					freq += (note.lane - 13) * 60  # More pitch variation
				elif note.lane == 7:  # Center note
					freq = 1000.0
				
				# Punchier envelope with quicker attack
				for i in range(hit_samples):
					var t = float(i) / sample_rate
					var envelope = 1.0 - pow(float(i) / hit_samples, 0.3)  # Less gentle decay
					var sample = sin(2.0 * PI * freq * t) * envelope * 0.4  # Louder amplitude
					playback.push_frame(Vector2(sample, sample))
