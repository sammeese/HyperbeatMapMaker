# res://timeline_canvas.gd
extends Control

@onready var scroll_container: ScrollContainer = $".."

var midi_editor: Node = null  # Reference to parent editor for seeking

var zoom_level: float = 1.0
var pixels_per_beat: float = 100.0
var scroll_offset: Vector2 = Vector2.ZERO

var selected_note: EditorData.NoteData = null
var context_menu: PopupMenu

const LABEL_WIDTH = 100  # Width for lane labels
const RULER_HEIGHT = 30  # Height of ruler at top
const WAVEFORM_HEIGHT = 60  # Height of waveform display when shown
const WAVEFORM_HEIGHT_EMPTY = 5  # Height when no waveform
var NUM_LANES = EditorData.LANE_COUNT
var current_waveform_height = WAVEFORM_HEIGHT_EMPTY  # Current waveform height

# Helper to get Y offset where lanes start (after waveform + ruler)
func get_lanes_y_offset() -> int:
	return current_waveform_height + RULER_HEIGHT

var dragging_note: EditorData.NoteData = null
var drag_mode: String = ""  # "move" or "resize"
var drag_start_pos: Vector2

var drag_start_beat: float
var drag_start_lane: int
var drag_start_positions: Dictionary = {}  # Store {note: {beat: float, lane: int}}
var hovered_note: EditorData.NoteData = null

var selected_notes: Array[EditorData.NoteData] = []
var is_box_selecting: bool = false
var box_select_start: Vector2
var box_select_end: Vector2
var copied_notes: Array[Dictionary] = []  # Store relative positions

# Undo/Redo system
var history_stack: Array[Array] = []  # Stack of note states
var history_index: int = -1  # Current position in history
const MAX_HISTORY_SIZE: int = 50  # Maximum undo levels

# Waveform display
var waveform_samples: PackedFloat32Array = []
var waveform_texture: ImageTexture = null
var waveform_needs_update: bool = true

func _ready():
	update_canvas_size()
	EditorData.notes_changed.connect(_on_notes_changed)
	EditorData.playback_position_changed.connect(_on_playback_position_changed)
	EditorData.lane_height_changed.connect(_on_lane_height_changed)
	setup_context_menu()
	
	# Get reference to midi_editor (traverse up the node tree)
	var node = get_parent()
	while node:
		if node.name == "MidiEditor":
			midi_editor = node
			break
		node = node.get_parent()
	
	# Connect to scroll container for sticky labels
	if scroll_container:
		scroll_container.get_h_scroll_bar().value_changed.connect(_on_scroll_changed)
	
	# Set initial canvas size
	update_canvas_size()
	
	# Initialize history with empty state
	save_history()

func _on_notes_changed():
	update_canvas_size()
	queue_redraw()

func _on_scroll_changed(_value: float):
	queue_redraw()  # Redraw to update sticky label positions

func _on_playback_position_changed(_time: float):
	queue_redraw()  # Redraw to update playhead position

func _on_lane_height_changed(_new_height: int):
	update_canvas_size()
	queue_redraw()

func _draw():
	draw_waveform()  # Draw waveform first (at very top)
	draw_ruler()  # Draw ruler below waveform
	draw_grid()
	draw_lane_separators()
	draw_notes()
	draw_selection_box()
	draw_lane_labels()  # Draw labels on top of notes
	draw_playhead()  # Playhead on top of everything

func draw_waveform():
	# Draw waveform display at the very top
	if not midi_editor or not midi_editor.audio_player.stream:
		# No audio loaded - draw small empty area
		current_waveform_height = WAVEFORM_HEIGHT_EMPTY
		draw_rect(Rect2(0, 0, size.x, current_waveform_height), Color(0.1, 0.1, 0.1))
		return
	
	var stream = midi_editor.audio_player.stream
	
	# Only show waveform for WAV files
	if not (stream is AudioStreamWAV):
		# OGG or other format - draw small empty area
		current_waveform_height = WAVEFORM_HEIGHT_EMPTY
		draw_rect(Rect2(0, 0, size.x, current_waveform_height), Color(0.1, 0.1, 0.1))
		return
	
	# WAV file loaded - use full height
	current_waveform_height = WAVEFORM_HEIGHT
	
	# Generate waveform if needed
	if waveform_needs_update:
		generate_waveform()
	
	if waveform_samples.is_empty():
		draw_rect(Rect2(0, 0, size.x, current_waveform_height), Color(0.1, 0.1, 0.1))
		return
	
	# Draw background
	draw_rect(Rect2(0, 0, size.x, current_waveform_height), Color(0.1, 0.1, 0.1))
	
	# Calculate visible range
	var scroll_offset = scroll_container.scroll_horizontal if scroll_container else 0
	var visible_start_beat = pixel_to_beat(scroll_offset)
	var visible_end_beat = pixel_to_beat(scroll_offset + size.x)
	
	# Get audio duration in beats
	var audio_duration = midi_editor.get_audio_duration()
	var total_beats = EditorData.seconds_to_beats(audio_duration)
	
	if total_beats <= 0:
		return
	
	# Draw waveform
	var waveform_color = Color(0.3, 0.6, 0.8, 0.7)
	var center_y = current_waveform_height / 2
	var amplitude = (current_waveform_height / 2) - 5  # Leave 5px padding
	
	# Sample rate: how many samples per pixel
	var samples_per_beat = waveform_samples.size() / total_beats
	
	# Draw vertical lines for each pixel
	for x in range(0, int(size.x), 2):  # Draw every 2 pixels for performance
		var beat = pixel_to_beat(x + scroll_offset)
		if beat < 0 or beat > total_beats:
			continue
		
		var sample_idx = int(beat * samples_per_beat)
		if sample_idx >= 0 and sample_idx < waveform_samples.size():
			var sample = waveform_samples[sample_idx]
			var height = abs(sample) * amplitude * EditorData.waveform_amplitude
			
			# Draw line from center
			if sample >= 0:
				draw_line(Vector2(x, center_y), Vector2(x, center_y - height), waveform_color, 1.0)
			else:
				draw_line(Vector2(x, center_y), Vector2(x, center_y + height), waveform_color, 1.0)
	
	# Draw center line
	draw_line(Vector2(0, center_y), Vector2(size.x, center_y), Color(0.2, 0.2, 0.2), 1.0)
	
	# Draw separator line at bottom
	draw_line(Vector2(0, current_waveform_height), Vector2(size.x, current_waveform_height), Color(0.3, 0.3, 0.3), 2.0)

func generate_waveform():
	if not midi_editor or not midi_editor.audio_player.stream:
		return
	
	var stream = midi_editor.audio_player.stream
	
	# Only generate waveform for WAV files
	if not (stream is AudioStreamWAV):
		waveform_samples.clear()
		waveform_needs_update = false
		return
	
	# Get audio data from WAV stream
	var audio_data: PackedByteArray = stream.data
	var mix_rate = stream.mix_rate
	var duration = stream.get_length()
	var format = stream.format  # 0=8bit, 1=16bit, 2=IMA_ADPCM
	var stereo = stream.stereo
	
	# For now, create a simplified waveform by sampling the byte data
	# This is a basic implementation - proper decoding would require
	# interpreting the PCM format correctly
	
	# Downsample to reasonable size
	var target_samples = int(duration * 100)  # 100 samples per second
	var bytes_per_sample = 2 if format == 1 else 1  # 16-bit or 8-bit
	var channels = 2 if stereo else 1
	var total_samples = audio_data.size() / (bytes_per_sample * channels)
	var step = max(1, int(total_samples / target_samples))
	
	waveform_samples.clear()
	
	# Sample the audio data
	for i in range(0, int(total_samples), step):
		var byte_index = i * bytes_per_sample * channels
		if byte_index >= audio_data.size():
			break
		
		# Simple amplitude extraction (normalized to -1.0 to 1.0)
		var sample = 0.0
		if format == 1:  # 16-bit
			# Read 16-bit signed integer (little endian)
			if byte_index + 1 < audio_data.size():
				var low = audio_data[byte_index]
				var high = audio_data[byte_index + 1]
				var value = low | (high << 8)
				# Convert to signed
				if value >= 32768:
					value -= 65536
				sample = float(value) / 32768.0
		else:  # 8-bit
			var value = audio_data[byte_index]
			# Convert unsigned 8-bit to signed (-1.0 to 1.0)
			sample = (float(value) - 128.0) / 128.0
		
		waveform_samples.append(sample)
	
	waveform_needs_update = false
	print("Waveform generated: %d samples from WAV file" % waveform_samples.size())

func draw_lane_labels():
	var font = ThemeDB.fallback_font
	
	# Get scroll offset to make labels sticky
	var scroll_offset = scroll_container.scroll_horizontal if scroll_container else 0
	
	for i in range(NUM_LANES):
		var y = get_lanes_y_offset() + i * EditorData.lane_height + EditorData.lane_height / 2
		var label = EditorData.LANE_LABELS[i]
		
		# Draw label at fixed position (accounting for scroll)
		var label_x = scroll_offset + 5
		draw_string(font, Vector2(label_x, y), label, HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 10, 12)
	
	# Draw background rectangle behind labels so they're readable
	var label_rect = Rect2(scroll_offset, get_lanes_y_offset(), LABEL_WIDTH, size.y - get_lanes_y_offset())
	draw_rect(label_rect, Color(0.15, 0.15, 0.15, 0.95), true)
	
	# Redraw labels on top of background
	for i in range(NUM_LANES):
		var y = get_lanes_y_offset() + i * EditorData.lane_height + EditorData.lane_height / 2
		var label = EditorData.LANE_LABELS[i]
		var label_x = scroll_offset + 5
		draw_string(font, Vector2(label_x, y), label, HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 10, 12)

func draw_ruler():
	var font = ThemeDB.fallback_font
	var scroll_offset = scroll_container.scroll_horizontal if scroll_container else 0
	
	# Background for ruler (positioned below waveform)
	draw_rect(Rect2(0, current_waveform_height, size.x, RULER_HEIGHT), Color(0.2, 0.2, 0.2))
	
	var visible_start_beat = pixel_to_beat(scroll_offset + LABEL_WIDTH)
	var visible_end_beat = pixel_to_beat(scroll_offset + size.x)
	
	# Draw bar markers and labels
	var beats_per_bar = 4  # 4/4 time signature
	var start_bar = floor(visible_start_beat / beats_per_bar)
	var end_bar = ceil(visible_end_beat / beats_per_bar) + 1
	
	for bar_num in range(start_bar, end_bar):
		var beat = bar_num * beats_per_bar
		var x = beat_to_pixel(beat)
		
		if x < LABEL_WIDTH:
			continue
		
		# Draw major tick (bar line)
		draw_line(Vector2(x, current_waveform_height), Vector2(x, current_waveform_height + RULER_HEIGHT), Color.WHITE, 2.0)
		
		# Draw bar number
		var bar_label = "Bar %d" % (bar_num + 1)
		draw_string(font, Vector2(x + 5, current_waveform_height + 15), bar_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		
		# Draw timecode (time at this bar)
		var time_at_bar = EditorData.beats_to_seconds(beat)
		var timecode = format_timecode(time_at_bar)
		draw_string(font, Vector2(x + 5, current_waveform_height + 28), timecode, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.8, 0.8))
		
		# Draw minor ticks (beat lines within bar)
		for beat_offset in range(1, beats_per_bar):
			var minor_beat = beat + beat_offset
			var minor_x = beat_to_pixel(minor_beat)
			
			if minor_x < LABEL_WIDTH:
				continue
			
			draw_line(Vector2(minor_x, current_waveform_height + RULER_HEIGHT - 10), Vector2(minor_x, current_waveform_height + RULER_HEIGHT), 
					  Color(0.6, 0.6, 0.6), 1.0)
	
	# Draw sticky label background over ruler
	var label_rect = Rect2(scroll_offset, current_waveform_height, LABEL_WIDTH, RULER_HEIGHT)
	draw_rect(label_rect, Color(0.15, 0.15, 0.15, 0.95), true)
	
	# Draw "Timeline" label
	draw_string(font, Vector2(scroll_offset + 5, current_waveform_height + 20), "Timeline", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

func format_timecode(seconds: float) -> String:
	var mins = int(seconds) / 60
	var secs = int(seconds) % 60
	var millis = int((seconds - int(seconds)) * 100)
	return "%d:%02d.%02d" % [mins, secs, millis]

func draw_selection_box():
	# Draw selected notes with highlight
	for note in selected_notes:
		if note.lane >= NUM_LANES:
			continue
		
		var x_start = beat_to_pixel(note.beat_position)
		var x_end = beat_to_pixel(note.beat_position + note.duration)
		var y = get_lanes_y_offset() + note.lane * EditorData.lane_height
		
		var note_width = x_end - x_start
		var note_rect = Rect2(x_start, y + 5, note_width, EditorData.lane_height - 10)
		
		# Draw selection outline
		draw_rect(note_rect, Color.YELLOW, false, 2.0)
	
	# Draw box selection rectangle
	if is_box_selecting:
		var rect = Rect2(box_select_start, box_select_end - box_select_start)
		draw_rect(rect, Color(0.5, 0.8, 1.0, 0.2), true)
		draw_rect(rect, Color(0.5, 0.8, 1.0, 0.8), false, 2.0)


func draw_playhead():
	# Draw playhead line at current playback position
	var current_beat = EditorData.seconds_to_beats(EditorData.current_time)
	var x = beat_to_pixel(current_beat)
	var scroll_offset = scroll_container.scroll_horizontal if scroll_container else 0
	
	# Draw playhead if it's visible (don't check against LABEL_WIDTH, let it draw over labels)
	if x >= 0 and x <= size.x:
		# Draw vertical line starting below ruler (after waveform + ruler)
		draw_line(Vector2(x, get_lanes_y_offset()), Vector2(x, size.y), Color(1.0, 0.3, 0.3, 0.8), 3.0)
		
		# Draw triangle at bottom of ruler (pointing down into lanes)
		var triangle = PackedVector2Array([
			Vector2(x - 8, get_lanes_y_offset()),
			Vector2(x + 8, get_lanes_y_offset()),
			Vector2(x, get_lanes_y_offset() + 12)
		])
		draw_colored_polygon(triangle, Color(1.0, 0.3, 0.3, 0.9))

func setup_context_menu():
	context_menu = PopupMenu.new()
	add_child(context_menu)
	context_menu.id_pressed.connect(_on_context_menu_selected)

func show_context_menu_for_note(note: EditorData.NoteData, position: Vector2):
	selected_note = note
	context_menu.clear()
	
	# Check if multiple notes are selected
	var multi_select = selected_notes.size() > 1
	
	if multi_select:
		# Batch operations for multiple notes
		context_menu.add_item("Batch Operations:", -1)
		context_menu.set_item_disabled(0, true)
		context_menu.add_separator()
		
		# Check if any selected notes are edge notes (lanes 8-19) or sustain notes (lane 20)
		var has_edge_notes = false
		var has_sustain_notes = false
		for n in selected_notes:
			if n.lane >= 8 and n.lane <= 19:
				has_edge_notes = true
			elif n.lane == 20:
				has_sustain_notes = true
		
		if has_edge_notes:
			context_menu.add_item("Set All to Target Note (1)", 201)
			context_menu.add_item("Set All to Swipe Left (3)", 203)
			context_menu.add_item("Set All to Swipe Right (5)", 205)
			context_menu.add_item("Swap Left/Right Swipes", 210)
			context_menu.add_item("Set All to Cross Note (6)", 206)
			context_menu.add_item("Set All to Soft Note (7)", 207)
			context_menu.add_item("Set All to Bar Note (9)", 209)
		
		if has_sustain_notes:
			# Add separator if we already showed edge note options
			if has_edge_notes:
				context_menu.add_separator()
			
			context_menu.add_item("Sustain: Set All to Blank (1)", 221)
			context_menu.add_item("Sustain: Set All to Left Swipe (3)", 223)
			context_menu.add_item("Sustain: Set All to Right Swipe (5)", 225)
			context_menu.add_item("Sustain: Set All to Blank (7)", 227)
			context_menu.add_item("Sustain: Swap Left/Right Swipes", 230)
		
		if not has_edge_notes and not has_sustain_notes:
			context_menu.add_item("Set All Velocities...", 200)
		
		context_menu.add_separator()
		context_menu.add_item("Delete All Selected", 99)
		
	else:
		# Single note operations
		# Check if this is an edge note (lanes 8-19)
		if note.lane >= 8 and note.lane <= 19:
			# Edge note - specific velocity options with labels
			context_menu.add_item("Target Note", 1)
			context_menu.add_item("Swipe Left", 3)
			context_menu.add_item("Swipe Right", 5)
			context_menu.add_item("Cross Note", 6)
			context_menu.add_item("Soft Note", 7)
			context_menu.add_item("Bar Note", 9)
		elif note.lane == 20:
			# Sustain lane - specific velocity options
			context_menu.add_item("Blank (1)", 1)
			context_menu.add_item("Left Swipe (3)", 3)
			context_menu.add_item("Right Swipe (5)", 5)
			context_menu.add_item("Blank (7)", 7)
		else:
			# Non-edge note - show current velocity and option to change
			context_menu.add_item("Current Velocity: %d" % note.velocity, -1)
			context_menu.set_item_disabled(0, true)
			context_menu.add_separator()
			context_menu.add_item("Set Velocity... (Type Number)", 100)
		
		context_menu.add_separator()
		context_menu.add_item("Delete Note", 99)
	
	context_menu.position = position
	context_menu.popup()

func draw_grid():
	var scroll_offset = scroll_container.scroll_horizontal if scroll_container else 0
	var visible_start_beat = pixel_to_beat(scroll_offset + LABEL_WIDTH)
	var visible_end_beat = pixel_to_beat(scroll_offset + size.x)
	
	var division_size = 1.0 / float(EditorData.snap_division)
	var start_line = floor(visible_start_beat / division_size)
	var end_line = ceil(visible_end_beat / division_size)
	
	for i in range(start_line, end_line + 1):
		var beat = i * division_size
		var x = beat_to_pixel(beat)
		
		if x < scroll_offset + LABEL_WIDTH:  # Don't draw grid over sticky labels
			continue
		
		var color: Color
		var width: float
		
		if int(beat) == beat and int(beat) % 4 == 0:
			color = Color(0.7, 0.7, 0.7, 0.8)
			width = 2.0
		elif int(beat) == beat:
			color = Color(0.5, 0.5, 0.5, 0.6)
			width = 1.5
		else:
			color = Color(0.3, 0.3, 0.3, 0.4)
			width = 1.0
		
		draw_line(Vector2(x, get_lanes_y_offset()), Vector2(x, size.y), color, width)
		
func draw_lane_separators():
	for i in range(NUM_LANES + 1):
		var y = get_lanes_y_offset() + i * EditorData.lane_height
		var scroll_offset = scroll_container.scroll_horizontal if scroll_container else 0
		draw_line(Vector2(scroll_offset + LABEL_WIDTH, y), Vector2(size.x, y), Color(0.4, 0.4, 0.4), 1.0)
	
	# Vertical line after labels (sticky) - starts below ruler
	var scroll_offset = scroll_container.scroll_horizontal if scroll_container else 0
	draw_line(Vector2(scroll_offset + LABEL_WIDTH, get_lanes_y_offset()), Vector2(scroll_offset + LABEL_WIDTH, size.y), Color(0.6, 0.6, 0.6), 2.0)

func draw_notes():
	for note in EditorData.notes:
		if note.lane >= NUM_LANES:
			continue
		
		var x_start = beat_to_pixel(note.beat_position)
		var x_end = beat_to_pixel(note.beat_position + note.duration)
		var y = get_lanes_y_offset() + note.lane * EditorData.lane_height
		
		# Note rectangle with length
		var note_width = x_end - x_start
		var note_rect = Rect2(x_start, y + 5, note_width, EditorData.lane_height - 10)
		
		# Color by velocity
		var color = get_velocity_color(note.velocity)
		draw_rect(note_rect, color)
		
		# Velocity indicator (fill height)
		var fill_percent = note.velocity / 9.0
		var fill_height = (EditorData.lane_height - 10) * fill_percent
		var fill_rect = Rect2(
			x_start,
			y + EditorData.lane_height - 5 - fill_height,
			note_width,
			fill_height
		)
		draw_rect(fill_rect, Color(1, 1, 1, 0.3))
		
		# Clock position indicator for edge notes
		if note.clock_position >= 0:
			var font = ThemeDB.fallback_font
			var text 
			if note.clock_position == 0:
				text = str(12)
			else:
				text = str(note.clock_position)
			draw_string(font, Vector2(x_start + 5, y + 25), text, 
					   HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		
		# Resize handle at the end of note
		var handle_size = 8.0
		var handle_rect = Rect2(x_end - handle_size, y + EditorData.lane_height/2 - handle_size/2, 
							   handle_size, handle_size)
		draw_rect(handle_rect, Color.WHITE)

func get_velocity_color(vel: int) -> Color:
	# Edge note colors based on type
	match vel:
		1: return Color(0.3, 0.6, 0.9)   # Target Note - Blue
		3: return Color(0.9, 0.4, 0.4)   # Swipe Left - Red
		5: return Color(0.4, 0.9, 0.4)   # Swipe Right - Green
		6: return Color(0.9, 0.6, 0.2)   # Cross Note - Orange
		7: return Color(0.7, 0.4, 0.9)   # Soft Note - Purple
		9: return Color(0.9, 0.9, 0.3)   # Bar Note - Yellow
		_: 
	
			var intensity = float(vel) / 127.0
			return Color(0.5 + intensity * 0.5, 0.5 - intensity * 0.5, 0.0)
			
func beat_to_pixel(beat: float) -> float:
	return LABEL_WIDTH + (beat * pixels_per_beat * zoom_level)

func pixel_to_beat(pixel: float) -> float:
	return (pixel - LABEL_WIDTH) / (pixels_per_beat * zoom_level)

var can_zoom : bool = false



func _process(_delta) -> void:
	if Input.is_action_just_pressed("ctrl"):
		can_zoom = true
		scroll_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if Input.is_action_just_released("ctrl"):
		can_zoom = false
		scroll_container.mouse_filter = Control.MOUSE_FILTER_PASS
		
func _gui_input(event: InputEvent):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# Check if Shift is held for multi-select
				if Input.is_key_pressed(KEY_SHIFT):
					start_box_selection(event.position)
				else:
					handle_left_click(event.position)
			else:
				# Mouse released
				if is_box_selecting:
					finish_box_selection()
				dragging_note = null
				drag_mode = ""
				drag_start_positions.clear()
		
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			handle_right_click(event.position)
		elif event.button_index == MOUSE_BUTTON_MIDDLE and event.pressed:
			# Middle-click to seek playback position
			var scroll_offset = scroll_container.scroll_horizontal if scroll_container else 0
			if event.position.x >= scroll_offset + LABEL_WIDTH:
				var beat = pixel_to_beat(event.position.x)
				var time_seconds = EditorData.beats_to_seconds(beat)
				if midi_editor:
					midi_editor.seek_to_time(time_seconds)
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if can_zoom:
				zoom_in(event.position)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if can_zoom:
				zoom_out(event.position)
	
	elif event is InputEventMouseMotion:
		# Track hovered note for keyboard delete
		hovered_note = get_note_at_position(event.position)
		
		if is_box_selecting:
			update_box_selection(event.position)
		elif dragging_note:
			handle_drag(event.position)

func _unhandled_input(event: InputEvent):
	# Handle keyboard input globally (doesn't require focus)
	if event is InputEventKey:
		if event.pressed and not event.echo:
			handle_keyboard_input(event)

func handle_left_click(pos: Vector2):
	# If context menu is open, just close it and don't place note
	if context_menu.visible:
		context_menu.hide()
		return
	
	var scroll_offset = scroll_container.scroll_horizontal if scroll_container else 0
	
	# Check if clicking in the sticky label area
	if pos.x < scroll_offset + LABEL_WIDTH:
		return
	
	# Check if clicking on a note
	var clicked_note = get_note_at_position(pos)
	
	if clicked_note:
		# If Ctrl held, toggle selection
		if Input.is_key_pressed(KEY_CTRL):
			if clicked_note in selected_notes:
				selected_notes.erase(clicked_note)
			else:
				selected_notes.append(clicked_note)
			queue_redraw()
			return
		
		# Otherwise clear selection and handle drag
		if not clicked_note in selected_notes:
			selected_notes.clear()
		
		var x_end = beat_to_pixel(clicked_note.beat_position + clicked_note.duration)
		
		# Check if clicking resize handle
		if abs(pos.x - x_end) < 10:  # Near the end handle
			dragging_note = clicked_note
			drag_mode = "resize"
			drag_start_pos = pos
			return
		else:
			# Clicking on note body - enable move mode
			dragging_note = clicked_note
			drag_mode = "move"
			drag_start_pos = pos
			drag_start_beat = clicked_note.beat_position
			drag_start_lane = clicked_note.lane
			
			# If the clicked note is not in selection, add it
			if not clicked_note in selected_notes:
				selected_notes.append(clicked_note)
			
			# Store starting positions of all selected notes
			drag_start_positions.clear()
			for note in selected_notes:
				drag_start_positions[note] = {
					"beat": note.beat_position,
					"lane": note.lane
				}
			
			return
	
	# Clicking on empty space - clear selection and place note
	selected_notes.clear()
	
	var beat = pixel_to_beat(pos.x)
	var lane = int((pos.y - get_lanes_y_offset()) / EditorData.lane_height)
	
	if lane >= NUM_LANES:
		return
	
	# Save state for undo before placing note
	save_history()
	
	# Snap to grid
	beat = snap_to_grid(beat)
	
	# Get MIDI note for this lane
	var midi_note = EditorData.get_midi_note_for_lane(lane)
	
	# Auto-assign clock position for edge notes (lanes 8-19)
	var clock_pos = EditorData.get_clock_position_for_lane(lane)
	
	# Default velocity based on lane type
	var velocity = 64  # Default for non-edge notes
	if lane >= 7 and lane <= 20:
		# Edge note - default to Target Note
		velocity = 1
	
	# Use division size for default length, but enforce minimum
	var division_size = 1.0 / float(EditorData.snap_division)
	var duration = max(division_size, EditorData.MIN_NOTE_DURATION)
	var note = EditorData.NoteData.new(beat, lane, clock_pos, velocity, midi_note, duration)
	EditorData.add_note(note)
	
func handle_drag(pos: Vector2):
	if not dragging_note:
		return
	
	if drag_mode == "resize":
		# Save state on first drag movement (when drag_start_positions is empty for resize)
		if not "resize_saved" in drag_start_positions:
			save_history()
			drag_start_positions["resize_saved"] = true
		
		# Resize note duration
		var end_beat = pixel_to_beat(pos.x)
		var new_duration = end_beat - dragging_note.beat_position
		new_duration = snap_to_grid(new_duration)
		dragging_note.duration = max(EditorData.MIN_NOTE_DURATION, new_duration)
		EditorData.notes_changed.emit()
	
	elif drag_mode == "move":
		# Save state on first drag movement (when we start moving)
		if not "move_saved" in drag_start_positions:
			save_history()
			drag_start_positions["move_saved"] = true
		
		# Move note to new position
		var new_beat = pixel_to_beat(pos.x)
		var new_lane = int((pos.y - get_lanes_y_offset()) / EditorData.lane_height)
		
		# Snap to grid
		new_beat = snap_to_grid(new_beat)
		
		# Calculate offset from the dragged note's starting position
		var beat_offset = new_beat - drag_start_beat
		var lane_offset = new_lane - drag_start_lane
		
		# Apply offset to all selected notes
		for note in selected_notes:
			if note in drag_start_positions:
				var start_pos = drag_start_positions[note]
				var target_beat = start_pos["beat"] + beat_offset
				var target_lane = start_pos["lane"] + lane_offset
				
				# Clamp lane
				target_lane = clamp(target_lane, 0, NUM_LANES - 1)
				
				# Update note position
				note.beat_position = target_beat
				
				# If lane changed, update MIDI note and clock position
				if target_lane != note.lane:
					note.lane = target_lane
					note.midi_note = EditorData.get_midi_note_for_lane(target_lane)
					note.clock_position = EditorData.get_clock_position_for_lane(target_lane)
		
		EditorData.notes_changed.emit()
		
func handle_right_click(pos: Vector2):
	var clicked_note = get_note_at_position(pos)
	if clicked_note:
		show_context_menu_for_note(clicked_note, get_global_mouse_position())

func handle_keyboard_input(event: InputEventKey):
	# Play/Pause with Spacebar
	if event.keycode == KEY_SPACE:
		if midi_editor:
			midi_editor.toggle_playback()
		# Accept the event to prevent UI elements from capturing it
		get_viewport().set_input_as_handled()
		return
	
	# Delete hovered note with Delete or Backspace
	if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
		if not selected_notes.is_empty():
			# Save state before deleting
			save_history()
			# Delete all selected notes
			for note in selected_notes:
				EditorData.remove_note(note)
			selected_notes.clear()
			queue_redraw()
		elif hovered_note:
			# Save state before deleting
			save_history()
			# Delete just the hovered note
			EditorData.remove_note(hovered_note)
			hovered_note = null
	
	# Copy with Ctrl+C
	elif event.keycode == KEY_C and event.is_command_or_control_pressed():
		copy_selected_notes()
	
	# Paste with Ctrl+V
	elif event.keycode == KEY_V and event.is_command_or_control_pressed():
		paste_notes_at_mouse()
	
	# Select all with Ctrl+A
	elif event.keycode == KEY_A and event.is_command_or_control_pressed():
		select_all_notes()
	
	# Duplicate with Ctrl+D
	elif event.keycode == KEY_D and event.is_command_or_control_pressed():
		duplicate_selected_notes()
	
	# Deselect with Escape
	elif event.keycode == KEY_ESCAPE:
		selected_notes.clear()
		queue_redraw()
	
	# Undo with Ctrl+Z
	elif event.keycode == KEY_Z and event.is_command_or_control_pressed() and not event.shift_pressed:
		undo()
	
	# Redo with Ctrl+Y or Ctrl+Shift+Z
	elif (event.keycode == KEY_Y and event.is_command_or_control_pressed()) or \
		 (event.keycode == KEY_Z and event.is_command_or_control_pressed() and event.shift_pressed):
		redo()
	
	# Arrow key nudging
	elif event.keycode == KEY_LEFT:
		nudge_selected_notes(-1, 0, event.shift_pressed)
	elif event.keycode == KEY_RIGHT:
		nudge_selected_notes(1, 0, event.shift_pressed)
	elif event.keycode == KEY_UP:
		nudge_selected_notes(0, -1, event.shift_pressed)
	elif event.keycode == KEY_DOWN:
		nudge_selected_notes(0, 1, event.shift_pressed)
	
	# Cycle snap division with Q (decrease) and E (increase)
	elif event.keycode == KEY_Q:
		if midi_editor:
			midi_editor.cycle_division(-1)
	elif event.keycode == KEY_E:
		if midi_editor:
			midi_editor.cycle_division(1)
	
	# Jump to previous/next section (lane 0 notes) with , and .
	elif event.keycode == KEY_COMMA:
		jump_to_previous_section()
	elif event.keycode == KEY_PERIOD:
		jump_to_next_section()
	
	# Quick velocity setting for hovered note with Z, X, C, V, B
	elif hovered_note and hovered_note.lane >= 8 and hovered_note.lane <= 19:
		if event.keycode == KEY_Z:
			hovered_note.velocity = 3  # Swipe Left
			EditorData.notes_changed.emit()
		elif event.keycode == KEY_X:
			hovered_note.velocity = 5  # Swipe Right
			EditorData.notes_changed.emit()
		elif event.keycode == KEY_C:
			hovered_note.velocity = 1  # Target
			EditorData.notes_changed.emit()
		elif event.keycode == KEY_V:
			hovered_note.velocity = 7  # Soft
			EditorData.notes_changed.emit()
		elif event.keycode == KEY_B:
			hovered_note.velocity = 9  # Bar
			EditorData.notes_changed.emit()

# Add box selection functions:
func start_box_selection(pos: Vector2):
	is_box_selecting = true
	box_select_start = pos
	box_select_end = pos
	
	# Clear previous selection if not holding Ctrl
	if not Input.is_key_pressed(KEY_CTRL):
		selected_notes.clear()

func update_box_selection(pos: Vector2):
	box_select_end = pos
	
	# Find notes in selection box
	var rect = Rect2(box_select_start, box_select_end - box_select_start).abs()
	
	var newly_selected: Array[EditorData.NoteData] = []
	for note in EditorData.notes:
		var x_start = beat_to_pixel(note.beat_position)
		var x_end = beat_to_pixel(note.beat_position + note.duration)
		var y = get_lanes_y_offset() + note.lane * EditorData.lane_height
		
		var note_rect = Rect2(x_start, y + 5, x_end - x_start, EditorData.lane_height - 10)
		
		if rect.intersects(note_rect):
			if not note in newly_selected:
				newly_selected.append(note)
	
	# Update selection
	if not Input.is_key_pressed(KEY_CTRL):
		selected_notes = newly_selected
	else:
		# Add to existing selection
		for note in newly_selected:
			if not note in selected_notes:
				selected_notes.append(note)
	
	queue_redraw()

func finish_box_selection():
	is_box_selecting = false
	queue_redraw()

# Add copy/paste functions:
func copy_selected_notes():
	if selected_notes.is_empty():
		return
	
	copied_notes.clear()
	
	# Find the earliest beat position as reference point
	var min_beat = INF
	var min_lane = INF
	for note in selected_notes:
		min_beat = min(min_beat, note.beat_position)
		min_lane = min(min_lane, note.lane)
	
	# Store relative positions
	for note in selected_notes:
		copied_notes.append({
			"beat_offset": note.beat_position - min_beat,
			"lane_offset": note.lane - min_lane,
			"duration": note.duration,
			"velocity": note.velocity,
			"clock_position": note.clock_position
		})
	
	print("Copied %d notes" % copied_notes.size())

func paste_notes_at_mouse():
	if copied_notes.is_empty():
		return
	
	var mouse_pos = get_local_mouse_position()
	var paste_beat = snap_to_grid(pixel_to_beat(mouse_pos.x))
	var paste_lane = int((mouse_pos.y - RULER_HEIGHT) / EditorData.lane_height)
	
	if paste_lane >= NUM_LANES:
		return
	
	# Save state for undo
	save_history()
	
	# Clear current selection
	selected_notes.clear()
	
	# Paste notes
	for note_data in copied_notes:
		var new_beat = paste_beat + note_data["beat_offset"]
		var new_lane = paste_lane + note_data["lane_offset"]
		
		# Skip if out of bounds
		if new_lane < 0 or new_lane >= NUM_LANES:
			continue
		
		var midi_note = EditorData.get_midi_note_for_lane(new_lane)
		var clock_pos = EditorData.get_clock_position_for_lane(new_lane)
		
		# Enforce minimum duration
		var duration = max(note_data["duration"], EditorData.MIN_NOTE_DURATION)
		
		var new_note = EditorData.NoteData.new(
			new_beat,
			new_lane,
			clock_pos,
			note_data["velocity"],
			midi_note,
			duration
		)
		EditorData.add_note(new_note)
		selected_notes.append(new_note)
	
	print("Pasted %d notes" % copied_notes.size())

func select_all_notes():
	selected_notes = EditorData.notes.duplicate()
	queue_redraw()

func duplicate_selected_notes():
	if selected_notes.is_empty():
		return
	
	# Save state for undo
	save_history()
	
	var new_notes: Array[EditorData.NoteData] = []
	
	# Find the latest beat position + duration in selection
	var max_end_beat = 0.0
	for note in selected_notes:
		var note_end = note.beat_position + note.duration
		max_end_beat = max(max_end_beat, note_end)
	
	# Find the earliest beat position as reference
	var min_beat = INF
	for note in selected_notes:
		min_beat = min(min_beat, note.beat_position)
	
	# Snap the end position to grid
	var division_size = 1.0 / float(EditorData.snap_division)
	var snap_target = ceil(max_end_beat / division_size) * division_size
	
	# Calculate offset to place duplicates at snapped position after selection
	var beat_offset = snap_target - min_beat
	
	# Duplicate each selected note with the calculated offset
	for note in selected_notes:
		var new_beat = note.beat_position + beat_offset
		var midi_note = EditorData.get_midi_note_for_lane(note.lane)
		var clock_pos = EditorData.get_clock_position_for_lane(note.lane)
		
		var new_note = EditorData.NoteData.new(
			new_beat,
			note.lane,
			clock_pos,
			note.velocity,
			midi_note,
			note.duration
		)
		EditorData.add_note(new_note)
		new_notes.append(new_note)
	
	# Select the new duplicated notes
	selected_notes = new_notes
	print("Duplicated %d notes" % new_notes.size())
	queue_redraw()


func get_note_at_position(pos: Vector2) -> EditorData.NoteData:
	var scroll_offset = scroll_container.scroll_horizontal if scroll_container else 0
	
	if pos.x < scroll_offset + LABEL_WIDTH:
		return null
	
	var beat = pixel_to_beat(pos.x)
	var lane = int((pos.y - get_lanes_y_offset()) / EditorData.lane_height)
	
	for note in EditorData.notes:
		if note.lane != lane:
			continue
		
		if beat >= note.beat_position and beat <= note.beat_position + note.duration:
			return note
	
	return null


func _on_context_menu_selected(id: int):
	if not selected_note:
		return
	
	# Save state for undo before any modifications
	if id != 100 and id != 200 and id != -1:  # Don't save for dialog opens or disabled items
		save_history()
	
	if id == 99:
		# Delete
		if selected_notes.size() > 1:
			# Delete all selected notes
			for note in selected_notes:
				EditorData.remove_note(note)
			selected_notes.clear()
		else:
			EditorData.remove_note(selected_note)
	
	elif id == 100:
		# Show input dialog for velocity (single note)
		show_velocity_input_dialog()
	
	elif id == 200:
		# Set all velocities (batch)
		show_velocity_input_dialog_batch()
	
	elif id >= 201 and id <= 209:
		# Batch set velocity for edge notes
		var velocity_map = {
			201: 1,  # Target Note
			203: 3,  # Swipe Left
			205: 5,  # Swipe Right
			206: 6,  # Cross Note
			207: 7,  # Soft Note
			209: 9   # Bar Note
		}
		
		if id in velocity_map:
			for note in selected_notes:
				if note.lane >= 8 and note.lane <= 19:  # Only edge notes
					note.velocity = velocity_map[id]
			EditorData.notes_changed.emit()
			print("Set %d edge notes to velocity %d" % [selected_notes.size(), velocity_map[id]])
	
	elif id == 210:
		# Swap left/right swipes (edge notes and sustain notes)
		var swapped_count = 0
		for note in selected_notes:
			if (note.lane >= 8 and note.lane <= 19) or note.lane == 20:  # Edge notes and sustain
				if note.velocity == 3:  # Swipe Left
					note.velocity = 5  # Swipe Right
					swapped_count += 1
				elif note.velocity == 5:  # Swipe Right
					note.velocity = 3  # Swipe Left
					swapped_count += 1
		
		if swapped_count > 0:
			EditorData.notes_changed.emit()
			print("Swapped %d swipe directions" % swapped_count)
	
	# Sustain-specific batch operations (IDs 221-230)
	elif id >= 221 and id <= 230:
		var velocity_map = {
			221: 1,  # Blank (1)
			223: 3,  # Left Swipe
			225: 5,  # Right Swipe
			227: 7   # Blank (7)
		}
		
		if id == 230:
			# Swap left/right swipes for sustain notes only
			var swapped_count = 0
			for note in selected_notes:
				if note.lane == 20:  # Only sustain notes
					if note.velocity == 3:  # Swipe Left
						note.velocity = 5  # Swipe Right
						swapped_count += 1
					elif note.velocity == 5:  # Swipe Right
						note.velocity = 3  # Swipe Left
						swapped_count += 1
			
			if swapped_count > 0:
				EditorData.notes_changed.emit()
				print("Swapped %d sustain note directions" % swapped_count)
		elif id in velocity_map:
			# Set velocity for sustain notes
			var set_count = 0
			for note in selected_notes:
				if note.lane == 20:  # Only sustain notes
					note.velocity = velocity_map[id]
					set_count += 1
			
			if set_count > 0:
				EditorData.notes_changed.emit()
				print("Set %d sustain notes to velocity %d" % [set_count, velocity_map[id]])
	
	elif id > 0:
		# Set velocity directly (for edge notes, single selection)
		selected_note.velocity = id
		EditorData.notes_changed.emit()
	
	if id != 100 and id != 200:  # Don't clear if showing dialog
		selected_note = null

var velocity_dialog: Window = null
var velocity_input: SpinBox = null

func show_velocity_input_dialog():
	if velocity_dialog:
		velocity_dialog.queue_free()
	
	velocity_dialog = Window.new()
	velocity_dialog.title = "Set Velocity"
	velocity_dialog.size = Vector2i(300, 150)
	velocity_dialog.unresizable = true
	add_child(velocity_dialog)
	
	var vbox = VBoxContainer.new()
	velocity_dialog.add_child(vbox)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	
	var label = Label.new()
	label.text = "Enter velocity (1-127):"
	vbox.add_child(label)
	
	velocity_input = SpinBox.new()
	velocity_input.min_value = 1
	velocity_input.max_value = 127
	velocity_input.value = selected_note.velocity if selected_note else 64
	velocity_input.step = 1
	vbox.add_child(velocity_input)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)
	
	var ok_button = Button.new()
	ok_button.text = "OK"
	ok_button.pressed.connect(_on_velocity_dialog_ok)
	hbox.add_child(ok_button)
	
	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(_on_velocity_dialog_cancel)
	hbox.add_child(cancel_button)
	
	velocity_dialog.popup_centered()
	velocity_input.grab_focus()

func _on_velocity_dialog_ok():
	if selected_note and velocity_input:
		selected_note.velocity = int(velocity_input.value)
		EditorData.notes_changed.emit()
	selected_note = null
	if velocity_dialog:
		velocity_dialog.queue_free()
		velocity_dialog = null

func _on_velocity_dialog_cancel():
	selected_note = null
	if velocity_dialog:
		velocity_dialog.queue_free()
		velocity_dialog = null

func show_velocity_input_dialog_batch():
	if velocity_dialog:
		velocity_dialog.queue_free()
	
	velocity_dialog = Window.new()
	velocity_dialog.title = "Set All Velocities"
	velocity_dialog.size = Vector2i(300, 150)
	velocity_dialog.unresizable = true
	add_child(velocity_dialog)
	
	var vbox = VBoxContainer.new()
	velocity_dialog.add_child(vbox)
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 10)
	
	var label = Label.new()
	label.text = "Enter velocity for all %d notes (1-127):" % selected_notes.size()
	vbox.add_child(label)
	
	velocity_input = SpinBox.new()
	velocity_input.min_value = 1
	velocity_input.max_value = 127
	velocity_input.value = 64
	velocity_input.step = 1
	vbox.add_child(velocity_input)
	
	var hbox = HBoxContainer.new()
	hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(hbox)
	
	var ok_button = Button.new()
	ok_button.text = "OK"
	ok_button.pressed.connect(_on_velocity_dialog_batch_ok)
	hbox.add_child(ok_button)
	
	var cancel_button = Button.new()
	cancel_button.text = "Cancel"
	cancel_button.pressed.connect(_on_velocity_dialog_cancel)
	hbox.add_child(cancel_button)
	
	velocity_dialog.popup_centered()
	velocity_input.grab_focus()

func _on_velocity_dialog_batch_ok():
	if velocity_input:
		var new_velocity = int(velocity_input.value)
		for note in selected_notes:
			note.velocity = new_velocity
		EditorData.notes_changed.emit()
		print("Set %d notes to velocity %d" % [selected_notes.size(), new_velocity])
	selected_note = null
	if velocity_dialog:
		velocity_dialog.queue_free()
		velocity_dialog = null

func handle_note_placement(pos: Vector2):
	var beat = pixel_to_beat(pos.x)
	var lane = int((pos.y - get_lanes_y_offset()) / EditorData.lane_height)
	
	if lane >= NUM_LANES:
		return
	
	# Snap to grid
	beat = snap_to_grid(beat)
	
	# Default clock position and velocity
	var clock_pos = 0
	var velocity = 5
	var midi_note = 60 + lane  # Simple mapping
	
	var note = EditorData.NoteData.new(beat, lane, clock_pos, velocity, midi_note)
	EditorData.add_note(note)

func snap_to_grid(beat: float) -> float:
	if not EditorData.snap_enabled:
		return beat
	var division_size = 1.0 / float(EditorData.snap_division)
	return round(beat / division_size) * division_size

func zoom_in(mouse_pos: Vector2):
	if not scroll_container:
		zoom_level = clamp(zoom_level * 1.1, 0.25, 4.0)
		queue_redraw()
		return
	
	# Get the beat position under the mouse before zoom
	var beat_at_mouse = pixel_to_beat(mouse_pos.x)
	
	# Apply zoom
	zoom_level = clamp(zoom_level * 1.1, 0.25, 4.0)
	
	# Calculate new pixel position of that beat
	var new_pixel_at_mouse = beat_to_pixel(beat_at_mouse)
	
	# Adjust scroll to keep the same beat under the mouse
	var scroll_adjustment = new_pixel_at_mouse - mouse_pos.x
	scroll_container.scroll_horizontal = int(scroll_container.scroll_horizontal + scroll_adjustment)
	
	# Update canvas size for new zoom level
	update_canvas_size()
	queue_redraw()

func zoom_out(mouse_pos: Vector2):
	if not scroll_container:
		zoom_level = clamp(zoom_level / 1.1, 0.25, 4.0)
		queue_redraw()
		return
	
	# Get the beat position under the mouse before zoom
	var beat_at_mouse = pixel_to_beat(mouse_pos.x)
	
	# Apply zoom
	zoom_level = clamp(zoom_level / 1.1, 0.25, 4.0)
	
	# Calculate new pixel position of that beat
	var new_pixel_at_mouse = beat_to_pixel(beat_at_mouse)
	
	# Adjust scroll to keep the same beat under the mouse
	var scroll_adjustment = new_pixel_at_mouse - mouse_pos.x
	scroll_container.scroll_horizontal = int(scroll_container.scroll_horizontal + scroll_adjustment)
	
	# Update canvas size for new zoom level
	update_canvas_size()
	queue_redraw()

func update_canvas_size():
	# Calculate required width based on furthest note or minimum size
	var max_beat = 64.0  # Minimum 64 beats visible
	
	for note in EditorData.notes:
		var note_end = note.beat_position + note.duration
		max_beat = max(max_beat, note_end)
	
	# Add padding: 25% extra space after the last note
	max_beat += max_beat * 0.25
	
	# Calculate pixel width needed
	var required_width = beat_to_pixel(max_beat) + LABEL_WIDTH
	
	# Set minimum size (allow extra scrolling)
	custom_minimum_size.x = max(required_width, 1000)
	custom_minimum_size.y = current_waveform_height + RULER_HEIGHT + (EditorData.lane_height * NUM_LANES)

func fix_zero_length_notes():
	# Fix all notes with duration below minimum
	var fixed_count = 0
	var zero_count = 0
	
	for note in EditorData.notes:
		if note.duration <= 0:
			zero_count += 1
			note.duration = EditorData.MIN_NOTE_DURATION
			fixed_count += 1
		elif note.duration < EditorData.MIN_NOTE_DURATION:
			note.duration = EditorData.MIN_NOTE_DURATION
			fixed_count += 1
	
	if fixed_count > 0:
		print("Fixed %d notes (including %d zero-length notes)" % [fixed_count, zero_count])
		EditorData.notes_changed.emit()
		
		# Show popup message to user
		if midi_editor:
			var message = "Fixed %d notes:\n" % fixed_count
			message += "- %d were zero-length\n" % zero_count
			message += "- %d were below minimum\n" % (fixed_count - zero_count)
			message += "\nAll set to minimum duration: 1/64th beat"
			midi_editor.show_message_popup("Notes Fixed", message)
	else:
		print("No notes needed fixing")
		if midi_editor:
			midi_editor.show_message_popup("No Issues Found", "All notes already meet the minimum duration requirement.")

func jump_to_previous_section():
	# Find section notes (lane 0) before current playback position
	var current_beat = EditorData.seconds_to_beats(EditorData.current_time)
	var previous_beat = -1.0
	
	for note in EditorData.notes:
		if note.lane == 0 and note.beat_position < current_beat:
			previous_beat = max(previous_beat, note.beat_position)
	
	if previous_beat >= 0:
		var time_seconds = EditorData.beats_to_seconds(previous_beat)
		if midi_editor:
			midi_editor.seek_to_time(time_seconds)
		
		# Scroll to position
		var x = beat_to_pixel(previous_beat)
		if scroll_container:
			scroll_container.scroll_horizontal = int(x - LABEL_WIDTH - 100)
		
		print("Jumped to previous section at beat %.2f" % previous_beat)
	else:
		print("No previous section found")

func jump_to_next_section():
	# Find section notes (lane 0) after current playback position
	var current_beat = EditorData.seconds_to_beats(EditorData.current_time)
	var next_beat = INF
	
	for note in EditorData.notes:
		if note.lane == 0 and note.beat_position > current_beat:
			next_beat = min(next_beat, note.beat_position)
	
	if next_beat < INF:
		var time_seconds = EditorData.beats_to_seconds(next_beat)
		if midi_editor:
			midi_editor.seek_to_time(time_seconds)
		
		# Scroll to position
		var x = beat_to_pixel(next_beat)
		if scroll_container:
			scroll_container.scroll_horizontal = int(x - LABEL_WIDTH - 100)
		
		print("Jumped to next section at beat %.2f" % next_beat)
	else:
		print("No next section found")

# Undo/Redo system
func save_history():
	# Save current state to history
	# Remove any future history if we're not at the end
	if history_index < history_stack.size() - 1:
		history_stack.resize(history_index + 1)
	
	# Create a deep copy of current notes
	var state: Array = []
	for note in EditorData.notes:
		state.append({
			"beat_position": note.beat_position,
			"lane": note.lane,
			"clock_position": note.clock_position,
			"velocity": note.velocity,
			"midi_note": note.midi_note,
			"duration": note.duration
		})
	
	history_stack.append(state)
	history_index += 1
	
	# Limit history size
	if history_stack.size() > MAX_HISTORY_SIZE:
		history_stack.pop_front()
		history_index -= 1

func reset_history():
	# Clear history and save current state as new starting point
	# Used after loading MIDI files
	history_stack.clear()
	history_index = -1
	save_history()
	print("History reset")

func undo():
	if history_index <= 0:
		print("Nothing to undo")
		return
	
	history_index -= 1
	restore_history_state(history_stack[history_index])
	print("Undo - History index: %d/%d" % [history_index, history_stack.size() - 1])

func redo():
	if history_index >= history_stack.size() - 1:
		print("Nothing to redo")
		return
	
	history_index += 1
	restore_history_state(history_stack[history_index])
	print("Redo - History index: %d/%d" % [history_index, history_stack.size() - 1])

func restore_history_state(state: Array):
	# Clear current notes
	EditorData.notes.clear()
	selected_notes.clear()
	
	# Restore notes from state
	for note_data in state:
		var note = EditorData.NoteData.new(
			note_data["beat_position"],
			note_data["lane"],
			note_data["clock_position"],
			note_data["velocity"],
			note_data["midi_note"],
			note_data["duration"]
		)
		EditorData.notes.append(note)
	
	EditorData.notes_changed.emit()
	queue_redraw()

# Arrow key nudging
func nudge_selected_notes(beat_offset: int, lane_offset: int, large_movement: bool):
	if selected_notes.is_empty():
		return
	
	# Save state for undo
	save_history()
	
	# Shift+Arrow on edge notes = mirror across clock
	if large_movement and (beat_offset != 0 or lane_offset != 0):
		# Check if any selected notes are edge notes
		var has_edge_notes = false
		for note in selected_notes:
			if note.lane >= 8 and note.lane <= 19:
				has_edge_notes = true
				break
		
		if has_edge_notes:
			mirror_edge_notes(beat_offset, lane_offset)
			return
		else:
			# No edge notes selected, do nothing for shift+arrow
			print("Shift+Arrow only works on edge notes")
			return
	
	# Normal arrow key nudging
	var division_size = 1.0 / float(EditorData.snap_division)
	var time_offset = beat_offset * division_size
	
	# Apply offset to all selected notes
	for note in selected_notes:
		# Apply time offset
		if time_offset != 0:
			note.beat_position += time_offset
			note.beat_position = max(0.0, note.beat_position)  # Don't go negative
		
		# Apply lane offset
		if lane_offset != 0:
			var new_lane = note.lane + lane_offset
			new_lane = clamp(new_lane, 0, NUM_LANES - 1)
			
			if new_lane != note.lane:
				note.lane = new_lane
				note.midi_note = EditorData.get_midi_note_for_lane(new_lane)
				note.clock_position = EditorData.get_clock_position_for_lane(new_lane)
	
	EditorData.notes_changed.emit()
	queue_redraw()
	
	var direction = ""
	if beat_offset < 0: direction = "left"
	elif beat_offset > 0: direction = "right"
	elif lane_offset < 0: direction = "up"
	elif lane_offset > 0: direction = "down"
	
	print("Nudged %d notes %s" % [selected_notes.size(), direction])

func mirror_edge_notes(beat_offset: int, lane_offset: int):
	# Mirror edge notes across clock axes
	# Shift+Left/Right: Horizontal mirror (12 and 6 stay same)
	# Shift+Up/Down: Vertical mirror (3 and 9 stay same)
	
	var mirrored_count = 0
	
	for note in selected_notes:
		if note.lane < 8 or note.lane > 19:
			continue  # Skip non-edge notes
		
		var clock_pos = note.clock_position
		var new_clock_pos = clock_pos
		
		if beat_offset != 0:
			# Horizontal mirror (Shift+Left/Right)
			match clock_pos:
				0: new_clock_pos = 0  # 12 stays same
				1: new_clock_pos = 11  # 1 <-> 11
				2: new_clock_pos = 10  # 2 <-> 10
				3: new_clock_pos = 9   # 3 <-> 9
				4: new_clock_pos = 8   # 4 <-> 8
				5: new_clock_pos = 7   # 5 <-> 7
				6: new_clock_pos = 6   # 6 stays same
				7: new_clock_pos = 5   # 7 <-> 5
				8: new_clock_pos = 4   # 8 <-> 4
				9: new_clock_pos = 3   # 9 <-> 3
				10: new_clock_pos = 2  # 10 <-> 2
				11: new_clock_pos = 1  # 11 <-> 1
		
		elif lane_offset != 0:
			# Vertical mirror (Shift+Up/Down)
			match clock_pos:
				0: new_clock_pos = 6   # 12 <-> 6
				1: new_clock_pos = 5   # 1 <-> 5
				2: new_clock_pos = 4   # 2 <-> 4
				3: new_clock_pos = 3   # 3 stays same
				4: new_clock_pos = 2   # 4 <-> 2
				5: new_clock_pos = 1   # 5 <-> 1
				6: new_clock_pos = 0   # 6 <-> 12
				7: new_clock_pos = 11  # 7 <-> 11
				8: new_clock_pos = 10  # 8 <-> 10
				9: new_clock_pos = 9   # 9 stays same
				10: new_clock_pos = 8  # 10 <-> 8
				11: new_clock_pos = 7  # 11 <-> 7
		
		if new_clock_pos != clock_pos:
			# Update note's lane based on new clock position
			var new_lane = 8 + new_clock_pos  # Edge notes start at lane 8
			note.lane = new_lane
			note.clock_position = new_clock_pos
			note.midi_note = EditorData.get_midi_note_for_lane(new_lane)
			mirrored_count += 1
	
	EditorData.notes_changed.emit()
	queue_redraw()
	
	var mirror_type = "horizontal" if beat_offset != 0 else "vertical"
	print("Mirrored %d edge notes (%s)" % [mirrored_count, mirror_type])
