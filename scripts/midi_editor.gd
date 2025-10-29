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

var time_begin: float
var time_delay: float
var playback_position: float = 0.0  # Store position for pause/resume

const NUM_LANES = 21

func _ready():
	setup_file_menu()
	setup_division_selector()
	setup_audio_offset_control()
	setup_snap_toggle()
	setup_lane_height_slider()
	setup_time_display()
	EditorData.bpm_changed.connect(_on_bpm_changed)
	play_button.pressed.connect(_on_play_pressed)
	pause_button.pressed.connect(_on_pause_pressed)
	bpm_input.value_changed.connect(_on_bpm_input_changed)

func _on_bpm_input_changed(value: float):
	EditorData.bpm = value
	EditorData.bpm_changed.emit(value)

func setup_audio_offset_control():
	# Create label
	var label = Label.new()
	label.text = "Audio Offset:"
	label.add_theme_font_size_override("font_size", 14)
	tool_bar_2.add_child(label)
	
	# Create spinbox for audio offset
	audio_offset_input = SpinBox.new()
	audio_offset_input.min_value = -10.0
	audio_offset_input.max_value = 10.0
	audio_offset_input.step = 0.01
	audio_offset_input.value = 0.0
	audio_offset_input.custom_minimum_size = Vector2(100, 0)
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
	snap_toggle.text = "Snap to Grid"
	snap_toggle.button_pressed = true
	snap_toggle.tooltip_text = "Enable/disable grid snapping"
	snap_toggle.toggled.connect(_on_snap_toggled)
	tool_bar_2.add_child(snap_toggle)

func _on_snap_toggled(enabled: bool):
	EditorData.snap_enabled = enabled

func setup_lane_height_slider():
	# Create label
	var label = Label.new()
	label.text = "Lane Height:"
	label.add_theme_font_size_override("font_size", 14)
	tool_bar_2.add_child(label)
	
	# Create slider for lane height
	lane_height_slider = HSlider.new()
	lane_height_slider.min_value = 15
	lane_height_slider.max_value = 50
	lane_height_slider.step = 1
	lane_height_slider.value = 20
	lane_height_slider.custom_minimum_size = Vector2(100, 0)
	lane_height_slider.tooltip_text = "Adjust lane height"
	lane_height_slider.value_changed.connect(_on_lane_height_changed)
	tool_bar_2.add_child(lane_height_slider)

func _on_lane_height_changed(value: float):
	EditorData.lane_height = int(value)
	EditorData.lane_height_changed.emit(int(value))
	timeline_canvas.queue_redraw()

func setup_time_display():
	# Create a label in the toolbar to show playback time
	time_label = Label.new()
	time_label.text = "0:00 / 0:00"
	time_label.add_theme_font_size_override("font_size", 14)
	$ToolBar.add_child(time_label)
	$ToolBar.move_child(time_label, $ToolBar.get_child_count() - 1)  # Move to end
	
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
	division_selector.add_item("1/4", 1)
	division_selector.add_item("1/8", 2)
	division_selector.add_item("1/16", 4)
	division_selector.add_item("1/32", 8)
	division_selector.add_item("1/64", 16)
	division_selector.select(2)  # Default to 1/16
	division_selector.item_selected.connect(_on_division_changed)

func _on_division_changed(index: int):
	var divisions = [1, 2, 4, 8, 16]  # Maps to 1/4, 1/8, 1/16, 1/32, 1/64
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
		
		# Apply audio offset: timeline position - offset = audio position
		# If offset is positive, audio plays later (start audio earlier in file)
		var audio_start_position = max(0.0, playback_position - EditorData.audio_offset)
		audio_player.play(audio_start_position)
		
		# Adjust time_begin to account for starting position
		time_begin -= int(playback_position * 1_000_000.0)

func _on_pause_pressed():
	# Pause button only pauses, never resumes
	if EditorData.is_playing:
		EditorData.is_playing = false
		playback_position = EditorData.current_time
		audio_player.stop()

func stop_playback():
	# Full stop - reset to beginning
	EditorData.is_playing = false
	audio_player.stop()
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
	
	if was_playing:
		# Resume playback from new position (with audio offset)
		var audio_start_position = max(0.0, playback_position - EditorData.audio_offset)
		audio_player.play(audio_start_position)
		time_begin = Time.get_ticks_usec() - int(playback_position * 1_000_000.0)
		time_delay = AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()
	
	update_time_display()

func get_audio_duration() -> float:
	if audio_player.stream:
		return audio_player.stream.get_length()
	return 0.0

@warning_ignore("unused_parameter")
func _process(delta):
	if EditorData.is_playing:
		if audio_player.playing:
			var time = (Time.get_ticks_usec() - time_begin) / 1000000.0
			time -= time_delay
			time = max(0, time)
			
			EditorData.current_time = time
			EditorData.playback_position_changed.emit(time)
			
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
		time_label.text = "%s / %s" % [current, total]

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
		# Alphabetically "note_off" > "note_on", so we reverse the comparison
		return a["type"] > b["type"]
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
