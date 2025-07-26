## Resets the AI's starting weapons at the start of a level in story mode to be in that level's allowed set if it is defined
extends Node

var _ai_config: AIStoryConfig
var _story_level: StoryLevel = SceneManager.current_story_level
var _artillery_spawner:ArtillerySpawner

func _ready() -> void:
	# Skip if precompiler running
	if SceneManager.is_precompiler_running:
		return

	_story_level = SceneManager.current_story_level
	if _story_level:
		# Level has already been loaded
		_on_init(SceneManager.get_current_level_root())
	else:
		push_error("%s: current story level NULL when in story mode!" % [name])

func _try_set_ai_config_for_current_difficulty() -> bool:
	if not _story_level:
		return false

	# Get the ai starting weapons for current difficulty
	_ai_config = _get_ai_config_by_difficulty(_story_level, Difficulty.current_difficulty)
	if not _ai_config:
		print_debug("%s: StoryLevel %s does not have ai starting weapons specified for difficulty=%s" % \
			[name, _story_level.name, EnumUtils.enum_to_string(Difficulty.DifficultyLevel, Difficulty.current_difficulty)])
		return false

	return true

func _get_ai_config_by_difficulty(story_level: StoryLevel, difficulty: Difficulty.DifficultyLevel) -> AIStoryConfig:
	if difficulty == null:
		push_error("%s: Difficulty is currently NULL" % [name])
		return null
	
	var difficulty_ordinal:int = EnumUtils.enum_ordinal(Difficulty.DifficultyLevel, difficulty)

	# If we have a matching difficulty return it; otherwise, get nearest match on lower difficulty
	for i in range(difficulty_ordinal, -1, -1):
		var ai_config: AIStoryConfig = story_level.ai_config_by_difficulty.get(i)
		if ai_config:
			return ai_config
	
	return null

func _on_init(level:GameLevel) -> void:
	print_debug("%s: _on_init: %s" % [name, level.level_name])

	_artillery_spawner = level.spawner

	## Listening in case this is a test level or a level that continues to spawn enemies later
	GameEvents.difficulty_changed.connect(_on_difficulty_changed)

	_modify_artillery_spawner(level.spawner)

func _modify_artillery_spawner(spawner: ArtillerySpawner) -> void:
	if not _try_set_ai_config_for_current_difficulty():
		return

	print_debug("%s: Modify Artillery Spawner - difficulty=%s; ai_types=%s; ai_weapons=%s; ai_weapon_count=%s" % \
		[name, EnumUtils.enum_to_string(Difficulty.DifficultyLevel, Difficulty.current_difficulty), _debug_map_scene_array(_ai_config.artillery_ai_types), _debug_map_scene_array(_ai_config.weapons), str(_ai_config.weapon_count)])
	
	spawner.artillery_ai_starting_weapons = _ai_config.weapons
	spawner.artillery_ai_starting_weapon_count = _ai_config.weapon_count
	
	if _ai_config.artillery_ai_types:
		spawner.artillery_ai_types = _ai_config.artillery_ai_types

	# Spawn counts handled by the general difficulty modifier


func _on_difficulty_changed(_new_difficulty: Difficulty.DifficultyLevel, _old_difficulty: Difficulty.DifficultyLevel) -> void:
	if is_instance_valid(_artillery_spawner):
		_modify_artillery_spawner(_artillery_spawner)

func _debug_map_scene_array(scene_array) -> Array:
	return scene_array.map(func(w): return w.resource_path)
