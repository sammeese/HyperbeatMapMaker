A simple MIDI editor made for creating custom song charts/maps for HYPERBEAT

I did use AI a fair bit to make this, I do not like AI, I think its cringe, but this kind of thing is outside my wheelhouse and I didn't wanna spend countless hours on whats supposed to be just a basic editor to help me and others.

Please note, that loaded songs will need to START on time with the down beat, otherwise the grid, regardless if the tempo is correct, will be out of time.


Install:

  Two choices - 
    Download from releases
    or 
    Download the source, go to https://godotengine.org/download/archive/4.5-stable/ and get the Godot_v4.5-stable_win64.exe and put it in the project folder (next to project.godot), and run Godot_v4.5-stable_win64.exe 



Known Issues:

  An imported midi containing notes that have a NoteOn and NoteOFf in the same space (ie, a note directly following another with no gaps between) can occasionally merge into a single short note in the middle of the two.
  
  Some of the controls are a bit janky
  
  Currently no support for time signatures or triplet/sextuplet division
