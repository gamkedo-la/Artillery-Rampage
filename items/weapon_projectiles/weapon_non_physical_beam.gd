class_name WeaponNonPhysicalBeam extends Node2D
## An alternative to WeaponProjectile for weapons with non-physical bodies

signal completed_lifespan ## Tracked by Weapon class

@onready var laser_start = $LaserStart
@onready var laser_end = $LaserEnd

## Self destroys once this time has passed.[br]
## When [member kill_after_turns_elapsed] is used, this time emits [signal completed_lifespan].
@export var max_lifetime: float = 10.0
## Indicate whether this projectile should destroy itself after an interaction.
## See [method disarm] and [method arm] to change the state at runtime.
@export var should_explode_on_impact:bool = false

@export var max_falloff_distance: float = 60:
	get: return max_falloff_distance*falloff_distance_multiplier
@export var falloff_distance_multiplier: float = 1.0 # ModProjectile

@export_category("Destructible")
@export var destructible_scale_multiplier:Vector2 = Vector2(2.0 , 2.0):
	get: return destructible_scale_multiplier*destructible_scale_multiplier_scalar
@export var destructible_scale_multiplier_scalar:float = 1.0 # ModProjectile

var owner_tank: Tank;
var source_weapon: Weapon ## The weapon we came from
var destructible_component:CollisionPolygon2D

## How far the beam can travel per second
var speed: float = 800.0

## The angle of the barrel firing the beam. This will be used to determine the trajectory of the beam.
var aim_angle: float

var can_travel = true
var time_since_last_hit = 0
var time_to_wait_between_hits = 0.0075

func _ready() -> void:
	if has_node('Destructible'):
		destructible_component = get_node('Destructible')
	if max_lifetime > 0.0: destroy_after_lifetime()

func set_sources(tank:Tank, weapon:Weapon) -> void:
	owner_tank = tank
	source_weapon = weapon

func _calculate_damage(target: Node2D) -> float:
	return 50

func destroy():
	completed_lifespan.emit()
	queue_free()

func destroy_after_lifetime(lifetime:float = max_lifetime) -> void:
	var timer = Timer.new()
	add_child(timer)
	timer.timeout.connect(destroy)
	timer.start(lifetime)

func _process(delta):
	# Only move laser_start at the end of the beam's lifetime
	#var laser_start_velocity = laser_end_velocity / 100
	#laser_start.position += laser_start_velocity.rotated(aim_angle)
	if can_travel:
		var laser_end_velocity = Vector2(speed * delta, 0.0)
		laser_end.position += laser_end_velocity.rotated(aim_angle)
		see_if_beam_collides_with_anything()
		$BeamSprite.global_rotation = aim_angle + deg_to_rad(90)
		$BeamSprite.position =  (laser_end.position + laser_start.position) / 2
		$BeamSprite.scale.y = laser_end.position.length() - laser_start.position.length()
	else:
		time_since_last_hit += delta
		if time_since_last_hit >= time_to_wait_between_hits:
			can_travel = true

func see_if_beam_collides_with_anything():
	var space_state = get_world_2d().direct_space_state
	var query_params := PhysicsRayQueryParameters2D.create(
		global_position, laser_end.global_position,
		 Collisions.CompositeMasks.damageable)
	query_params.exclude = [self]
	var result: Dictionary = space_state.intersect_ray(query_params)
	if result.size() > 0:
		laser_end.global_position = result.position
		explode()
		can_travel = false
		time_since_last_hit = 0

func get_destructible_component() -> CollisionPolygon2D:
	return destructible_component

## Runs damage logic and explodes if an interaction occurs
func explode(collided_body: PhysicsBody2D = null, force:bool = false):
	# Need to do a sweep to see all the things we have influenced
	# Need to be sure not to "double-damage" things both from influence and from direct hit 
	# The body here is the direct hit body that will trigger the projectile to explode if an interaction happens
	#if not run_collision_logic:
		#return
	#if calculated_hit:
		#return
	
	var had_interaction:bool = false if not force else true
	if is_instance_valid(collided_body) and collided_body.get_collision_layer_value(10): # ProjectileBlocker (shield, etc) hack
		# FIXME if not inside_of_players_shield...:
		had_interaction = true
	var affected_nodes = _find_interaction_overlaps()
	
	#region Node Group Determination

	var processed_nodes_set: Dictionary[Node, bool] = {}
	var damaged_processed_map: Dictionary[Node, float] = {}
	var destructed_processed_map: Dictionary[Node, Vector2] = {}

	for node in affected_nodes:
		# See if this node is a "Damageable" or a "Destructable"
		# Damageable:
		var root_node: Node = Groups.get_parent_in_group(node, Groups.Damageable)
		if root_node:
			var damage_amount = _calculate_damage(node)
			if damage_amount > 0:
				had_interaction = true
				damaged_processed_map[root_node] = maxf(damage_amount, damaged_processed_map.get(root_node, 0.0))
				processed_nodes_set[root_node] = true
				
		# Destructible:
		# -Some projectiles don't have a destructible node and don't damage the terrain or other shatterable things.
		if destructible_component:
			root_node = Groups.get_parent_in_group(node, Groups.Destructible)
			if root_node and root_node not in destructed_processed_map:
				_on_destructible_component_interaction(destructible_component, root_node)
				var contact_point: Vector2 = laser_end.position

				had_interaction = true
				destructed_processed_map[root_node] = contact_point
				processed_nodes_set[root_node] = true
	#endregion

	#region Events and Damage Dispatch

	# Process events for destructible components and combine for those that are the same
	# Process damage at end as took max damage if there were multiple colliders on single damageable root node
	# Also process destructible components at end as some may also be damageable and want to emit a single global event

	var instigator := get_instigator()

	for node in processed_nodes_set:
		# Default damage to 0 if this is only a destructible node and not also damageable
		var damage_amount:float = damaged_processed_map.get(node, 0.0)
		# Default to global_position for contact point if this is just a damageable node
		var contact_point:Vector2 = destructed_processed_map.get(node, global_position)

		if node.is_in_group(Groups.Destructible):
			damage_destructible_node(node, instigator, self, contact_point, destructible_scale_multiplier)
		if node.is_in_group(Groups.Damageable):
			damage_damageable_node(node, instigator, self, damage_amount)

		GameEvents.took_damage.emit(node, instigator, self, contact_point, damage_amount)
	
	#endregion

	# Explode
	if had_interaction and should_explode_on_impact: 
		destroy()

## For use with a Damageable group nodes only.
## This method exists to be overridden by classes extending [WeaponProjectile], as a hook.
func damage_damageable_node(
	damageable:Node, instigator:Node, projectile:WeaponNonPhysicalBeam,
	damage_amount:float
	) -> void:
	
	damageable.take_damage(instigator, projectile, damage_amount)
	
## For use with a Destructible group nodes only.
## This method exists to be overridden by classes extending [WeaponProjectile], as a hook.
@warning_ignore("unused_parameter")
func damage_destructible_node(
	destructible:Node, instigator:Node, projectile:WeaponNonPhysicalBeam,
	contact_point:Vector2, destructible_scale_multiplier:Vector2
	) -> void:
	
	var container = WeaponBeamPhysicsContainer.new(self)
	destructible.damage(container, contact_point, destructible_scale_multiplier)

func get_instigator() -> Node2D:
	return owner_tank.get_parent() as Node2D if is_instance_valid(owner_tank) else null

## Override to return laser transform
func _get_collision_transform() -> Transform2D:
	return Transform2D(0, laser_end.global_position)

func _find_interaction_overlaps() -> Array[Node2D]:
	var space_state = get_world_2d().direct_space_state
	
	# TODO: Maybe this belongs in Collisions auto-load
	var params = PhysicsShapeQueryParameters2D.new()
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.collision_mask = Collisions.CompositeMasks.damageable
	params.margin = Collisions.default_collision_margin
	params.transform = _get_collision_transform()
	params.exclude = [self]
	
	# More optimized shape creation for interfacing with the physics server
	# Given a handle (rid) that needs to be freed when done
	var shape_rid = PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape_rid, max_falloff_distance)
	params.shape_rid = shape_rid
	
	# Note that each contact point is reported so for a large radius you may end up selecting the same collider multiple times
	# Unfortunately no way to remove contact point info so we need to increase the max results (esp. for the mega nuke) and then 
	# only append the unique colliders
	var results: Array[Dictionary] = space_state.intersect_shape(params, Collisions.weapon_sweep_result_count)

	var collision_results: Array[Node2D] = []

	print("WeaponProjectile(" + name + "): Found " + str(results.size()) + " overlaps with projectile")
	for result:Dictionary in results:
		var collider = result["collider"] as Node2D
		if(!is_instance_valid(collider)):
			push_warning("WeaponProjectile(" + name + " damage overlapped with non-Node2D" +  result["collider"].name)
			continue
		if not collider in collision_results:
			print("WeaponProjectile(" + name + " damage overlapped with " + collider.name)
			collision_results.append(collider)

	# Release the shape when done with physics queries.
	PhysicsServer2D.free_rid(shape_rid)
	
	return collision_results

## Override to change the destructible position to laser end position
func _on_destructible_component_interaction(in_destructible_component: CollisionPolygon2D, destructible_node:Node) -> void:
	in_destructible_component.position = laser_end.position
