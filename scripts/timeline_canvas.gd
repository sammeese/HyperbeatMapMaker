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
var NUM_LANES = EditorData.LANE_COUNT

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
	draw_ruler()  # Draw ruler first (at top)
	draw_grid()
	draw_lane_separators()
	draw_notes()
	draw_selection_box()
	draw_lane_labels()  # Draw labels on top of notes
	draw_playhead()  # Playhead on top of everything

func draw_lane_labels():
	var font = ThemeDB.fallback_font
	
	# Get scroll offset to make labels sticky
	var scroll_offset = scroll_container.scroll_horizontal if scroll_container else 0
	
	for i in range(NUM_LANES):
		var y = RULER_HEIGHT + i * EditorData.lane_height + EditorData.lane_height / 2
		var label = EditorData.LANE_LABELS[i]
		
		# Draw label at fixed position (accounting for scroll)
		var label_x = scroll_offset + 5
		draw_string(font, Vector2(label_x, y), label, HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 10, 12)
	
	# Draw background rectangle behind labels so they're readable
	var label_rect = Rect2(scroll_offset, RULER_HEIGHT, LABEL_WIDTH, size.y - RULER_HEIGHT)
	draw_rect(label_rect, Color(0.15, 0.15, 0.15, 0.95), true)
	
	# Redraw labels on top of background
	for i in range(NUM_LANES):
		var y = RULER_HEIGHT + i * EditorData.lane_height + EditorData.lane_height / 2
		var label = EditorData.LANE_LABELS[i]
		var label_x = scroll_offset + 5
		draw_string(font, Vector2(label_x, y), label, HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 10, 12)

func draw_ruler():
	var font = ThemeDB.fallback_font
	var scroll_offset = scroll_container.scroll_horizontal if scroll_container else 0
	
	# Background for ruler
	draw_rect(Rect2(0, 0, size.x, RULER_HEIGHT), Color(0.2, 0.2, 0.2))
	
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
		draw_line(Vector2(x, 0), Vector2(x, RULER_HEIGHT), Color.WHITE, 2.0)
		
		# Draw bar number
		var bar_label = "Bar %d" % (bar_num + 1)
		draw_string(font, Vector2(x + 5, 15), bar_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)
		
		# Draw timecode (time at this bar)
		var time_at_bar = EditorData.beats_to_seconds(beat)
		var timecode = format_timecode(time_at_bar)
		draw_string(font, Vector2(x + 5, 28), timecode, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0.8, 0.8, 0.8))
		
		# Draw minor ticks (beat lines within bar)
		for beat_offset in range(1, beats_per_bar):
			var minor_beat = beat + beat_offset
			var minor_x = beat_to_pixel(minor_beat)
			
			if minor_x < LABEL_WIDTH:
				continue
			
			draw_line(Vector2(minor_x, RULER_HEIGHT - 10), Vector2(minor_x, RULER_HEIGHT), 
					  Color(0.6, 0.6, 0.6), 1.0)
	
	# Draw sticky label background over ruler
	var label_rect = Rect2(scroll_offset, 0, LABEL_WIDTH, RULER_HEIGHT)
	draw_rect(label_rect, Color(0.15, 0.15, 0.15, 0.95), true)
	
	# Draw "Timeline" label
	draw_string(font, Vector2(scroll_offset + 5, 20), "Timeline", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)

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
		var y = RULER_HEIGHT + note.lane * EditorData.lane_height
		
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
		# Draw vertical line starting below ruler
		draw_line(Vector2(x, RULER_HEIGHT), Vector2(x, size.y), Color(1.0, 0.3, 0.3, 0.8), 3.0)
		
		# Draw triangle at ruler (pointing down into lanes)
		var triangle = PackedVector2Array([
			Vector2(x - 8, RULER_HEIGHT),
			Vector2(x + 8, RULER_HEIGHT),
			Vector2(x, RULER_HEIGHT + 12)
		])
		draw_colored_polygon(triangle, Color(1.0, 0.3, 0.3, 0.9))

func setup_context_menu():
	context_menu = PopupMenu.new()
	add_child(context_menu)
	context_menu.id_pressed.connect(_on_context_menu_selected)

func show_context_menu_for_note(note: EditorData.NoteData, position: Vector2):
	selected_note = note
	context_menu.clear()
	
	# Check if this is an edge note (lanes 8-19)
	if note.lane >= 7 and note.lane <= 19:
		# Edge note - specific velocity options with labels
		context_menu.add_item("Target Note", 1)
		context_menu.add_item("Swipe Left", 3)
		context_menu.add_item("Swipe Right", 5)
		context_menu.add_item("Cross Note", 6)
		context_menu.add_item("Soft Note", 7)
		context_menu.add_item("Bar Note", 9)
	elif note.lane == 20:
		# Sustain lane - specific velocity options
		context_menu.add_item("1 - Blank", 1)
		context_menu.add_item("7 - Blank", 7)
		context_menu.add_item("3 - Left", 3)
		context_menu.add_item("5 - Right", 5)
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
		
		draw_line(Vector2(x, RULER_HEIGHT), Vector2(x, size.y), color, width)
		
func draw_lane_separators():
	for i in range(NUM_LANES + 1):
		var y = RULER_HEIGHT + i * EditorData.lane_height
		var scroll_offset = scroll_container.scroll_horizontal if scroll_container else 0
		draw_line(Vector2(scroll_offset + LABEL_WIDTH, y), Vector2(size.x, y), Color(0.4, 0.4, 0.4), 1.0)
	
	# Vertical line after labels (sticky) - starts below ruler
	var scroll_offset = scroll_container.scroll_horizontal if scroll_container else 0
	draw_line(Vector2(scroll_offset + LABEL_WIDTH, RULER_HEIGHT), Vector2(scroll_offset + LABEL_WIDTH, size.y), Color(0.6, 0.6, 0.6), 2.0)

func draw_notes():
	for note in EditorData.notes:
		if note.lane >= NUM_LANES:
			continue
		
		var x_start = beat_to_pixel(note.beat_position)
		var x_end = beat_to_pixel(note.beat_position + note.duration)
		var y = RULER_HEIGHT + note.lane * EditorData.lane_height
		
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
	var lane = int((pos.y - RULER_HEIGHT) / EditorData.lane_height)
	
	if lane >= NUM_LANES:
		return
	
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
		# Resize note duration
		var end_beat = pixel_to_beat(pos.x)
		var new_duration = end_beat - dragging_note.beat_position
		new_duration = snap_to_grid(new_duration)
		dragging_note.duration = max(EditorData.MIN_NOTE_DURATION, new_duration)
		EditorData.notes_changed.emit()
	
	elif drag_mode == "move":
		# Move note to new position
		var new_beat = pixel_to_beat(pos.x)
		var new_lane = int((pos.y - RULER_HEIGHT) / EditorData.lane_height)
		
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
	# Delete hovered note with Delete or Backspace
	if event.keycode == KEY_DELETE or event.keycode == KEY_BACKSPACE:
		if not selected_notes.is_empty():
			# Delete all selected notes
			for note in selected_notes:
				EditorData.remove_note(note)
			selected_notes.clear()
			queue_redraw()
		elif hovered_note:
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
	
	# Deselect with Escape
	elif event.keycode == KEY_ESCAPE:
		selected_notes.clear()
		queue_redraw()

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
		var y = RULER_HEIGHT + note.lane * EditorData.lane_height
		
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


func get_note_at_position(pos: Vector2) -> EditorData.NoteData:
	var scroll_offset = scroll_container.scroll_horizontal if scroll_container else 0
	
	if pos.x < scroll_offset + LABEL_WIDTH:
		return null
	
	var beat = pixel_to_beat(pos.x)
	var lane = int((pos.y - RULER_HEIGHT) / EditorData.lane_height)
	
	for note in EditorData.notes:
		if note.lane != lane:
			continue
		
		if beat >= note.beat_position and beat <= note.beat_position + note.duration:
			return note
	
	return null


func _on_context_menu_selected(id: int):
	if not selected_note:
		return
	
	if id == 99:
		# Delete
		EditorData.remove_note(selected_note)
	elif id == 100:
		# Show input dialog for velocity
		show_velocity_input_dialog()
	elif id > 0:
		# Set velocity directly (for edge notes)
		selected_note.velocity = id
		EditorData.notes_changed.emit()
	
	if id != 100:  # Don't clear if showing dialog
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

func handle_note_placement(pos: Vector2):
	var beat = pixel_to_beat(pos.x)
	var lane = int((pos.y - RULER_HEIGHT) / EditorData.lane_height)
	
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
	custom_minimum_size.y = RULER_HEIGHT + (EditorData.lane_height * NUM_LANES)

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
