extends Control

@onready var check_box: CheckBox = $PanelContainer/VBoxContainer/HBoxContainer/CheckBox

func _ready():
	if FileAccess.file_exists("user://skip_intro_panel.cfg"):
		print("skipping intro")
		queue_free()
	

func _on_button_pressed() -> void:
	if check_box.button_pressed:
		var skip_file = ConfigFile.new()
		skip_file.set_value("delete_this_file_to_bring_back_intro_panel", "thanks", "for_using")
		skip_file.save("user://skip_intro_panel.cfg")

	queue_free()
