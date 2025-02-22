extends Node

var is_switching_scene: bool

class SceneKeys:
	const MainMenu:StringName = &"MainMenu"
	const PauseMenu:StringName = &"PauseMenu"

# We expect to reference the above keys with a const "preload" of a packed scene 
# or reference to a unique name (possibly for pause menu)

# These are more dynamic levels that we will specify in configuration
# TODO: May want to make these a dictionary with key being level name but then will want to be sure to preserve order

# Don't use PackedScene as we don't want all the scene data to be preloaded at the start of the game
@export var levels: Array[String]
@export var level_names: Dictionary = {}

const default_delay: float = 1.0

var _current_level_index:int = 0

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

func quit() -> void:
	get_tree().quit()
	
func restart_level(delay: float = default_delay) -> void:
	_switch_scene(func(): get_tree().reload_current_scene(), delay)
	
func next_level(delay: float = default_delay) -> void:
	if levels.is_empty():
		push_error("No levels available to load")
	# TODO: When using procedural maps may need a different strategy or may want to shuffle the levels on start
	# The procedural map could just be a specific scene that has some base configuration and then generates on ready
	# Or we could start proc-gening the next scene during current scene and then just keep in memory and present it here
	await switch_scene_file(levels[_current_level_index], delay)
	_current_level_index = (_current_level_index + 1) % levels.size()
		
func switch_scene_keyed(key : StringName, delay: float = default_delay) -> void:
	# TODO: Loading main menu and pause menu
	await next_level(delay)
	
func switch_scene(scene: PackedScene, delay: float = default_delay) -> void:
	_switch_scene(func(): get_tree().change_scene_to_packed(scene), delay)
	
func switch_scene_file(scene: String, delay: float = default_delay) -> void:
	_switch_scene(func(): get_tree().change_scene_to_file(scene), delay)

func _switch_scene(switchFunc: Callable, delay: float) -> void:
	if is_switching_scene:
		return
	
	# Avoid two events causing a restart in the same game (e.g. player dies and leaves 1 player remaining)
	is_switching_scene = true
	await get_tree().create_timer(delay).timeout
	
	is_switching_scene = false
	
	# TODO: Consider using resource loader to load async during the delay period
	switchFunc.call()
