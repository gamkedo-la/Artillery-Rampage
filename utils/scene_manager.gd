extends Node

@export var levels_always_selectable: StoryLevelsResource ## These levels are immediately & always available to select.
var is_switching_scene: bool
var is_precompiler_running:bool = false

enum PlayMode {
	DIRECT, # Happens with playing level directly
	STORY,
	PLAY_NOW,
	LEVEL_SELECT
}

class SceneKeys:
	const MainMenu:StringName = &"MainMenu"
	#const PauseMenu:StringName = &"PauseMenu"
	const RandomStart:StringName = &"RandomStart"
	
	const StoryMap:StringName = &"StoryMap"
	const StoryStart:StringName = &"StoryStart"
	const RoundSummary:StringName = &"RoundSummary"

	const GameOver:StringName = &"GameOver"

# We expect to reference the above keys with a const "preload" of a packed scene 
# or reference to a unique name (possibly for pause menu)

# Don't use PackedScene as we don't want all the scene data to be preloaded at the start of the game
@export var story_levels: StoryLevelsResource

const default_delay: float = 2.0

const main_menu_scene_file = "res://levels/main_menu.tscn"
const story_start_scene_file = "res://ui/story/story_sequence.tscn"
const story_map_scene_file = "res://ui/story/map/story_map_scene.tscn"
const story_round_summary_scene_file = "res://ui/story/round_summary/story_round_summary.tscn"
const game_over_scene_file = "res://levels/game_over.tscn"

var _story_level_state_scene:PackedScene = preload("res://levels/story_level_state.tscn")

var _current_level_index:int = -1
var _current_level_root_node:GameLevel
var _current_story_level:StoryLevel

var play_mode:PlayMode

const new_story_selected:StringName = &"NewStory"

var current_scene:Node = null:
	get: return current_scene if current_scene else get_tree().current_scene
	set(value):
		current_scene = value
	
# Any scene, even if it is a UI scene and not a game level scene
var _last_scene_resource:Resource

# Only the last game level scene
var _last_game_level_resource:Resource

func _ready()->void:
	var root = get_tree().root
	current_scene = root.get_child(root.get_child_count() - 1)
	
func _init() -> void:
	GameEvents.level_loaded.connect(_on_GameLevel_loaded)
	
func get_current_level_root() -> GameLevel:
	#assert(is_instance_valid(_current_level_root_node), "Trying to access root outside of game level.")
	
	if is_instance_valid(_current_level_root_node):
		if _current_level_root_node.is_inside_tree():
			return _current_level_root_node
	else:
		# TODO precompiler bypass
		if not is_precompiler_running:
			push_warning("Trying to access root outside of game level.")
		_current_level_root_node = null
	return null

func quit() -> void:
	get_tree().quit()
	
func restart_level(delay: float = default_delay) -> void:
	print_debug("restart_level: %s, delay=%f" % [str(_current_level_root_node.name) if _current_level_root_node else "NULL", delay])

	if not _last_game_level_resource:
		push_error("restart_level: No last game level resource to restart")
		return

	await _switch_scene(func()->Resource: return _last_game_level_resource, delay)
	
func next_level(delay: float = default_delay) -> void:
	if !story_levels or !story_levels.levels:
		push_error("No levels available to load")
	# TODO: When using procedural maps may need a different strategy or may want to shuffle the levels on start
	# The procedural map could just be a specific scene that has some base configuration and then generates on ready
	# Or we could start proc-gening the next scene during current scene and then just keep in memory and present it here
	_current_level_index = (_current_level_index + 1) % story_levels.levels.size()
	_current_story_level = story_levels.levels[_current_level_index]
	
	print_debug("Loading story level index=%d -> %s" % [_current_level_index, _current_story_level.name])

	await switch_scene_file(_current_story_level.scene_res_path, delay)
	
func set_story_level_index(index:int) -> bool:
	if index >= 0 and index < story_levels.levels.size():
		print_debug("set story level index=%d" % [index])
		_current_level_index = index
		return true
	push_warning("Attempted to set invalid story level index=%d - expected [0, %d)" % [index, story_levels.levels.size()])
	return false
	
# TODO: May move these branches out of the scene manager to keep it more single responsiblity
func level_failed() -> void:
	match play_mode:
		PlayMode.STORY:
			switch_scene_keyed(SceneKeys.RoundSummary)
		PlayMode.DIRECT:
			_default_restart_level()
		_: # default
			restart_level()
			
func _default_restart_level():
	await get_tree().create_timer(default_delay).timeout
	get_tree().reload_current_scene()
			
func level_complete() -> void:
	match play_mode:
		PlayMode.DIRECT:
			_default_restart_level()
		PlayMode.STORY:
			await switch_scene_keyed(SceneKeys.RoundSummary)
		PlayMode.PLAY_NOW:
			# TODO: Logic duplication, possibly different set of levels with PlayNow logic in MainMenu, should consolidate
			if story_levels and story_levels.levels:
				await switch_scene_file(story_levels.levels.pick_random().scene_res_path)
			else:
				restart_level()
		PlayMode.LEVEL_SELECT:
			await switch_scene_keyed(SceneKeys.MainMenu)
			
func switch_scene_keyed(key : StringName, delay: float = default_delay) -> void:
	match key:
		SceneKeys.MainMenu:
			await switch_scene_file(main_menu_scene_file)
		SceneKeys.RandomStart:
			await next_level(delay)
		SceneKeys.StoryStart:
			_current_level_index = -1
			await switch_scene_file(story_start_scene_file)
		SceneKeys.StoryMap:
			await switch_scene_file(story_map_scene_file)
		SceneKeys.RoundSummary:
			await switch_scene_file(story_round_summary_scene_file)
		SceneKeys.GameOver:
			await switch_scene_file(game_over_scene_file)
		_:
			push_error("Unhandled scene key=%s" % [key])
	
func switch_scene(scene: PackedScene, delay: float = default_delay) -> void:
	var display_name = str(scene)
	print_debug("switch_scene: %s, delay=%f" % [display_name, delay])
	await _switch_scene(func()->Resource: return scene, delay)
	
func switch_scene_file(scene: String, delay: float = default_delay) -> void:
	print_debug("switch_scene_file: %s, delay=%f" % [scene, delay])
	# TODO: Consider using resource loader to load async during the delay period
	await _switch_scene(func()->Resource: return load(scene), delay)

func _switch_scene(switchFunc: Callable, delay: float) -> void:
	if is_switching_scene:
		return
	
	SaveStateManager.save_tree_state()
	
	# Avoid two events causing a restart in the same game (e.g. player dies and leaves 1 player remaining)
	is_switching_scene = true
	
	if delay > 0:
		await get_tree().create_timer(delay).timeout
	else:
		await get_tree().process_frame
	
	is_switching_scene = false
	
	var root = get_tree().root
	var root_current_scene = root.get_child(root.get_child_count() - 1)
	root_current_scene.free()
	
	# Await in case the loading is done async
	var new_scene:Resource = await switchFunc.call()
	
	current_scene = new_scene.instantiate()
	_last_scene_resource = new_scene

	#current_scene.scene_file_path = new_scene.resource_path
	
	# Somehow get_tree().current_scene is null inside _ready of the loaded scene
	# even if we do get_tree().current_scene = current_scene before
	# So instead set the current_scene on SceneManager and have it manage the current_scene rather than the tree root
	# So replaced all references to this
	get_tree().root.add_child(current_scene)
	get_tree().current_scene = current_scene
	
	#await get_tree().process_frame

	SaveStateManager.restore_tree_state()
	
	get_tree().paused = false

func _on_GameLevel_loaded(level:GameLevel) -> void:
	print_debug("_on_GameLevel_loaded: level=%s" % [str(level.get_parent().name) if level else "NULL"])
	
	if _current_story_level:
		level.name = _current_story_level.name
		level.add_child(_story_level_state_scene.instantiate())
		
	_current_level_root_node = level

	_last_game_level_resource = _last_scene_resource
