## Singleton instance that orchestrates modifying the scene tree for story mode
extends Node

## Set sthe story mode level modifiers scene
## This will be kept empty while the system is being developed
## But will be set to "res://story/story_mode_level_modifiers.tscn"
## once the weapon unlock shop at end of level is ready that can be purchased with scrap
## Later can also use scrap to purchase a random mod bundle that can upgrade existing weapons
## These will also be rewarded at the end of a story win with possibly a free choice weapon as well
## Idea is that player will have 1/3 choices for upgrade at end of a win
## 1 will be a one time mod bundle, 1 will be a weapon that can also be purchased later, and 1 will be a passive upgrade like health
## The idea is for this to be a meaningful choice with an opportunity cost associated with it as the exact mod bundle may never appear again
## Maybe we can associate a score with it like "common, uncommon, rare, and legendary"
## Player can also use scrap to refill ammo on existing weapons and a discount if refilling all ammo (as opposed to doing it for each)
## Player can refill health at a personnel discount (50%) of losing it in a loss
@export
var story_mode_level_modifiers_scene:PackedScene

@export
var story_level_state_scene:PackedScene

var _story_level_state:Node
var _story_level_state_added:bool

func _ready() -> void:
	# Only connect if enable the story mode level modifiers
	if not story_mode_level_modifiers_scene:
		return

	GameEvents.scene_switched.connect(_on_scene_switched)

func _exit_tree() -> void:
	if is_instance_valid(_story_level_state):
		_story_level_state.queue_free()
		
func _on_scene_switched(_new_scene: Node) -> void:
	# Skip if not in story mode
	if SceneManager.play_mode != SceneManager.PlayMode.STORY:
		_remove_story_state()
		return

	# Make sure this is a game level and not some other kind of UI screen
	var game_level: GameLevel = _get_game_level()
	if not game_level:
		# Still add a story level state so that state is initialized properly
		if not _story_level_state_added:
			if not is_instance_valid(_story_level_state):
				_story_level_state = create_story_level_state(&"NonGameLevel")
				
			print_debug("%s: Add story level state as child" % name)
			add_child(_story_level_state)
			_story_level_state_added = true
		return
	# Remove from the story mode manager tree since it will be added to the game level
	else:
		_remove_story_state()
	
	# First add story level state
	game_level.add_child(create_story_level_state(&"GameLevel"))
	
	print_debug("Applying story mode level modifiers to game_level=%s" % [game_level.scene_file_path])

	var story_mode_level_modifiers:Node = story_mode_level_modifiers_scene.instantiate()
	game_level.add_child(story_mode_level_modifiers)

func create_story_level_state(name: StringName) -> StoryLevelState:
	var story_level_state:StoryLevelState = story_level_state_scene.instantiate()
	if name:
		story_level_state.name = name
	print_debug("%s: Creating story level state: %s" % [name, story_level_state.name])
	
	return story_level_state
	
func _remove_story_state() -> void:
	if _story_level_state_added:
		print_debug("%s: Remove story level state as child" % name)
		remove_child(_story_level_state)
		_story_level_state_added = false

func _get_game_level() -> GameLevel:
	# Avoid warning on SceneManager
	return get_tree().get_first_node_in_group(Groups.GameLevel)
