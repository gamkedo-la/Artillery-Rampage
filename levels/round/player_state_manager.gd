## Keeps track of player state between rounds and establishes this state at the start of the round
extends Node

## Toggles whether player state tracking should be enabled
## If disabled then each round will be independent of the others
var enable:bool:
	set(value):
		enable = value
		if value:
			print_debug("enable")
			_connect_events()
		else:
			print_debug("disable")
			_disconnect_events()
			clear()
	get:
		return enable

var player: Player
var player_state: PlayerState
var _dirty:bool
	
func clear() -> void:
	player = null
	player_state = null
	_dirty = false

func _connect_events() -> void:
	if not GameEvents.round_started.is_connected(_on_round_started):
		GameEvents.round_started.connect(_on_round_started)
	if not GameEvents.player_added.is_connected(_on_player_added):
		GameEvents.player_added.connect(_on_player_added)
	if not GameEvents.round_ended.is_connected(_on_round_ended):
		GameEvents.round_ended.connect(_on_round_ended)
	if not GameEvents.level_loaded.is_connected(_on_level_loaded):
		GameEvents.level_loaded.connect(_on_level_loaded)
	
func _disconnect_events() -> void:
	if GameEvents.round_started.is_connected(_on_round_started):
		GameEvents.round_started.disconnect(_on_round_started)
	if GameEvents.player_added.is_connected(_on_player_added):
		GameEvents.player_added.disconnect(_on_player_added)
	if GameEvents.level_loaded.is_connected(_on_level_loaded):
		GameEvents.level_loaded.disconnect(_on_level_loaded)

	if is_instance_valid(player):
		if player.player_killed.is_connected(_on_player_killed):
			player.player_killed.disconnect(_on_player_killed)
		if not player.is_inside_tree():
			# This means that duplicate/removed child node was never added to tree so we need to manually free
			player.queue_free()
		player = null
		
func _on_level_loaded(_level:GameLevel) -> void:
	_dirty = false
	
func _on_round_started() -> void:
	pass

func _on_player_added(p_player: TankController) -> void:
	# Called before player added to the tree
	if p_player is not Player:
		return
	player = p_player

	player.player_killed.connect(_on_player_killed)
	if not player_state:
		print_debug("%s - no player state, skipping" % [name])
		return
	
	player.pending_state = player_state
	
func _on_round_ended() -> void:
	# Player will only be valid here on win
	_snapshot_player_state(true)

	# Will become invalid when the instance is destroyed by the current SceneTree
	player = null
	
func _on_player_killed(_player:Player) -> void:
	_snapshot_player_state(false)

func _snapshot_player_state(include_curr_health:bool) -> void:
	if not player:
		return

	# Retain any previously unlocked weapons
	var new_player_state:PlayerState = player.create_player_state().include_unlocks_from(player_state)
	if not include_curr_health:
		new_player_state.health = player_state.health if player_state else new_player_state.max_health
	
	player_state = new_player_state
	_dirty = true
#region Savable

func restore_from_save_state(save: SaveState) -> void:
	if not enable:
		clear()
		return
	if SaveStateManager.consume_state_flag(SceneManager.new_story_selected, &"player"):
		PlayerState.delete_save_state(StorySaveUtils.get_story_save(save))
		clear()
		return
	if _dirty:
		# We need to save state first
		return	
	
	player_state = PlayerState.deserialize_from_save_state(StorySaveUtils.get_story_save(save))
	print_debug("%s: restore_from_save_state: %s" % [name, is_instance_valid(player_state)])

func update_save_state(game_state:SaveState) -> void:
	if not enable or not player_state:
		return
	var story_state:Dictionary = StorySaveUtils.get_story_save(game_state, true)
	player_state.serialize_save_state(story_state)
	_dirty = false
	print_debug("%s: update_save_state" % name)
#endregion
