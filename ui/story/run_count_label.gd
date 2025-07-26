extends Label

@export var pretext:String = "Run #"
var run_count:int = 0

func _ready() -> void:
	hide()
	if SceneManager:
		# Need to wait a frame to make sure this loads
		await get_tree().process_frame
		if SceneManager.story_level_state:
			run_count = SceneManager.story_level_state.run_count
			if run_count > 1:
				show()
			else:
				hide()
			
			text = pretext + str(run_count)
			return
