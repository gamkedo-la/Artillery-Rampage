# Abstract base class for AI and player controllers
class_name TankController extends Node2D
@export var enable_damage_before_first_turn:bool = true 
var _initial_fall_damage:bool
@export var weapons_container:Node = self ## Keep all Weapon components in here. If unassigned, self is used.

signal intent_to_act(action: Callable, owner: Object)
var can_take_action:bool = true

## Set player state that has been loaded from previous round
var pending_state: PlayerState

## identifier for team that this player is on 
## If not on a team, then -1 is used
## AI units will not attack those on the same team
@export var team:int = -1

var popups:Array

func _ready() -> void:
	tank.actions_completed.connect(_on_tank_actions_completed)
	GameEvents.connect("turn_ended", _on_turn_ended)
	GameEvents.connect("turn_started", _on_turn_started)
	
	_initial_fall_damage = tank.enable_fall_damage
	
	if !enable_damage_before_first_turn:
		print_debug("TankController(%s) - _ready: Disable fall damage before first turn" % [name])
		tank.enable_fall_damage = false

func is_on_same_team_as(other: TankController) -> bool:
	if team < 0:
		return false
	return team == other.team
	
func begin_round() -> void:
	if pending_state:
		print_debug("TankController(%s) - _ready: Applying pending state" % [name])
		_apply_pending_state(pending_state)
		pending_state = null

func begin_turn() -> void:
	#tank.reset_orientation()
	tank.enable_fall_damage = _initial_fall_damage
	tank.push_weapon_update_to_hud() # TODO: fix for simultaneous fire game
	can_take_action = check_if_must_skip_actions() # Check this in Player/AI for behavior. Will submit empty action if true.
	
func end_turn() -> void:
	clear_all_popups()
	GameEvents.turn_ended.emit(tank.controller) # Because I'm not sure if "self" is abstract in this context
	
var tank: Tank:
	get: return _get_tank()

func _apply_pending_state(state: PlayerState) -> void:
	remove_all_weapons(true)
	# Make sure decouple the weapon object from the state
	attach_weapons(state.get_weapons_copy())

	tank.apply_pending_state(state)

## Capture the current state of the player
## [param p_state] - state to use - useful for subclasses to override if we need derived player state classes
func create_player_state(p_state: PlayerState = null) -> PlayerState:
	var state: PlayerState = p_state if p_state else PlayerState.new()

	state.weapons = get_weapons()
	tank.populate_player_state(state)

	return state

func _get_tank() -> Tank:
	push_error("abstract function")
	return null
	
func get_weapons() -> Array[Weapon]:
	var weapons:Array[Weapon]
	for w in weapons_container.get_children():
		if w is Weapon:
			weapons.append(w)
	return weapons
	
func attach_weapons(weapons: Array[Weapon]) -> void:
	for w in weapons:
		weapons_container.add_child(w)
		w.global_position = tank.global_position # Probably not necessary but Weapon is a Node2D and should be simplified if so.
	tank.scan_available_weapons()
	
func remove_all_weapons(detach_immediately: bool = false) -> void:
	for w in weapons_container.get_children():
		if w is Weapon:
			w.destroy()
			if detach_immediately and w.get_parent():
				w.get_parent().remove_child(w)

func set_color(value: Color) -> void:
	tank.color = value

func _on_turn_ended(_player: TankController) -> void:
	# On any player turn ended, simulate physics	
	tank.toggle_gravity(true)

func _on_turn_started(_player: TankController) -> void:
	# Ony any player turn started, stop simulating physics
	tank.reset_orientation()

func _on_tank_actions_completed(_tank: Tank) -> void:
	end_turn()

func submit_intended_action(action: Callable, player: TankController) -> void:
	if can_take_action:
		print_debug("Submitted action")
		intent_to_act.emit(action, player)
	else:
		skip_action(player) # This is a catch case, should be handled by AI behavior before this, but it does work.

func skip_action(player: TankController) -> void:
	print_debug("Skipping taking actions (this turn)")
	intent_to_act.emit(_skip, player) # Required for turn to advance as RoundDirector is awaiting our ticket
	await get_tree().process_frame
	end_turn()
	
func _skip() -> void:
	pass

func check_if_must_skip_actions() -> bool:
	# Disabling effects like EMP
	var disabling_emp_charge_threshold:float = 50.0
	if tank.debuff_emp_charge > disabling_emp_charge_threshold:
		#print_debug("EMP charge above threshold--turn must be skipped")
		var popup = popup_message(PopupNotification.Contexts.EMP_DISABLED)
		return false
		
	return true

#region Popup Notifications
func popup_message(message:String, pulses:Array = PopupNotification.PulsePresets.Three, lifetime:float = 0.0) -> PopupNotification:
	var popup = PopupNotification.constructor(message, pulses)
	if lifetime > 0.0: # Allows for default from the instance's export var
		popup.lifetime = lifetime
	
	tank.tankBody.add_child(popup) # Because the tankBody moves independently of the tank node...
	
	var offset = Vector2(0.0, 24.0) + (popups.size() * Vector2(0.0, 48.0)) # They stack
	
	# TODO place above tank if near bottom of screen (would be cut off)
	popup.global_position = tank.tankBody.global_position + offset
	
	popup.completed_lifetime.connect(_on_popup_completed_lifetime)
	
	popups.append(popup)
	return popup
	
func clear_all_popups() -> void:
	for popup:PopupNotification in popups:
		popup.fade_out(1.0)
	
# Popup stacking
func _on_popup_completed_lifetime(popup: PopupNotification) -> void:
	popups.erase(popup)
	#print_debug("Active popups: ", popups.size())
#endregion
