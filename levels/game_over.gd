extends CanvasLayer


# Called when the node enters the scene tree for the first time.
func _ready():
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta):
	pass


func _on_retry_pressed():
	get_tree().change_scene_to_file("res://levels/test/test_level_01.tscn")


func _on_quit_pressed():
	get_tree().change_scene_to_file("res://levels/main_menu.tscn")
