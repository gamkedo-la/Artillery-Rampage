extends Node

var _artillery_spawner: ArtillerySpawner
var _story_level: StoryLevel = SceneManager.current_story_level

class WeaponWeights:
	var weapon: PackedScene
	var weight: float

class AIRunLevelWeaponConfig:
	var weapons: Array[WeaponWeights] 
	var additional_weapon_count: int

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

func _on_init(level: GameLevel) -> void:
	print_debug("%s: _on_init: %s" % [name, level.level_name])

	_artillery_spawner = level.spawner
	
	# HACK: We need to wait for the story level state to be restored prior to modifying artillery
	# However, if we wait a frame it's too late as the artillery already spawned
	GameEvents.save_state_restored.connect(_on_save_state_restored.unbind(2))

	# Need to modify the counts given the new difficulty	
	GameEvents.difficulty_changed.connect(_on_difficulty_changed)
	
func _on_save_state_restored() -> void:
	_modify_artillery_spawner(_artillery_spawner)
	GameEvents.save_state_restored.disconnect(_on_save_state_restored)
	
func _modify_artillery_spawner(spawner: ArtillerySpawner) -> void:
	var story_level_state:StoryLevelState = SceneManager.story_level_state
	if not story_level_state:
		push_error("%s: StoryLevelState not found in tree - unable to check run number" % name)
		return
	
	var run_count:int = story_level_state.run_count
	if run_count <= 0:
		push_error("%s: Invalid run count %d" % [name, run_count])
		return
	if run_count == 1:
		print_debug("%s: Skip modifiers on first run" % name)
		return
	
	# Change the AI strength
	var effective_difficulty:Difficulty.DifficultyLevel = _get_effective_difficulty_for_run_count(run_count)
	print_debug("%s: Effective AI difficulty %s -> %s" % \
		[name, EnumUtils.enum_to_string(Difficulty.DifficultyLevel, Difficulty.current_difficulty), EnumUtils.enum_to_string(Difficulty.DifficultyLevel, effective_difficulty)])
	GameEvents.ai_effective_difficulty_changed.emit(effective_difficulty)

	spawner.default_ai_players += Vector2i.ONE * (run_count - 1)

	# Clamp to max
	var max_ai_players:int = _story_level.absolute_max_ai

	spawner.default_ai_players = Vector2i(
		mini(spawner.default_ai_players.x, max_ai_players),
		mini(spawner.default_ai_players.y, max_ai_players)
	)

	var modifier_weapon_config: AIRunLevelWeaponConfig = _get_run_level_weapon_config(spawner, run_count)
	if modifier_weapon_config:
		_modify_ai_weapons_by_config(spawner, modifier_weapon_config)

func _get_effective_difficulty_for_run_count(run_count:int) -> Difficulty.DifficultyLevel:
	var current_difficulty: int = EnumUtils.enum_as_int(Difficulty.current_difficulty)
	var hardest_difficulty: int = EnumUtils.enum_as_int(Difficulty.DifficultyLevel.HARD)

	var effective_difficulty_int: int = current_difficulty + (run_count - 1)

	if effective_difficulty_int >= hardest_difficulty:
		return Difficulty.DifficultyLevel.HARD

	return effective_difficulty_int as Difficulty.DifficultyLevel
	
func _get_run_level_weapon_config(spawner: ArtillerySpawner, run_count: int) -> AIRunLevelWeaponConfig:
	var run_modifiers:AIRunModifiers = SceneManager.story_levels.run_modifiers
	if not run_modifiers:
		return null

	var weapon_config:AIRunLevelWeaponConfig = AIRunLevelWeaponConfig.new()
	weapon_config.weapons = []
	weapon_config.additional_weapon_count = run_modifiers.additional_weapon_count_by_run_count.get(run_count, 0)

	for config in run_modifiers.weapon_config:
		var match_diff:int = run_count - config.min_run_count
		if match_diff < 0:
			continue

		var weapon_weights := WeaponWeights.new()
		weapon_weights.weapon = config.weapon
		if config.weight_by_run.has(match_diff):
			weapon_weights.weight = config.weight_by_run.get(match_diff)
		elif match_diff > 0 and not config.weight_by_run.is_empty():
			# Use largest
			weapon_weights.weight = config.weight_by_run[config.weight_by_run.keys().max()]
		else:
			weapon_weights.weight = 1.0
		
		weapon_config.weapons.push_back(weapon_weights)
	
	# Add existing weapons with weight 1.0 that are not modified
	var scored_weapon_scenes: Array = weapon_config.weapons.map(func(x): return x.weapon)

	for weapon_scene in spawner.artillery_ai_starting_weapons:
		if not scored_weapon_scenes.any(func(scored): return scored.resource_path == weapon_scene.resource_path):
			var weapon_weights := WeaponWeights.new()
			weapon_weights.weapon = weapon_scene
			weapon_weights.weight = 1.0
			weapon_config.weapons.push_back(weapon_weights)

	# Sort so that highest priority weapons come first
	weapon_config.weapons.sort_custom(func(a,b): return a.weight > b.weight)

	return weapon_config

func _modify_ai_weapons_by_config(spawner: ArtillerySpawner, modifier_weapon_config: AIRunLevelWeaponConfig) -> void:
	spawner.artillery_ai_starting_weapon_count += Vector2i.ONE * modifier_weapon_config.additional_weapon_count
	var min_weapon_count:int = spawner.artillery_ai_starting_weapon_count.x
	var max_weapon_count:int = spawner.artillery_ai_starting_weapon_count.y

	var final_weapons:Array[PackedScene] = []
	for weapon_config in modifier_weapon_config.weapons:
		var weight:float = weapon_config.weight
		var weapon_scene:PackedScene = weapon_config.weapon

		if weight > 1.0 \
		 or (is_equal_approx(weight, 1.0) and final_weapons.size() < max_weapon_count) \
		 or (weight < 1.0 and final_weapons.size() < min_weapon_count):
			final_weapons.push_back(weapon_scene)
		else:
			break

	spawner.artillery_ai_starting_weapons = final_weapons
	
	# Add lowest priority weapons next
func _on_difficulty_changed(_new_difficulty: Difficulty.DifficultyLevel, _old_difficulty: Difficulty.DifficultyLevel) -> void:
	# Wait a frame to make sure that the default processing runs first
	await get_tree().process_frame
	if is_instance_valid(_artillery_spawner):
		_modify_artillery_spawner(_artillery_spawner)
