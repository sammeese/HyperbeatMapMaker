extends Node

# MIDI data
var midi_data: Resource  # From G0retZ library
var bpm: float = 120.0
var ppq: int = 480  # Pulses per quarter note
var time_signature_numerator: int = 4  # Beats per measure
var time_signature_denominator: int = 4  # Beat unit (4 = quarter note)

var audio_file_path: String = ""
var audio_offset: float = 0.0  # Audio offset in seconds (positive = audio plays later)
var playback_speed: float = 1.0  # Current playback speed multiplier

# Editor state
var notes: Array[NoteData] = []
var current_time: float = 0.0
var is_playing: bool = false
var snap_division: int = 4  # 1/16th notes
var snap_enabled: bool = true  # Grid snap toggle
var lane_height: int = 20  # Height of each lane in pixels
var waveform_amplitude: float = 1.0  # Amplitude multiplier for waveform display
var metronome_enabled: bool = false  # Metronome click during playback
var note_hits_enabled: bool = false  # Play sound when notes trigger during playback

const LANE_COUNT = 21  # Actually 21 lanes based on your note list
const MIN_NOTE_DURATION = 0.015625  # 1/64th of a beat (minimum note length)

# MIDI note assignments for each lane
const LANE_MIDI_NOTES = [
	0,   # Lane 0
	7,   # Lane 1
	8,   # Lane 2
	9,   # Lane 3
	10,  # Lane 4
	21,  # Lane 5
	22,  # Lane 6
	23,  # Lane 7
	24,  # Lane 8  - Edge Note 1
	25,  # Lane 9  - Edge Note 2
	26,  # Lane 10 - Edge Note 3
	27,  # Lane 11 - Edge Note 4
	28,  # Lane 12 - Edge Note 5
	29,  # Lane 13 - Edge Note 6
	30,  # Lane 14 - Edge Note 7
	31,  # Lane 15 - Edge Note 8
	32,  # Lane 16 - Edge Note 9
	33,  # Lane 17 - Edge Note 10
	34,  # Lane 18 - Edge Note 11
	35,  # Lane 19 - Edge Note 12
	36,  # Lane 20
]

# Lane labels (you can customize these)
const LANE_LABELS = [
	"Sections",      # Lane 0
	"Tunnel",      # Lane 1
	"Tunnel",      # Lane 2
	"Ornaments",      # Lane 3
	"Ornaments",     # Lane 4
	"V Mirror",     # Lane 5
	"H Mirror",     # Lane 6
	"Center",     # Lane 7
	"Edge 12",      # Lane 8
	"Edge 1",      # Lane 9
	"Edge 2",      # Lane 10
	"Edge 3",      # Lane 11
	"Edge 4",      # Lane 12
	"Edge 5",      # Lane 13
	"Edge 6",      # Lane 14
	"Edge 7",      # Lane 15
	"Edge 8",      # Lane 16
	"Edge 9",     # Lane 17
	"Edge 10",     # Lane 18
	"Edge 11",     # Lane 19
	"Sustain",     # Lane 20
]


# Signals
signal notes_changed
signal playback_position_changed(time: float)
signal bpm_changed(new_bpm: float)
signal lane_height_changed(new_height: int)
signal time_signature_changed(numerator: int, denominator: int)

class NoteData:
	var beat_position: float
	var lane: int  # 0-20
	var clock_position: int  # 0-11 for edge notes, -1 for others
	var velocity: int  # Actual MIDI velocity (1-127)
	var midi_note: int  # Actual MIDI note number
	var duration: float = 1.0  # Duration in beats
	
	func _init(pos: float, l: int, clock: int, vel: int, note: int, dur: float = 1.0):
		beat_position = pos
		lane = l
		clock_position = clock
		velocity = vel
		midi_note = note
		duration = dur

func add_note(note: NoteData):
	notes.append(note)
	notes.sort_custom(func(a, b): return a.beat_position < b.beat_position)
	notes_changed.emit()

func remove_note(note: NoteData):
	notes.erase(note)
	notes_changed.emit()

static func get_midi_note_for_lane(lane: int) -> int:
	if lane >= 0 and lane < LANE_MIDI_NOTES.size():
		return LANE_MIDI_NOTES[lane]
	return 60  # Default fallback

# Helper function to get clock position from lane (for Edge Notes only)
static func get_clock_position_for_lane(lane: int) -> int:
	if lane >= 8 and lane <= 19:  # Edge Notes (lanes 8-19)
		return (lane - 8)  # Returns 0-11
	return -1  # Not an edge note

func beats_to_ticks(beats: float) -> int:
	return int(beats * ppq)

func ticks_to_beats(ticks: int) -> float:
	return float(ticks) / ppq

func seconds_to_beats(seconds: float) -> float:
	return (seconds * bpm) / 60.0

func beats_to_seconds(beats: float) -> float:
	return (beats * 60.0) / bpm

func get_beats_per_measure() -> float:
	# Convert denominator to quarter note equivalents
	# e.g., 4 = quarter note = 1 beat, 8 = eighth note = 0.5 beat
	var beat_value = 4.0 / float(time_signature_denominator)
	return float(time_signature_numerator) * beat_value

func beat_to_measure_and_beat(beat: float) -> Dictionary:
	var beats_per_measure = get_beats_per_measure()
	var measure = int(beat / beats_per_measure)
	var beat_in_measure = fmod(beat, beats_per_measure)
	return {"measure": measure, "beat": beat_in_measure}
