## Resets the player's starting weapons at the beginning of story mode
## as upgrades and weapons are earned through story progression and purchases through scrap and personnel
extends Node

var _level:GameLevel

# Assumes that we are in story mode, though technically could use it for any game mode if want to reset the state
func _ready() -> void:
	# Skip if precompiler running
	if SceneManager.is_precompiler_running:
		return
	# Level has already been loaded
	_on_init(SceneManager.get_current_level_root())

func _on_init(level:GameLevel) -> void:
	# Assumes that we only save when completing a level
	_level = level

	# Need to wait for round start to make sure all level state loaded
	GameEvents.player_added.connect(_check_reset_weapons)
	
func _check_reset_weapons(player: TankController) -> void:
	if not player is Player:
		return
		
	if not _should_reset_weapons(_level):
		return
	print_debug("%s: Reset weapons for player on first level=%s of first run" % [name, _level.level_name])

	# Assumes first weapon is the default one that player should start with
	var existing_weapons:Array[Weapon] = player.get_weapons()
	if not existing_weapons:
		push_warning("%s: Player=%s has no weapons!" % [name, player])
		return
	
	# Make copy of default starting weapon since we are about to destroy all the weapons
	var default_starting_weapon: Weapon = existing_weapons.front().duplicate()
	print_debug("%s: Starting with weapon=%s" % [name, default_starting_weapon.display_name])

	player.remove_all_weapons(true)
	player.attach_weapons([default_starting_weapon])

func _should_reset_weapons(level:GameLevel) -> bool:
	# If this is not the first level or not the first run, then there is nothing to do 
	if SceneManager._current_level_index > 0:
		print_debug("%s: Skip resetting weapons as level=%s is level %d" % [name, level.level_name, SceneManager._current_level_index])
		return false
	
	var story_level_state:StoryLevelState = SceneManager.story_level_state
	if not story_level_state:
		push_warning("%s: StoryLevelState not found in tree - unable to check run number" % name)
		return true
	
	var run_count:int = story_level_state.run_count
	if run_count > 1:
		print_debug("%s: Skip resetting weapons as this is run %d" % [name, run_count])
		return false
	return true	
