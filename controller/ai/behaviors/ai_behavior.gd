class_name AIBehavior extends Node

var behavior_type: Enums.AIBehaviorType

## Set default priority returned when no other conditions match for state selection
@export var default_priority: int = 1

@export var launch_collision_linear_threshold: float = 0.1
@export var min_collision_test_dist: float = 50

@export_range(0.0, 1.0, 0.01) var ceiling_velocity_threshold: float = 0.1

@export var weapon_scoring_strategies_container:Node

var track_shot_history: bool = false

class LaunchProperties:
	var speed: float
	var power_speed_mult: float = 1.0
	var mass: float = 1.0

class WeaponInfo:
	var weapon: Weapon
	var projectile_prototype: Node2D
	
	func delete() -> void:
		if projectile_prototype:
			projectile_prototype.queue_free()
			projectile_prototype = null

class OpponentTargetHistory:
	var opponent: TankController
	var my_position: Vector2
	var opp_position: Vector2
	var hit_location: Vector2 = Vector2.ZERO
	var fire_time: float
	var hit_time: float
	var hit_count: int # For multi-shot
	var power: float
	var max_power: float
	var angle: float

var tank: Tank

var has_player_fired: bool = false

# Dictionary of opponent to Array[OpponentTargetHistory]
var _opponent_target_history: Dictionary = {}
var last_opponent_history_entry: OpponentTargetHistory


func _ready() -> void:
	# Listen to track opponent targeting feedback and if player has fired
	GameEvents.projectile_fired.connect(_on_projectile_fired)

	if not weapon_scoring_strategies_container:
		weapon_scoring_strategies_container = self

var game_level: GameLevel:
	get: return SceneManager.get_current_level_root()
	

var aim_fulcrum_position: Vector2:
	get: return tank.turret.global_position
	
func execute(tank_unit: Tank) -> AIState:
	self.tank = tank_unit
	return null

func get_opponents() -> Array[TankController]:
	# Array.filter is broken!  See https://github.com/godotengine/godot/issues/72566
	#var opponents: Array[TankController] = []
#
	#var my_controller: TankController = tank.owner
	#for controller in game_level.round_director.tank_controllers:
		## Make sure we are not on the same team
		#if controller != my_controller and not my_controller.is_on_same_team_as(controller):
			#opponents.push_back(controller)
	#return opponents
	return TankController.get_opponents_of(tank.owner, game_level.round_director.tank_controllers)
	
#region Aim and LOS	

func get_power_for_target_and_angle(target: Vector2, angle: float, launch_props: LaunchProperties, forces: int = 0, hit_test: bool = true) -> float:
	# See https://en.wikipedia.org/wiki/Range_of_a_projectile
	var source: Vector2 = aim_fulcrum_position

	# If adjusting for walls then get the adjusted target
	var adjusted_target: Vector2 = get_target_end_walls(source, target, forces)

	# Adjusting target for max power if wind should be taken into account
	if forces & Forces.Wind:
		var orig_launch_speed := launch_props.speed
		launch_props.speed = tank.max_power * launch_props.power_speed_mult
		adjusted_target += _get_wind_offset(adjusted_target - source, launch_props)
		launch_props.speed = orig_launch_speed

	# Wolfram Alpha: Solve d = v * cos(theta) / g * (v * sin(theta) + sqrt(v ^ 2 * sin(theta)^2 + 2 * g * y)) for v
	# v = d * sqrt(g) / (sqrt(2 * d * sin(theta) + 2 * y * cos(theta)) * sqrt(cos(theta))

	# Y should be positive for targets below, since y increases going down this works out
	var y: float = adjusted_target.y - source.y
	var x: float = absf(adjusted_target.x - source.x)

	var g: float = PhysicsUtils.get_gravity_vector().y
	var angle_rads: float = deg_to_rad(angle)
	var sin_angle: float = sin(angle_rads)
	var cos_angle: float = cos(angle_rads)

	var sqrt_term: float = 2 * x * sin_angle + 2 * y * cos_angle
	if sqrt_term <= 0:
		print_debug("%s: Unreachable target=%s; angle=%f" % [tank.owner.name, target, angle])
		return -1

	var speed: float = x * sqrt(g) / (sqrt(sqrt_term) * sqrt(cos_angle))

	# If speed is greater than max power then angle is not viable
	var target_power = speed / launch_props.power_speed_mult

	print_debug("%s: target=%s; angle=%f; required power=%f - %s" % [tank.owner.name, target, angle, target_power, str(target_power <= tank.max_power)])

	if target_power > tank.max_power:
		return -1

	# Check if we will hit the ceiling, if it applies, at an unacceptable speed
	if will_hit_ceiling_at_unacceptable_speed(source, angle, speed, forces):
		return -1
	
	# Since the ascent is half of the total flight time, this means the linear phase accounts for about 5–15% of the total flight time.
	# vy = vo * sin(theta) - g * t
	# Determine initial ratio of y / x and then deviation threshold to solve for time when it is no longer linear
	# Once have the time the length of the hit test target is v * t
	# if cos_angle is 0 then ignore the test

	if not hit_test or is_zero_approx(cos_angle):
		return target_power
	
	# Check that it won't collide with something in front of us
	var aim_dir: Vector2 = Vector2(cos_angle, -sin_angle)
	
	var ratio: float = aim_dir.y / aim_dir.x
	var deviation_threshold: float = ratio * launch_collision_linear_threshold

	# y will increase toward zero on the upward trajectory
	# Use v = vo + a * t and split into x and y components. Since vx doesn't change, it cancels out
	# Want to solve for when vy decreases by 1 - deviation_threshold
	var time_to_linear: float = - deviation_threshold * speed * sin_angle / g
	var hit_test_dist: float = maxf(time_to_linear * speed, min_collision_test_dist)
	var hit_test_target: Vector2 = source + aim_dir * hit_test_dist

	var result: Dictionary = has_line_of_sight_to(source, hit_test_target)
	if result.test:
		return target_power
	
	print_debug("%s: target=%s; angle=%f; required power=%f; speed=%f; hit_test_dist=%f - HIT OBSTACLE at %s" % [tank.owner.name, target, angle, target_power, speed, hit_test_dist, result.position])
	return -1

func has_line_of_sight_to(start_pos: Vector2, end_pos: Vector2) -> Dictionary:
	var result: Dictionary = check_world_collision(start_pos, end_pos)

	if !result:
		print_debug("%s: start_pos=%s; end_pos=%s -> TRUE" % [tank.owner.name, str(start_pos), str(end_pos)])
		return {test = true}
	
	print_debug("%s: start_pos=%s; end_pos=%s -> FALSE - hit=%s -> %s"
		% [tank.owner.name, str(start_pos), str(end_pos), result.collider.name, str(result.position)])

	return {test = false, position = result.position}

func calculate_ceiling_reflection_target(start_pos: Vector2, end_pos: Vector2) -> Vector2:
	var ceiling_y: float = game_level.walls.ceiling_y
	var mirrored_target := Vector2(end_pos.x, 2.0 * ceiling_y - end_pos.y)
	var dir: Vector2 = mirrored_target - start_pos
	var t: float = (ceiling_y - start_pos.y) / dir.y
	return start_pos + dir * t

func check_world_collision(start_pos: Vector2, end_pos: Vector2) -> Dictionary:
	var space_state := tank.get_world_2d().direct_space_state

	var query_params := PhysicsRayQueryParameters2D.create(
		start_pos, end_pos,
		Collisions.CompositeMasks.obstacle)

	var result: Dictionary = space_state.intersect_ray(query_params)

	return result

func get_direct_aim_angle_to(opponent: TankController, launch_props: LaunchProperties, forces: int = 0) -> float:
	var aim_source_pos: Vector2 = aim_fulcrum_position

	# By default aim to the center of the opponent
	var opponent_position: Vector2 = get_target_end_walls(aim_source_pos, opponent.tank.tankBody.global_position, forces)

	var to_opponent: Vector2 = opponent_position - aim_source_pos
	var pos_offset: Vector2 = _get_active_forces_offset(to_opponent, launch_props, forces)
	
	var aim_target_pos: Vector2 = opponent_position + pos_offset

	return _get_direct_aim_angle_to(aim_source_pos, aim_target_pos)

func _get_direct_aim_angle_to(from_pos: Vector2, to_pos: Vector2) -> float:
	# Needs to be relative to turret neutral position which is up
	var up_vector: Vector2 = Vector2.UP.rotated(tank.tankBody.global_rotation)
	
	var dir := from_pos.direction_to(to_pos)
	var angle := up_vector.angle_to(dir)

	return clampf(rad_to_deg(angle), tank.min_angle, tank.max_angle)
	
func aim_angle_to_world_direction(angle: float) -> Vector2:
	var turret_angle: float = tank.turret.global_rotation
	var world_angle: float = turret_angle + rad_to_deg(angle)
	
	return Vector2.UP.rotated(rad_to_deg(world_angle))

func global_signed_angle_to_turret_angle(global_angle: float) -> float:
	return global_angle_to_turret_angle(absf(global_angle)) * signf(global_angle)

func global_angle_to_turret_angle(global_angle: float) -> float:
	return 90 - global_angle

func turret_angle_to_global_angle(turret_angle: float) -> float:
	return 90 - turret_angle

func has_direct_shot_to(opponent: TankController, launch_props: LaunchProperties, forces: int = 0) -> Dictionary:
	# Test from barrel to test points on artillery
	var aim_source_position: Vector2 = aim_fulcrum_position
	var opponent_position: Vector2 = get_target_end_walls(aim_source_position, opponent.tank.tankBody.global_position, forces)

	var up_vector: Vector2 = Vector2.UP.rotated(tank.tankBody.global_rotation)
	
	var opponent_tank: Tank = opponent.tank

	# Get local positions so can offset relative to the walls-adjusted opponent_position
	var test_positions: PackedVector2Array = opponent_tank.get_body_reference_points_local()

	var to_opponent: Vector2 = opponent_position - aim_source_position
	var pos_offset: Vector2 = _get_active_forces_offset(to_opponent, launch_props, forces)

	print_debug("%s: LOS opponent=%s; calculated pos_offset=%s -> %f" % [tank.owner.name, opponent.name, pos_offset, pos_offset.length()])

	for i in range(test_positions.size()):
		test_positions[i] += opponent_position + pos_offset
	
	# First check that we can even aim directly at the opponent and limit to those viable positions
	var viable_positions: PackedVector2Array = []
	var viable_angles: PackedFloat32Array = []

	for position in test_positions:
		var to_pos := aim_source_position.direction_to(position)
		var angle := rad_to_deg(up_vector.angle_to(to_pos))
		
		print_debug("%s: LOS opponent=%s; pos=%s; angle=%f" % [tank.owner.name, opponent.name, position, angle])

		if angle >= tank.min_angle and angle <= tank.max_angle:
			viable_positions.append(position)
			viable_angles.append(angle)
				
	var fire_position: Vector2 = tank.get_weapon_fire_locations().global_position

	var has_los: bool = false
	var max_position: Vector2 = fire_position
	var max_distance: float = 0.0
	var aim_position: Vector2 = Vector2.ZERO
	var aim_angle: float = 0.0
	
	for i in range(viable_positions.size()):
		var position: Vector2 = viable_positions[i]
		var line_of_sight_positions: PackedVector2Array = get_line_of_sight_positions(fire_position, position, forces)

		var result: Dictionary
		# line of sight positions are pairwise (0, 1), (1, 2), (2, 3), etc. starting with fire_position
		var los_passed: bool = true
		var j: int = 0
		while j < line_of_sight_positions.size() - 1:
			result = has_line_of_sight_to(line_of_sight_positions[j], line_of_sight_positions[j + 1])
			if !result.test:
				los_passed = false
				# Need to compute last result for the position
				j = line_of_sight_positions.size() - 2
			j += 1

		if los_passed:
			has_los = true
			aim_position = position
			aim_angle = viable_angles[i]
			break
		else:
			var dist := fire_position.distance_squared_to(result.position)
			if dist > max_distance:
				max_distance = dist
				max_position = result.position
	
	if has_los:
		print_debug("%s: LOS to opponent=%s -> TRUE; tested_positions=%d"
		 % [tank.owner.name, opponent.name, viable_positions.size()])
		return {test = true, position = aim_position, aim_angle = aim_angle, adjusted_opponent_position = opponent_position}
		
	print_debug("%s: LOS to opponent=%s -> FALSE -> %s; tested_positions=%d"
		% [tank.owner.name, opponent.name, str(max_position), viable_positions.size()])
	
	return {test = false, position = max_position, adjusted_opponent_position = opponent_position}

#endregion

#region Forces
class Forces:
	const Gravity: int = 1
	
	@warning_ignore("shadowed_global_identifier")
	const Wind: int = 1 << 1

	const Walls_Warp: int = 1 << 2
	const Walls_Elastic: int = 1 << 3

	@warning_ignore("shadowed_global_identifier")
	const Walls: int = Walls_Warp | Walls_Elastic
	const All: int = Gravity | Wind | Walls_Warp | Walls_Elastic
	
func _get_active_forces_offset(aim_trajectory: Vector2, launch_props: LaunchProperties, forces: int) -> Vector2:
	var total_offset: Vector2 = Vector2.ZERO
	
	if forces & Forces.Gravity:
		total_offset += _get_gravity_offset(aim_trajectory, launch_props)
	if forces & Forces.Wind:
		total_offset += _get_wind_offset(aim_trajectory, launch_props)
	
	return total_offset
	
func _get_gravity_offset(aim_trajectory: Vector2, launch_props: LaunchProperties) -> Vector2:
	return _get_force_accel_offset(aim_trajectory, launch_props.speed, PhysicsUtils.get_gravity_vector())

func _get_wind_offset(aim_trajectory: Vector2, launch_props: LaunchProperties) -> Vector2:
	if is_zero_approx(launch_props.speed) or is_zero_approx(launch_props.mass):
		return Vector2.ZERO
	
	var wind_force: Vector2 = _get_wind_force()
	if wind_force.is_zero_approx():
		return Vector2.ZERO
		
	# F = m * a
	var wind_accel: Vector2 = _get_wind_accel(wind_force, launch_props)

	return _get_force_accel_offset(aim_trajectory, launch_props.speed, wind_accel)
	
func _get_force_accel_offset(aim_trajectory: Vector2, launch_speed: float, acceleration: Vector2) -> Vector2:
	if is_zero_approx(launch_speed):
		return Vector2.ZERO

	var aim_trajectory_dir: Vector2 = aim_trajectory.normalized()

	var launch_velocity: Vector2 = aim_trajectory_dir * launch_speed
	if is_zero_approx(launch_velocity.x):
		return Vector2.ZERO
		
	# Calculate time from horizontal component
	# x = vx  * t
	var flight_time: float = aim_trajectory.x / launch_velocity.x
	
	# d = 1/2 * a * t^2 + voy * t
	var final_pos: Vector2 = 0.5 * acceleration * flight_time * flight_time + launch_velocity * flight_time
	
	# Determine how much additional pos we need to hit the final pos of the flight
	var additional_pos: Vector2 = aim_trajectory - final_pos
	return additional_pos
	
func _get_wind_force() -> Vector2:
	var wind: Wind = game_level.wind
	return wind.force if wind else Vector2.ZERO

func _get_wind_accel(wind_force: Vector2, launch_props: LaunchProperties) -> Vector2:
	# F = m * a
	var wind_accel: Vector2 = wind_force / launch_props.mass / 100
	return wind_accel
#endregion
	
#region Weapons
func get_weapon_infos() -> Array[WeaponInfo]:
	var weapon_infos: Array[WeaponInfo] = []
	
	for weapon in tank.weapons:
		var weapon_info: WeaponInfo = WeaponInfo.new()
		weapon_info.weapon = weapon
		
		var scene_to_spawn: PackedScene = weapon.scene_to_spawn
		if scene_to_spawn and scene_to_spawn.can_instantiate():
			weapon_info.projectile_prototype = scene_to_spawn.instantiate() as Node2D
			
		weapon_infos.push_back(weapon_info)
		
	return weapon_infos
	
func delete_weapon_infos(weapon_infos: Array[WeaponInfo]) -> void:
	for info in weapon_infos:
		info.delete()
	weapon_infos.clear()
#endregion

#region Miss tracking

func _target_is_player_and_has_not_fired(target: TankController) -> bool:
	return !has_player_fired and target is Player

func _on_projectile_fired(projectile: WeaponProjectile) -> void:
	if not projectile.max_damage > 0.0: return # Ignore trajectory previewer, flares, etc
	if projectile.owner_tank and projectile.owner_tank.owner is Player:
		print_debug("%s: Player has fired - %s" % [name, projectile.owner_tank.owner.name])
		has_player_fired = true

	if !track_shot_history or !tank or projectile.owner_tank != tank:
		return
	
	print_debug("AIBehavior(%s): Projectile Fired=%s" % [tank.owner.name, projectile.name])

	if !last_opponent_history_entry:
		print_debug("AIBehavior(%s): Ignoring blind fire shot for projectile=%s" % [tank.owner.name, projectile.name])
		return

	last_opponent_history_entry.fire_time = _get_current_time_seconds()
	# Need to bind the extra projectile argument to connect
	#projectile.completed_lifespan.connect(_on_projectile_destroyed.bind(projectile, last_opponent_history_entry))
	projectile.completed_lifespan.connect(_on_projectile_destroyed.bind(last_opponent_history_entry))

# Bind arguments are passed as an array
func _on_projectile_destroyed(projectile: WeaponProjectile, opponent_history_entry: OpponentTargetHistory) -> void:
	print_debug("AIBehavior(%s): Projectile Destroyed=%s" % [tank.owner.name, projectile.name])

	opponent_history_entry.hit_count += 1
	opponent_history_entry.hit_location += projectile.global_position
	opponent_history_entry.hit_time += _get_current_time_seconds()

#endregion

#region Walls

func should_wall_compensate(forces: int) -> bool:
	var walls: Walls = game_level.walls
	if !walls:
		return false
	match walls.wall_mode:
		Walls.WallType.WARP:
			return forces & Forces.Walls_Warp != 0
		Walls.WallType.ELASTIC, Walls.WallType.ACCELERATE, Walls.WallType.STICKY:
			return forces & Forces.Walls_Elastic != 0
	return false

func get_target_end_walls(start_pos: Vector2, end_pos: Vector2, forces: int) -> Vector2:
	return get_shortest_path_walls(start_pos, end_pos).end if should_wall_compensate(forces) else end_pos

func get_shortest_path_walls(start_pos: Vector2, end_pos: Vector2) -> Dictionary:
	# return all points along the path
	# TODO: May break this out into a separate class
	# TODO: May want to pass in velocities too as these are affected by the elastic mode and may need to loop through certain simulations
	# To get the full result
	# for example for warp you may get 4 results - start -> right wall -> left wall -> end
	# for elastic you may get 4 results - start -> right_wall -> bounce -> end
	# for none you may get 2 results - start -> end
	# TODO: We should calculate this just once and store on this AIBehavior
	# For being determine los and collisions, need to return the intermediate test points when there are walls
	var results: Dictionary = {
		use_walls = false,
		end = end_pos
	}

	var walls: Walls = game_level.walls
	if not walls or walls.wall_mode == Walls.WallType.NONE:
		return results

	match walls.wall_mode:
		Walls.WallType.WARP:
			get_shorted_path_warp_walls(start_pos, end_pos, results)

	# Need to handle elastic walls in a different way since it doesn't affect the target position
	return results

func get_shorted_path_warp_walls(start_pos: Vector2, end_pos: Vector2, results: Dictionary) -> void:
	# Compare distance squared direct to target and distance squared using walls
	var direction: Vector2 = end_pos - start_pos
	var direct_distance: float = absf(direction.x)

	# Determine direction and need to flip if using walls
	# We will assume they aren't there and just extend the x distance
	var dir_sign: float = signf(direction.x)
	var wall_x_positions: PackedFloat32Array = []

	var walls: Walls = game_level.walls

	if dir_sign > 0: # Aiming to right want to check left
		wall_x_positions.push_back(walls.min_extent.x)
		wall_x_positions.push_back(walls.max_extent.x)
	else: # Aiming to left
		wall_x_positions.push_back(walls.max_extent.x)
		wall_x_positions.push_back(walls.min_extent.x)

	var adjusted_end_pos: float = (wall_x_positions[0] - start_pos.x) + (end_pos.x - wall_x_positions[1])
	var wall_distance: float = absf(adjusted_end_pos - start_pos.x)

	if wall_distance < direct_distance:
		results.use_walls = true
		results.end = Vector2(start_pos.x + adjusted_end_pos, end_pos.y)
		results.wall_x_positions = wall_x_positions
	else:
		results.end = end_pos

func get_line_of_sight_positions(start_pos: Vector2, end_pos: Vector2, forces: int) -> PackedVector2Array:
	var results: PackedVector2Array = []
	if !should_wall_compensate(forces):
		results.push_back(start_pos)
		results.push_back(end_pos)
		return results

	var wall_results: Dictionary = get_shortest_path_walls(start_pos, end_pos)
	if !wall_results.use_walls:
		results.push_back(start_pos)
		results.push_back(end_pos)
		return results

	# Need to interpolate the y between the walls
	var wall_x_positions: PackedFloat32Array = wall_results.wall_x_positions
	var adjusted_end_pos: Vector2 = wall_results.end

	var total_distance: float = absf(adjusted_end_pos.x - start_pos.x)
	var accum_distance: float = 0.0

	results.push_back(start_pos)
	accum_distance += absf(wall_x_positions[0] - start_pos.x)
	var first_wall: Vector2 = Vector2(wall_x_positions[0], lerpf(start_pos.y, adjusted_end_pos.y, accum_distance / total_distance))
	results.push_back(first_wall)

	if wall_x_positions.size() > 1: # Warp
		results.push_back(Vector2(wall_x_positions[1], first_wall.y))

	results.push_back(end_pos)
	return results

func get_sorted_angles_by_wall_type(angles: Array[float]) -> Array[float]:
	# Sort angles by wall type
	var walls: Walls = game_level.walls
	
	match walls.wall_mode:
		Walls.WallType.ELASTIC, Walls.WallType.STICKY, Walls.WallType.ACCELERATE:
			# Prefer lower trajectories
			angles = angles.duplicate()
			angles.sort()
	
	return angles

func will_hit_ceiling_at_unacceptable_speed(start_pos: Vector2, angle: float, speed: float, forces:int) -> bool:
	# Only applies for elastic-like walls
	var walls: Walls = game_level.walls
	if not walls or not walls.is_elastic_variety or not should_wall_compensate(forces):
		return false

	# If the angle is too high then it will hit the ceiling
	var ceiling_y: float = game_level.walls.ceiling_y
	# Starting above the ceiling so immediately return true
	if ceiling_y >= start_pos.y:
		print_debug("%s: Hits ceiling from start - start_pos=%s; ceiling_y=%f" % [tank.owner.name, str(start_pos), ceiling_y ])
		return true

	var angle_rads: float = deg_to_rad(angle)
	var sin_angle: float = sin(angle_rads)
	var g: float = PhysicsUtils.get_gravity_vector().y

	# vy^2 = (Vo*sin(theta))^2 - 2 * g * dy
	# y increases going down so subtract ceiling y from start pos y for a positive result
	var dy:float = start_pos.y - ceiling_y
	var initial_speed_y:float = speed * sin_angle

	var speed_squared: float = initial_speed_y * initial_speed_y - 2 * g * dy
	if speed_squared <= 0:
		# Not enough velocity to hit the ceiling
		return false
	
	# See if final y speed exceeds threshold
	var speed_threshold:float = initial_speed_y * ceiling_velocity_threshold
	var speed_threshold_squared:float = speed_threshold * speed_threshold

	var hits_ceiling:bool = speed_squared >= speed_threshold_squared

	if OS.is_debug_build():
		print_debug("%s: Hits ceiling at unacceptable speed - %s - start_pos=%s; angle=%f; speed=%f; initial_y_speed=%f; final_y_speed=%f" \
			% [name, str(hits_ceiling), str(start_pos), angle, speed, initial_speed_y, sqrt(speed_squared)])
	return hits_ceiling

#endregion

#region Opponent History
func _add_opponent_target_entry(opponent_data: Dictionary) -> OpponentTargetHistory:
	if !track_shot_history or !opponent_data.get("direct", false):
		return null
	
	var opponent: TankController = opponent_data.opponent
	var power: float = opponent_data.power
	var max_power: float = tank.max_power
	var angle: float = opponent_data.angle

	var opponent_target_history = _opponent_target_history.get_or_add(opponent.get_instance_id(), [])

	var target_data = OpponentTargetHistory.new()
	target_data.opponent = opponent
	target_data.my_position = aim_fulcrum_position
	target_data.opp_position = opponent.tank.global_position
	target_data.power = power
	target_data.angle = angle
	target_data.max_power = max_power

	last_opponent_history_entry = target_data
	opponent_target_history.append(target_data)

	return target_data

func get_opponent_target_history(opponent: TankController) -> Array:
	return _opponent_target_history.get(opponent.get_instance_id(), [])
	
#endregion

#region Utils

func _get_current_time_seconds() -> float:
	return game_level.game_timer.time_seconds

# TODO: This should be a helper on the game level and take into account walls
func _get_playable_x_extent() -> float:
	return get_viewport().get_visible_rect().size.x

#endregion

#region Weapon Selection

func select_best_weapon(opponent_data: Dictionary, weapon_infos: Array[AIBehavior.WeaponInfo]) -> int:
	# If only have one weapon then immediately return
	if tank.weapons.is_empty():
		push_warning("%s(%s): No weapons available! - returning 0" % [name, tank.owner.name])
		# Return 0 instead of -1 in case issue resolves itself by the time we try to shoot
		return 0
	if tank.weapons.size() == 1:
		print_debug("%s(%s): Only 1 weapon available - returning 0" % [name, tank.owner.name])
		return 0
	
	var target_distance: float

	# We are going to hit something other than opponent tank first
	if opponent_data.has("hit_position"):
		target_distance = tank.global_position.distance_to(opponent_data.hit_position)
	else:
		target_distance = tank.global_position.distance_to(opponent_data.adjusted_position)

	# Select most powerful available weapon that won't cause self-damage
	var player_has_not_fired:bool = _target_is_player_and_has_not_fired(opponent_data.opponent)
	var best_weapon:int = -1

	# Find the best weapon unless shooting at player and they haven't shot in which case we want the worst weapon
	var best_score:float
	var comparison_result: int

	if player_has_not_fired:
		best_score = 1e9
		comparison_result = -1
	else:
		best_score = 0.0
		comparison_result = 1

	# Determine strategy to use for each weapon based on registered handlers
	# If two handlers match then the latest one is used
	# We can order the siblings nodes such that the "highest priority" one comes last
	var weapon_handlers:Dictionary[Weapon, WeaponScorer]
	for weapon_info in weapon_infos:
		for weapon_scorer in weapon_scoring_strategies_container.get_children():
			if weapon_scorer is WeaponScorer and weapon_scorer.handles_weapon(weapon_info.weapon, weapon_info.projectile_prototype):
				weapon_handlers[weapon_info.weapon] = weapon_scorer

	var all_opponents := get_opponents()

	for i in range(weapon_infos.size()):
		var weapon_info: AIBehavior.WeaponInfo = weapon_infos[i]
		var weapon: Weapon = weapon_info.weapon
		var projectile: Node2D = weapon_info.projectile_prototype
		
		var weapon_scorer:WeaponScorer = weapon_handlers.get(weapon)
		if weapon_scorer:
			var score: float = weapon_scorer.compute_score(tank, weapon, projectile, target_distance, all_opponents, comparison_result)
			print_debug("%s(%s): weapon(%d)=%s; score=%f" % [name, tank.owner.name, i, weapon.name, score])
			if int(signf(score - best_score)) == comparison_result:
				best_score = score
				best_weapon = i
		else:
			push_warning("%s(%s): weapon(%d)=%s did not match a handler and will be ignored" % [name, tank.owner.name,i, weapon.name])

	var chosen_weapon_index:int

	if best_weapon != -1:
		print_debug("%s(%s): selected best_weapon=%d/%d; score=%f" % [name, tank.owner.name, best_weapon, weapon_infos.size(), best_score])
		chosen_weapon_index = best_weapon
	else:
		# Fallback to random weapon
		print_debug("%s(%s): Could not find viable weapon - falling back to random selection out of %d candidates" % [name, tank.owner.name, tank.weapons.size()])
		chosen_weapon_index = randi_range(0, tank.weapons.size() - 1)

	# Notify the scorers that weapon was chosen
	var chosen_info:WeaponInfo = weapon_infos[chosen_weapon_index]
	var chosen_weapon_scorer:WeaponScorer = weapon_handlers.get(chosen_info.weapon)
	if chosen_weapon_scorer:
		chosen_weapon_scorer.on_chosen(chosen_info.weapon, chosen_info.projectile_prototype)

	return chosen_weapon_index
#endregion
