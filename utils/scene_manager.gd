extends Node

var is_switching_scene: bool

class SceneKeys:
	const MainMenu:StringName = &"MainMenu"
	#const PauseMenu:StringName = &"PauseMenu"
	const RandomStart:StringName = &"RandomStart"
	
	const StoryMap:StringName = &"StoryMap"
	const StoryStart:StringName = &"StoryStart"

# We expect to reference the above keys with a const "preload" of a packed scene 
# or reference to a unique name (possibly for pause menu)

# Don't use PackedScene as we don't want all the scene data to be preloaded at the start of the game
@export var story_levels: StoryLevelsResource

const default_delay: float = 1.0

const main_menu_scene_file = "res://levels/main_menu.tscn"
const story_start_scene_file = "res://ui/story/story_sequence.tscn"
const story_map_scene_file = "res://ui/story/map/story_map_scene.tscn"

var _current_level_index:int = 0
var _current_level_root_node:GameLevel
var _current_story_level:StoryLevel

func _init() -> void:
	GameEvents.level_loaded.connect(_on_GameLevel_loaded)
	
func get_current_level_root() -> GameLevel:
	assert(is_instance_valid(_current_level_root_node), "Trying to access root outside of game level.")
	if is_instance_valid(_current_level_root_node):
		if _current_level_root_node.is_inside_tree():
			return _current_level_root_node
	else:
		_current_level_root_node = null
	return null

func quit() -> void:
	get_tree().quit()
	
func restart_level(delay: float = default_delay) -> void:
	print_debug("restart_level: %s, delay=%f" % [str(_current_level_root_node.name) if _current_level_root_node else "NULL", delay])

	_switch_scene(func(): get_tree().reload_current_scene(), delay)
	
func next_level(delay: float = default_delay) -> void:
	if !story_levels or !story_levels.levels:
		push_error("No levels available to load")
	# TODO: When using procedural maps may need a different strategy or may want to shuffle the levels on start
	# The procedural map could just be a specific scene that has some base configuration and then generates on ready
	# Or we could start proc-gening the next scene during current scene and then just keep in memory and present it here
	print_debug("Loading")
	_current_story_level = story_levels.levels[_current_level_index]
	await switch_scene_file(_current_story_level.scene_res_path, delay)
	_current_level_index = (_current_level_index + 1) % story_levels.levels.size()
		
func switch_scene_keyed(key : StringName, delay: float = default_delay) -> void:
	match key:
		SceneKeys.MainMenu:
			await switch_scene_file(main_menu_scene_file)
		SceneKeys.RandomStart:
			await next_level(delay)
		SceneKeys.StoryStart:
			await switch_scene_file(story_start_scene_file)
		SceneKeys.StoryMap:
			await switch_scene_file(story_map_scene_file)
	
func switch_scene(scene: PackedScene, delay: float = default_delay) -> void:
	var display_name = str(scene)
	print_debug("switch_scene: %s, delay=%f" % [display_name, delay])
	await _switch_scene(func(): get_tree().change_scene_to_packed(scene), delay)
	
func switch_scene_file(scene: String, delay: float = default_delay) -> void:
	print_debug("switch_scene_file: %s, delay=%f" % [scene, delay])
	await _switch_scene(func(): get_tree().change_scene_to_file(scene), delay)

func _switch_scene(switchFunc: Callable, delay: float) -> void:
	if is_switching_scene:
		return
	
	# Avoid two events causing a restart in the same game (e.g. player dies and leaves 1 player remaining)
	is_switching_scene = true
	await get_tree().create_timer(delay).timeout
	
	is_switching_scene = false
	
	# TODO: Consider using resource loader to load async during the delay period
	switchFunc.call()
	get_tree().paused = false

func _on_GameLevel_loaded(level:GameLevel) -> void:
	print_debug("_on_GameLevel_loaded: level=%s" % [str(level.name) if level else "NULL"])
	
	if _current_story_level:
		level.name = _current_story_level.name
	_current_level_root_node = level
