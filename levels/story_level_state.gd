class_name StoryLevelState extends Node

var _last_completed_level:int = -1
var _game_level:GameLevel
var _requires_restore:bool
var _dirty:bool

var _run:int = 1

var run_count: int:
	get: return _run

func _ready() -> void:
	_game_level = get_parent() as GameLevel
	if not _game_level:
		print_debug("%s: Parent=%s is not a GameLevel - not listening for round events" % [name, get_parent().name if get_parent() else &"NULL"])
		return
		
	print_debug("%s: Parent=%s is a GameLevel - connecting to round ended" % [name, get_parent().name])
	GameEvents.round_ended.connect(_on_round_ended)
	# Don't restore from a game level as the current level is set outside a game level
	_requires_restore = false
	
func _enter_tree() -> void:
	_requires_restore = true
	_dirty = false
	GameEvents.story_level_changed.connect(_on_level_changed)
	print_debug("StoryLevelState entered tree: %s" % name)

func _exit_tree() -> void:
	GameEvents.story_level_changed.disconnect(_on_level_changed)
	print_debug("StoryLevelState exited tree: %s" % name)
	
func _on_level_changed(level:int) -> void:
	print_debug("%s: level changed: %d" % [name, level])
	if level < _last_completed_level:
		print_debug("%s: new level=%d < _last_completed_level=%d - updating and incrementing run: %d" % [name, level, _last_completed_level, _run + 1])
		_last_completed_level = level - 1
		_run += 1
		_dirty = true

func _on_round_ended() -> void:
	# TODO: This is kind of hacky but "won" is set in this signal in RoundStatTracker so there could be an ordering issue
	var player_won:bool = not RoundStatTracker.round_data.died
	print_debug("%s: On Round ended: Player won=%s" % [name, player_won])
	
	# Only update last completed on win
	# SceneManager.next_level increments so "current_level_index" is actually the next level here
	if player_won:
		_last_completed_level = SceneManager._current_level_index
		_dirty = true
		print_debug("%s: last_completed_level=%d" % [name, _last_completed_level])
	
#region Savable
const SAVE_STATE_KEY:StringName = &"Story"
const _LEVEL_KEY:StringName = &"Level"
const RUN_KEY:StringName = &"Run"

func restore_from_save_state(save: SaveState) -> void:
	if save and save.state and SaveStateManager.consume_state_flag(SceneManager.new_story_selected, SAVE_STATE_KEY):
		StorySaveUtils.get_story_save(save).erase(_LEVEL_KEY)
		return
	
	if not _dirty:
		_restore_story_level_state(save)

	# Only restore on continue state
	if _requires_restore:
		# Make sure only do this really once from continue story
		if SaveStateManager.consume_state_flag(SceneManager.continue_story_selected, SAVE_STATE_KEY):
			print_debug("%s: set story level index=%d" % [name, _last_completed_level])
			SceneManager.set_story_level_index(_last_completed_level)
		_requires_restore = false

func update_save_state(save:SaveState) -> void:
	if not save or not save.state or not _dirty:
		return
	
	# if _last_completed_level >= 0:
	var state:Dictionary = save.state.get_or_add(SAVE_STATE_KEY, {})
	state[_LEVEL_KEY] = _last_completed_level
	state[RUN_KEY] = _run

	_dirty = false
	print_debug("%s: set save state last completed level=%d" % [name, _last_completed_level])
	
func _restore_story_level_state(save: SaveState) -> void:
	if not save or not save.state:
		return
	
	if not save.state.has(SAVE_STATE_KEY):
		print_debug("%s:No existing story state found" % name)
		return
	
	var state:Dictionary = save.state[SAVE_STATE_KEY]

	_last_completed_level = state.get(_LEVEL_KEY, -1)
	_run = state.get(RUN_KEY, 1)

	print_debug("%s: _restore_story_level_state: last_completed_level=%d; run=%d" % [name, _last_completed_level, _run])
	
#endregion
