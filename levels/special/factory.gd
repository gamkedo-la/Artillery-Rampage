extends Node2D

## Spawn artillery units to start the match, then every so frequently during match
## maybe with a curve or an array of turn count targets.
## When artillery is spawned, it joins a queue.
## This queue is moved by the "conveyor" once length per turn.
## Once an artillery meets the end, it takes turns.
## If there is already an artillery at the end, artillery can queue behind it
## and will immediately deploy when the end artillery dies, effectively replacing it.

signal conveyor_advanced ## This signal is used internally
signal artillery_spawned ## This signal is unused, remove this comment if used

@export var round_director:RoundDirector

@export var schedule:Dictionary[int,int] ## Turn Count, Number to Spawn
@export var damageable_components:Array[DamageableDestructibleObject] # Maybe?
@onready var total_components:int = damageable_components.size()

@export var conveyor_length:int = 4
var conveyor_slot_x_offset:float = 50.0
var conveyor_move_duration:float = 1.0
var conveyor_slots:Array[ConveyorSlot]

@export var explosion_scene:PackedScene = preload("res://items/weapon_projectiles/explosions/explosion_meganuke.tscn")

var turn_counter:int = 0
var popups:Array[PopupNotification]
var emp_disabling_threshold:float = 40.0

@onready var spawnpoint: Marker2D = %Spawnpoint
@onready var game_level:GameLevel = get_parent()


func _ready() -> void:
	if not round_director:
		push_error("Must assign export property Round Director node!")
	round_director.directed_by_external_script = true
	GameEvents.turn_ended.connect(_on_turn_ended) # For turn based logic

	for component in damageable_components: # Observe the components that the player must destroy to kill the factory.
		component.destroyed.connect(_on_component_destroyed)

	for iterator in conveyor_length:
		var new_slot = ConveyorSlot.new()
		new_slot.number = iterator
		new_slot.global_position = (
			spawnpoint.global_position - Vector2(conveyor_slot_x_offset * new_slot.number, 0.0) # Leftward
			)
		conveyor_slots.append(new_slot)

	call_deferred("check_turn")

func try_spawn_new_artillery() -> bool:
	for component in damageable_components:
		if component.can_be_emp_charged:
			if component.emp_charge > emp_disabling_threshold:
				return false ## Disabled from EMP

	var slot = conveyor_slots[0]
	if slot.is_occupied:
		print_debug("Force advancing conveyor.")
		advance_conveyor()
		await conveyor_advanced
		if slot.is_occupied:
			print_debug("Slot ", slot.number, " still occupied. (Belt is full?) Cancelling spawn.")
			return false # Belt is full

	## Something with how the decoupled tankBody physics object results in
	## strange positional offsets so we have to set it after we spawn...
	slot.occupant = game_level.spawner.spawn_unit(Vector2(0,0), true, self)
	slot.occupant.disabled = true
	slot.occupant.global_position = slot.global_position
	slot.physics_body.freeze = true

	# Assign to teams - only works correctly if there is 1 team or no teams
	# otherwise they will change teams mid-game
	var all_occupants:Array[TankController] = []
	for s in conveyor_slots:
		if is_instance_valid(s.occupant):
			all_occupants.push_back(s.occupant)
	game_level.spawner.assign_teams(all_occupants)

	popup_message("Assembled Unit", PopupNotification.PulsePresets.One)
	artillery_spawned.emit()
	return true

func check_turn() -> void:
	#if turn_counter in schedule:
	if schedule.has(turn_counter):
		for to_spawn in schedule[turn_counter]:
			print_debug("Trying spawn ", to_spawn+1, " of ", schedule[turn_counter])
			var did_spawn = await try_spawn_new_artillery()

func advance_conveyor() -> void:
	var slot = conveyor_slots.back().number
	while slot >= 0:
		print_debug("Advancing slot ", slot)
		if conveyor_slots[slot].is_occupied:
			if slot+1 < conveyor_slots.size():
				if conveyor_slots[slot+1].is_occupied:
					print_debug("Next slot is full, cancelling advance.")
					return
				var move_tween = create_tween()
				var next_position:Vector2 = conveyor_slots[slot+1].global_position
				#conveyor_slots[slot].occupant.global_position = next_position
				move_tween.tween_property(conveyor_slots[slot].occupant, "global_position", next_position, conveyor_move_duration).set_trans(Tween.TRANS_SPRING)
				#move_tween.tween_callback(_reassign_slots.bind(conveyor_slots[slot], conveyor_slots[slot+1]))
				move_tween.tween_callback(conveyor_advanced.emit)
				_reassign_slots(conveyor_slots[slot], conveyor_slots[slot+1])
			else:
				#End of the line
				activate_artillery(conveyor_slots[slot].occupant)
				conveyor_advanced.emit()
		else:
			# Empty slot
			pass
		slot -= 1
		continue

func activate_artillery(artillery:TankController) -> void:
	print_debug("Activating artillery ", artillery.name)
	game_level.activate_tank_controller(artillery) # Gives it turns
	set_deferred("artillery.tank.tankBody:freeze", false)

func _reassign_slots(from:ConveyorSlot, to:ConveyorSlot) -> void:
	if to.is_occupied:
		print_debug("Reassigning to full slot!")
	to.occupant = from.occupant
	from.occupant = null

func defeated() -> void:
	#End the round
	
	var explosion_instance:Explosion = explosion_scene.instantiate()
	explosion_instance.global_position = global_position
	get_parent().add_child(explosion_instance)
	#await explosion_instance.completed
	
	# Wait a tick for all rewards to compute
	await get_tree().process_frame
	%RoundDirector.end_round()

func _on_turn_ended(_tank:TankController) -> void:
	#turn_counter += 1
	set_deferred("turn_counter", turn_counter+1) # Maybe bugfix
	advance_conveyor()
	check_turn()

func _on_component_destroyed(component) -> void:
	damageable_components.erase(component)
	var remaining_components:int = damageable_components.size()
	popup_message("%s/%s Factory Parts Remaining" % [remaining_components, total_components])
	if damageable_components.is_empty():
		defeated()

class ConveyorSlot:
	var number:int
	var occupant:TankController
	var physics_body:TankBody:
		get:
			if is_occupied:
				return occupant.tank.tankBody
			else:
				return null
	var is_occupied:bool:
		get: return true if occupant else false
	var global_position:Vector2



#region Popup Notifications
func popup_message(message:String, pulses:Array = PopupNotification.PulsePresets.Three, lifetime:float = 3.0) -> PopupNotification:
	var popup = PopupNotification.constructor(message, pulses)
	if lifetime > 0.0: # Allows for default from the instance's export var
		popup.lifetime = lifetime

	add_child(popup)

	var offset = Vector2(0.0, 24.0) + (popups.size() * Vector2(0.0, 48.0)) # They stack

	# TODO place above tank if near bottom of screen (would be cut off)
	popup.global_position = global_position + offset
	var actual = get_global_transform_with_canvas().origin
	if actual.y + 96.0 > get_viewport().get_visible_rect().size.y:
		popup.global_position = global_position - offset*3

	popup.completed_lifetime.connect(_on_popup_completed_lifetime)

	popups.append(popup)
	return popup

func clear_all_popups() -> void:
	for popup:PopupNotification in popups:
		popup.fade_out()

# Popup stacking
func _on_popup_completed_lifetime(popup: PopupNotification) -> void:
	popups.erase(popup)
	#print_debug("Active popups: ", popups.size())
#endregion
