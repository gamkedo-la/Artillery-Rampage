class_name WeaponProjectile extends RigidBody2D

#TODO: We might not need the Overlap if we only have the weapon projectile interact with Area2D's and not other physics bodies

enum DamageFalloffType
{
	Constant,
	Linear,
	InverseSquare
}

class CollisionResult:
	var game_time_seconds:float
	var global_position: Vector2
	var collider: Node2D

signal completed_lifespan ## Tracked by Weapon class


# The idea here is that we are using RigidBody2D for the physics behavior
# and the Area2D as the overlap detection for detecting hits

@export var color: Color = Color.BLACK

@export var max_lifetime: float = 10.0 ## Self destroys once this time has passed.
@export var explosion_to_spawn:PackedScene

@export_category("Damage")
@export var damage_falloff_type: DamageFalloffType = DamageFalloffType.Linear

@export_category("Damage")
@export var min_falloff_distance: float = 10

@export_category("Damage")
@export var max_falloff_distance: float = 60

@export_category("Damage")
@export var min_damage: float = 10

@export_category("Damage")
@export var max_damage: float = 100

#@export_category("Damage")
#@export var last_collider_time_tolerance: float = 0.1

@export_category("Destructible")
@export var destructible_scale_multiplier:Vector2 = Vector2(10 , 10)

## Indicate whether need to explode on impact with supported collision layers and cause damage
## This replaces the "Overlap" concept
@export_category("Destructible")
@export var should_explode_on_impact:bool = true

var calculated_hit: bool
var owner_tank: Tank;
var source_weapon: Weapon # The weapon we came from
var firing_container

# TODO: We can probably combine this with above should_explode_on_impact
# Removed the Overlap concept as can handle the overlap interaction through the rigid body
# This also allows us to use continuous collision detection to fix the tunneling problem we see with projectiles going through the terrain
var can_explode:bool = true # used by MIRV

#func set_spawn_parameters(in_owner_tank: Tank, power:float, angle:float):
	#self.owner_tank = in_owner_tank
	#linear_velocity = Vector2.from_angle(angle) * power * power_velocity_mult
	
var last_collision:CollisionResult
# Avoid problems with game pauses as _integrate_forces is called
# before on_body_entered and we only need to read the result then
var current_collision:CollisionResult

func _ready() -> void:
	if should_explode_on_impact:
		connect("body_entered", on_body_entered)
	modulate = color
	if max_lifetime > 0.0: destroy_after_lifetime()
	GameEvents.emit_projectile_fired(self)
	
func set_sources(tank:Tank,weapon:Weapon) -> void:
	owner_tank = tank
	source_weapon = weapon
	if explosion_to_spawn:
		firing_container = SceneManager.get_current_level_root() if not null else get_tree().current_scene
		if firing_container.has_method("get_container"):
			firing_container = firing_container.get_container()

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	# Store any collision results for later access
	if state.get_contact_count() >= 1:
		# It says "local position" in function name but the docs say it is global position
		# and this agrees with empirical results
		var pos: Vector2 = state.get_contact_local_position(0)
		current_collision = CollisionResult.new()
		# TODO: This will not work with pause
		# Time.get_ticks_msec is not like Unreal's UWorld::GetTimeSeconds that
		# tracks actual game time when the game isn't paused and responds to time dilation
		# To do this we can create a singleton that keeps track of game time and tracks pause state to
		# subtract out those intervals
		current_collision.game_time_seconds = Time.get_ticks_msec() / 1000.0
		current_collision.global_position = pos
		current_collision.collider = state.get_contact_collider_object(0) as Node2D

		last_collision = current_collision
	else:
		current_collision = null

func on_body_entered(_body: Node2D):
	# Need to do a sweep to see all the things we have influenced
	# Need to be sure not to "double-damage" things both from influence and from direct hit
	# The body here is the direct hit body that will trigger the projectile to explode if an interaction happens
	if not can_explode:
		return
	if calculated_hit:
		return
	var affected_nodes = _find_interaction_overlaps()
	var had_interaction:bool = false
	
	var processed_set: Dictionary = {}
	
	for node in affected_nodes:
		# See if this node is a "Damageable" or a "Destructable"
		var root_node = get_parent_in_group(node, Groups.Damageable)
		if root_node:
			if root_node in processed_set:
				continue
			var damage_amount = _calculate_damage(node)
			if damage_amount > 0:
				root_node.take_damage(owner_tank, self, damage_amount)
				had_interaction = true
		# Some projectiles don't have a destructible node, e.g. MIRV
		if $Destructible:
			root_node = get_parent_in_group(node, Groups.Destructible)
			if root_node:
				if root_node in processed_set:
					continue
				center_destructible_on_impact_point($Destructible)
				root_node.damage($Destructible, destructible_scale_multiplier)
				had_interaction = true
		processed_set[root_node] = root_node
	# end for
	
	# FIXME: Technically shouldn't do this and should set to true and also always call destroy but MIRV doesn't work correctly without it
	calculated_hit = not affected_nodes.is_empty()

	# Always explode on impact
	#if had_interaction:
	if calculated_hit:
		destroy()
		
func center_destructible_on_impact_point(destructible: CollisionPolygon2D) -> void:
	var destructible_polygon: PackedVector2Array = destructible.polygon
	# Get velocity vector direction to determine translation direction
	var movement_dir : Vector2 = linear_velocity.normalized()
	var circle : Circle = Circle.create_from_points(destructible_polygon)
	
	var contact_point: Vector2 = _determine_contact_point(movement_dir, circle.radius)
	
	var translation_radius: float = circle.radius * destructible_scale_multiplier.length()
	var translation: Vector2 = contact_point - global_position + translation_radius * movement_dir
	
	for i in range(destructible_polygon.size()):
		destructible_polygon[i] += translation

func get_parent_in_group(node: Node, group: String) -> Node:
	if node.is_in_group(group):
		return node
	if node.get_parent() == null:
		return null
	return get_parent_in_group(node.get_parent(), group)

func destroy():
	#GameEvents.emit_turn_ended(owner_tank.owner) ## Moved to Weapon class.
	if explosion_to_spawn:
		spawn_explosion(explosion_to_spawn)
		
	completed_lifespan.emit()
	queue_free()
	
func destroy_after_lifetime(lifetime:float = max_lifetime) -> void:
	var timer = Timer.new()
	add_child(timer)
	timer.timeout.connect(destroy)
	timer.start(lifetime)
	
func spawn_explosion(scene:PackedScene) -> void:
	var instance
	if scene.can_instantiate():
		instance = scene.instantiate()
		instance.global_position = global_position
		firing_container.add_child(instance)

func _determine_contact_point(movement_dir: Vector2, radius: float) -> Vector2:
	var space_state = get_world_2d().direct_space_state

	var extent: Vector2 = movement_dir * radius * 2.0

	var query_params := PhysicsRayQueryParameters2D.create(
		global_position - extent, global_position + extent,
		 Collisions.CompositeMasks.damageable)
		
	query_params.exclude = [self]
	
	var result: Dictionary = space_state.intersect_ray(query_params)
	if !result:
		push_warning("WeaponProjectile(%s): No contact point found for projectile - returning default position=%s" % [name, global_position])
		return global_position
	return result["position"]

func _find_interaction_overlaps() -> Array[Node2D]:
	var space_state = get_world_2d().direct_space_state
	
	# TODO: Maybe this belongs in Collisions auto-load
	var params = PhysicsShapeQueryParameters2D.new()
	params.collide_with_areas = true
	params.collide_with_bodies = true
	params.collision_mask = Collisions.CompositeMasks.damageable
	params.margin = Collisions.default_collision_margin
	params.transform = Transform2D(0, global_position)
	params.exclude = [self]
	
	# More optimized shape creation for interfacing with the physics server
	# Given a handle (rid) that needs to be freed when done
	var shape_rid = PhysicsServer2D.circle_shape_create()
	PhysicsServer2D.shape_set_data(shape_rid, max_falloff_distance)
	params.shape_rid = shape_rid
	
	var results: Array[Dictionary] = space_state.intersect_shape(params)

	var collision_results: Array[Node2D] = []

	print("WeaponProjectile(" + name + "): Found " + str(results.size()) + " overlaps with projectile")
	for result:Dictionary in results:
		var collider = result["collider"] as Node2D
		if(!is_instance_valid(collider)):
			push_warning("WeaponProjectile(" + name + " damage overlapped with non-Node2D" +  result["collider"].name)
			continue
		print("WeaponProjectile(" + name + " damage overlapped with " + collider.name)
		collision_results.append(collider)

	# Release the shape when done with physics queries.
	PhysicsServer2D.free_rid(shape_rid)
	
	return collision_results

func _calculate_damage(target: Node2D) -> float:
	return _calculate_point_damage(_get_node_impact_position(target))

func _get_impact_point() -> Vector2:
	if _is_last_collision_relevant():
		return last_collision.global_position
	return global_position

func _get_node_impact_position(node: Node2D) -> Vector2:
	if _is_last_collision_relevant() and last_collision.collider == node:
		return last_collision.global_position
	return node.global_position

func _is_last_collision_relevant() -> bool:
	return is_instance_valid(last_collision)
	#return last_collision and \
	#	Time.get_ticks_msec() / 1000.0 - last_collision.game_time_seconds <= last_collider_time_tolerance

func _calculate_point_damage(pos: Vector2) -> float:
	var impact_point:Vector2 = _get_impact_point()

	var dist = (pos - impact_point).length()
	if dist >= max_falloff_distance:
		return 0.0
	if dist <= min_falloff_distance:
		return max_damage
	
	match damage_falloff_type:
		DamageFalloffType.Constant:
			return max_damage
		DamageFalloffType.Linear:
			return _calculate_dist_frac(dist) * max_damage
		DamageFalloffType.InverseSquare:
			var falloff = _calculate_dist_frac(dist)
			return falloff * falloff * max_damage
		_:
			push_error("Unrecognized damage type: " + str(damage_falloff_type))
			return max_damage
			
func _calculate_dist_frac(dist: float):
	return  (1.0 - (dist - min_falloff_distance) / (max_falloff_distance - min_falloff_distance))	
