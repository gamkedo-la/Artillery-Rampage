class_name RoundDirector extends Node

var tank_controllers: Array = []
var active_player_index: int = -1

@export 
var physics_check_time: float = 0.25

@export
var max_fall_check_time:float = 20.0

var fall_check_timer: Timer

signal tanks_stopped_falling

var _fall_check_elapsed_time:float = 0.0

var current_gamestate: GameState

func _ready():
	current_gamestate = create_new_gamestate() # TODO: loading saved gamestate
	
	fall_check_timer = Timer.new()
	fall_check_timer.set_wait_time(0.5)
	fall_check_timer.set_one_shot(false)
	fall_check_timer.connect("timeout", _on_fall_check_timeout)
	fall_check_timer.autostart = false
	
	add_child(fall_check_timer)
	
func add_controller(tank_controller) -> void:
	tank_controllers.append(tank_controller)
	
func _on_fall_check_timeout():
	_fall_check_elapsed_time += fall_check_timer.wait_time
	
	if !is_any_tank_falling():
		print("_on_fall_check_timeout: Stopping fall_check_timer")
		_stop_fall_check_timer()
	elif _fall_check_elapsed_time >= max_fall_check_time:
		push_warning("_on_fall_check_timeout: Fall check timer exceeded max time of %fs - Force stopping the timer")
		_stop_fall_check_timer()
		
func _stop_fall_check_timer() -> void:
	fall_check_timer.stop()
	tanks_stopped_falling.emit()
	_fall_check_elapsed_time = 0.0
	
func begin_round() -> bool:
	
	GameEvents.connect("turn_ended", _on_turn_ended)
	
	for controller: TankController in tank_controllers:
		controller.tank.connect("tank_killed", _on_tank_killed)
		controller.intent_to_act.connect(current_gamestate.queue_action)
		
	# Order of tanks is always random per original "Tank Wars"
	tank_controllers.shuffle()
	
	# Await at start in case tanks are falling at start
	# TODO: Maybe remove this before release
	await _async_check_and_await_falling()
	
	GameEvents.emit_round_started()
	
	return next_player()

func next_player() -> bool:
	# If there are 1 or 0 players left then the round is over
	if tank_controllers.size() <= 1:
		active_player_index = -1
		return false
		
	active_player_index = (active_player_index + 1) % tank_controllers.size()
	var active_player = tank_controllers[active_player_index]
	
	print("Turn beginning for %s" % [active_player.name])
	
	active_player.begin_turn()
	GameEvents.emit_turn_started(active_player)
	
	return true
	
func _on_turn_ended(controller: TankController) -> void:
	print("Turn ended for " + controller.name)
	await _async_check_and_await_falling()
	
	if !next_player():
		GameEvents.emit_round_ended()
		return

func _async_check_and_await_falling() -> void:
	 # Wait for physics to settle prior to allowing next player to start
	# or just make this class a Node and add to tree from Game
	var scene_tree = get_tree()

	# Wait a smidge and then check if any tank is falling and give time for physics to settle
	await scene_tree.create_timer(physics_check_time).timeout
	
	if is_any_tank_falling():
		print("_on_turn_ended: At least one tank falling - Starting fall_check_timer")
		fall_check_timer.start()
		await tanks_stopped_falling		
		
func is_any_tank_falling() -> bool:
	for controller in tank_controllers:
		if is_instance_valid(controller) && controller.tank.is_falling():
			return true
	return false
	
func _on_tank_killed(tank: Tank, _instigatorController: Node2D, _instigator: Node2D):
	# Need to reset the active player index when removing the controller
	var tank_controller_to_remove: TankController = tank.owner
	if !is_instance_valid(tank_controller_to_remove):
		push_warning("tank=" + tank.name + " has no owner controller")
		return
	var index_to_remove: int = tank_controllers.find(tank_controller_to_remove)
	if(index_to_remove < 0):
		push_warning("TankController=" + tank_controller_to_remove.name + " is not in round")
		return
	
	tank_controllers.erase(tank_controller_to_remove)
	
	# See if we need to shift the active player index
	if index_to_remove <= active_player_index:
		active_player_index -= 1
		if active_player_index < 0:
			active_player_index = tank_controllers.size() - 1
			

#region Game State
func create_new_gamestate() -> GameState:
	return GameState.new()

class GameState extends Resource: # Resource supports save/load
	class Action:
		var action: Callable
		var caller: Object
		# I just realized I recreated the Callable class but maybe we'll extend it
		
	var action_queue:Array[Action]
	
	func run_action(action: Action) -> void:
		action.action.call()
		
	func run_next_action() -> void:
		pop_next_action().action.call_deferred()
	
	func queue_action(action: Callable, caller: Object) -> void:
		var new_action = Action.new()
		new_action.action = action
		new_action.owner = caller
		action_queue.append(new_action)
		
	func get_actions() -> Array[Action]:
		return action_queue
	
	func get_next_action() -> Action:
		return action_queue.front()
		
	func get_actions_by_owner(action_owner: Object) -> Array[Action]:
		return action_queue.filter(_check_action_owner.bind(action_owner))
	
	func erase_actions_by_owner(action_owner: Object) -> void:
		action_queue = action_queue.filter(_check_action_owner.bind(action_owner, true))
		
	func pop_next_action() -> Action:
		return action_queue.pop_front()
	
	func _check_action_owner(action: Action, check: Object, invert:bool = false) -> bool:
		if action.caller == check: return true if not invert else false
		else: return false if not invert else true
#endregion
