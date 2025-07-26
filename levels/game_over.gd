extends Control

@onready var retry_button:Button = %retry
@onready var quit_button:Button = %quit

# Called when the node enters the scene tree for the first time.
func _ready():
	Juice.fade_in(self, Juice.SLOW, Color.BLACK)

func _on_retry_pressed():
	SaveStateManager.start_new_story_with_new_save()
	disable_buttons()

func _on_quit_pressed():
	StorySaveUtils.delete_story_save()
	SceneManager.switch_scene_keyed(SceneManager.SceneKeys.MainMenu)
	
	disable_buttons()

func disable_buttons() -> void:
	retry_button.disabled = true
	quit_button.disabled = true
