# res://circular_preview.gd
extends Control

const RADIUS = 150.0
const NUM_POSITIONS = 12

var center: Vector2

func _ready():
	center = size / 2
	EditorData.notes_changed.connect(queue_redraw)
	EditorData.playback_position_changed.connect(_on_playback_updated)

func _draw():
	# Outer circle
	draw_arc(center, RADIUS, 0, TAU, 64, Color.WHITE, 2.0)
	
	# Clock position markers
	for i in range(NUM_POSITIONS):
		var angle = (i * TAU / NUM_POSITIONS) - PI/2  # Start at 12 o'clock
		var marker_pos = center + Vector2(cos(angle), sin(angle)) * RADIUS
		
		# Marker circle
		draw_circle(marker_pos, 10.0, Color(0.5, 0.5, 0.5))
		
		# Position number
		#var font = ThemeDB.fallback_font
		#draw_string(font, marker_pos - Vector2(5, -5), str(i+1), 
		#			HORIZONTAL_ALIGNMENT_CENTER, -1, 14, Color.WHITE)
		
		# Line to center
		draw_line(center, marker_pos, Color(0.3, 0.3, 0.3), 1.0)
	
	# Draw upcoming notes
	draw_upcoming_notes()

func draw_upcoming_notes():
	var lookahead_time = 1.2  # seconds
	var current_beat = EditorData.seconds_to_beats(EditorData.current_time)
	var end_beat = current_beat + EditorData.seconds_to_beats(lookahead_time)
	
	for note in EditorData.notes:
		if note.beat_position < current_beat:
			continue
		if note.beat_position > end_beat:
			break
		
		# Only show edge notes (lanes 8-19) and center notes (lane 7)
		if note.lane < 7 or note.lane > 19:
			continue
		
		# Calculate distance from center based on time-to-hit
		var time_to_hit = EditorData.beats_to_seconds(note.beat_position - current_beat)
		var distance_percent = 1.0 - (time_to_hit / lookahead_time)
		var current_radius = lerp(0.0, RADIUS, distance_percent)
		
		var note_pos: Vector2
		
		# Center note (lane 7) - draw at center
		if note.lane == 7:
			note_pos = center
		else:
			# Edge note (lanes 8-19) - draw at clock position
			var angle = (note.clock_position * TAU / NUM_POSITIONS) - PI/2
			note_pos = center + Vector2(cos(angle), sin(angle)) * current_radius
		
		# Draw note
		var color = get_velocity_color(note.velocity)
		draw_circle(note_pos, 8.0, color)
		
		# Hit indicator at perfect timing
		if abs(time_to_hit) < 0.05:
			draw_circle(note_pos, 12.0, Color.WHITE, false, 2.0)

func get_velocity_color(vel: int) -> Color:
	match vel:
		1: return Color(0.3, 0.6, 0.9)   # Target Note - Blue
		3: return Color(0.9, 0.4, 0.4)   # Swipe Left - Red
		5: return Color(0.4, 0.9, 0.4)   # Swipe Right - Green
		6: return Color(0.9, 0.6, 0.2)   # Cross Note - Orange
		7: return Color(0.7, 0.4, 0.9)   # Soft Note - Purple
		9: return Color(0.9, 0.9, 0.3)
		_: return Color.WHITE

func _on_playback_updated(time: float):
	queue_redraw()
