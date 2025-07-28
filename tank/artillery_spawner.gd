class_name ArtillerySpawner extends Node2D

@export var artillery_ai_types: Array[PackedScene] = []
@export var artillery_ai_starting_weapons: Array[PackedScene] ## These must be of class Weapon
@export var artillery_ai_starting_weapon_count:Vector2i = Vector2i()
#@export var artillery_ai_upgrade_weapons: Array[PackedScene] # Could go this route
@export var default_ai_players: Vector2i = Vector2i()
## Specify min and max team size. If < 1 then no teams will be assigned
@export var num_ai_teams: int = 0
@export var group_teams_together:bool = true

@export var default_human_players: Vector2i = Vector2i()

@export_range(-100, 100) var spawn_y_offset: float = -10.0
@export_range(20, 250) var ideal_min_spawn_separation: float = 100.0
@export_range(0.2, 1.0, 0.01) var spawn_test_bounds_delta: float = 0.5
## max slant that a unit should be able to spawn on
@export_range(0, 90, 1.0) var max_slant_angle_deg: float = 5.0

@export_range(0, 1e9, 1, "or_greater")
var min_boundary_x_distance: float = 40

## Saturation and value for the AI color.
@export var ai_color_sv: Color = Color.from_hsv(0.0, 0.9, 1.0)

## Ranges to draw from for the AI color hue.
## Goal is to avoid random colors from being too similar
@export var ai_colors:Array[Color]

const player_type : PackedScene = preload("res://controller/player/player.tscn")

const SENTINEL_VECTOR: Vector2 = Vector2(-1e10, -1e10)
const SENTINEL_ANGLE = 1e9

# Need to wait for the terrain to finish building before doing raycasts
const spawn_delay:float = 0.2
const default_spawn_test_size: float = 20.0

var _specified_positions: Array[Marker2D] = []
var _all_positions: Array[Vector2] = []
var _used_positions: Array[Vector2] = []
var _placed_positions: Array[Vector2] = []
var _spawn_test_size: float = default_spawn_test_size
var _ai_hue_index:int

var enemy_names: Array[String] = [
	"Blasty", "Leadhead", "Loose Cannon", "Bombs-a-lot", "Stand Still", "The Arcster",
	"Deadeye", "Bingo", "Kablewy", "Inferno", "Silo", "Big Guns", "Steady Aim",
	"Lobster", "Scrapheap", "General Malfunction", "Big Clank", "Shellraiser",
	"Armorgeddon", "Rico Shay", "Tankerbell", "No Roll Model", "Tank Sinatra",
	"Barrel Streep", "Tanky Winky", "Tankenstein", "Solid Tank", "Jack & Flakster",
	"Sly Boomer", "Twisted Metal", "Splinter Shell", "Howit Sir", "Longlob",
	"Arc Nemesis", "The Lobfather", "The Soprammos", "Aims Bond", "Better Call Cannonball",
	"Stranger Plinks", "The Lobbit", "Ms L Guidance", "Indy Wreckage", "Bunker Buster Keaton",
	"Splash Damage", "General Radius", "Volley Parton", "Aiming Byhouse", "Betty Boom",
	"Sabrina Sharpshooter", "Julie Aim Roberts", "Mortaricia", "Billie Dieless",
	"Tremor Maker", "Havoc", "Ruiner", "Scorcher", "Striker", "Powderkeg", "Boomstick",
	"Blasteroid", "Brave Little Turret", "Missfire", "Shockwave", "Old Boomer",
	"Plink Panther", "Buster Rhimes", "Crapshot", "Thomas", "Forge Clooney",
	"Dedre Lode", "Blaster Chief", "KiloNuke Dukem", "Spare Parts", "Luna Tick",
	"Grateful Lead", "Ratcheting Crank", "Gigadeath", "Blammstein", "Leadfinger",
	"Nuke Skylobber", "Trinity", "Liquid Flank", "Tank Rampage", "Montbombery",
	"HomingTeam", "Lobber Breaker", "Boolint Floatstring", "Kaboomerang", "Broomhilda",
	"Boomer Simpson",  "Count Flakula", "Napalma Anderson", "Blammo Baggins",
	"Mad Muzzle", "Boom Hower", "Recoil Kid", "Flintboom", "Boom Chakalaka", "Crater Tot",
	"Missle Dontfire", "Muzzle Crow", "Minestrong", "Fuse Willis", "Killionaire",
	"Big Smoke", "Showdown", "Craterhead", "Meteora", "Supremo", "Shelluminati",
	"Ms Direct", "Buzz Bombardier", "Bang Ladesh", "Cannon O'Brian", "Crush Limbomb",
	"The Pulveriser", "Highway Spar", "Kabloom Affleck", "Exploderman",
	"Tank You Next", "Shelliot Page", "Shellex", "Tanky Kong", "Big Damage", "Lead Scraplin",
	"Freddie Dead", "Mortar Combat", "The Blast Ronin", "Bombsylvania", "Dr Boomlove",
	"Gunpowder", "The Shellector", "Bombparts", "Leadnought", "Arc Angel", "Lord Farshot",
	"Lead Reckoning", "Lead or Alive", "Lead Island", "Lead Rising", "Lead Money",
	"Filthy Fallout", "Major Reach", "Shellvester Stallone", "Down Ranger", "ShazBot",
	"Hullbuster", "Ironed Men", "Doctor Strays", "The Boominator", "Lead Better", "Wet Lead",
	"Ducks Go Flak", "Pillar of Bombem", "Aiming Lou Wood", "Bomb Crews", "Bomb Hanks",
	"Kate Wins It", "Scope Leo", "Orlando Boom", "Nicolas Rage", "Bruce Will Miss",
	"Sandra Bullet", "Bomb Haul End", "Barton Plink", "Earthquaker", "Bombstation Vita",
	"Bomb Box Series X", "Team Rocket", "Cannonball Z", "Aimbot", "Center Strike",
	"Lead Zeppelin", "Boomhowser", "Kantmiss", "Tanksgiving", "Shrapnella", "Explodabeth",
	"Kablamuel L Jackson", "Sir Aimsalot", "Plink Panther S.", "Bomber Energy", "Bombstar",
	"Blam Hathaway", "Midbommer", "Florence Pew-Pew", "Ice Snipes",
]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	enemy_names.shuffle()
	_check_for_specified_positions()

# Vector2i has [min,max] for each type
func populate_random_on_terrain(terrain: Terrain, ai_players: Vector2i = Vector2i(), human_players: Vector2i = Vector2i()) -> Array[TankController]:
	_used_positions.clear()
	_all_positions.clear()
	_placed_positions.clear()

	_ai_hue_index = 0
	ai_colors.shuffle()

	if ai_players.x <= 0:
		ai_players = default_ai_players
	if human_players.x <= 0:
		human_players = default_human_players
	
	var num_ai := randi_range(ai_players.x, ai_players.y)
	var num_human := randi_range(human_players.x, human_players.y)
	var total_spawns := num_ai + num_human
	
	if total_spawns <= 0:
		print("ArtillerySpawner(%s): No spawning requested - returning []" % [name])
		return []
	
	print("ArtillerySpawner(%s): Requesting spawning - num_ai=%d [%d-%d]; num_human=%d [%d-%d]" 
	% [name, num_ai, ai_players.x, ai_players.y, num_human, human_players.x, human_players.y])
	
	if !await _calculate_spawn_positions(terrain, total_spawns):
		push_warning("ArtillerySpawner(%s): Unable to generate requested spawn count=%d; generated=%d" % [name, total_spawns, _used_positions.size()])
		
	var spawned_list := spawn_multiple_units(_used_positions, num_human)
	
	return spawned_list

func _check_for_specified_positions() -> void:
	for child in get_children():
		if child is Marker2D:
			_specified_positions.push_back(child)

func _instantiate_controller_scene_at(_scene: PackedScene, _position: Vector2) -> TankController:
	if !_scene:
		push_error("ArtillerySpawner(%s): Unable to create TankController from NULL scene" % [name])
		return null
	var instance := _scene.instantiate() as TankController
	if instance:
		instance.global_position = _position
	else:
		push_error("ArtillerySpawner(%s): Unable to create TankController from packed scene=%s" % [name, _scene])
	
	return instance

func init_controller_props(controller: TankController) -> void:
	if controller is AITank:
		controller.set_color(_get_rand_ai_color())
		
func _get_rand_ai_color() -> Color:
	if _ai_hue_index >= ai_colors.size():
		print_debug("%s: Exceeded available colors - selecting one at random" % name)
		return Color.from_hsv(randf(), ai_color_sv.s, ai_color_sv.v)
	
	var ai_color:Color = ai_colors[_ai_hue_index]
	_ai_hue_index += 1
	return Color.from_hsv(ai_color.h, ai_color_sv.s, ai_color_sv.v)

func _calculate_spawn_positions(terrain: Terrain, count: int) -> bool:
	var success:bool = true
	for marker in _specified_positions:
		_all_positions.push_back(marker.global_position)
		
	for placed_unit in get_tree().get_nodes_in_group(Groups.Unit):
		var placed_unit_node = placed_unit as Node2D
		if placed_unit_node:
			_placed_positions.push_back(placed_unit_node.global_position)
	print_debug("ArtillerySpawner(%s): Discovered %d placed units" % [name, _placed_positions.size()])
	await _generate_spawns(terrain, count - _all_positions.size())
	
	if count > _all_positions.size():
		push_warning("ArtillerySpawner(%s): Requesting %d spawns but only %d available" % [name, count, _all_positions.size()])
		success = false
		count = _all_positions.size()
	
	# Sort positions by x
	_all_positions.sort_custom(func(a:Vector2, b:Vector2) -> bool: return a.x < b.x)	
	_choose_positions(count)
			
	return success
	
func _generate_spawns(terrain: Terrain, requested_count: int) -> void:
	if requested_count <= 0:
		return
	
	await get_tree().create_timer(spawn_delay).timeout

	var spawn_bounds := terrain.get_bounds_global()

	_spawn_test_size = _compute_spawn_test_bounds()
	
	# Subtract out the safe bounds on either side
	var spawnable_size: float = spawn_bounds.size.x - (min_boundary_x_distance * 2)
	# Generate extra positions to work around the placed ones
	var surplus_pos:int = _placed_positions.size() * 2
	var generated_pos:int = requested_count + surplus_pos
	var stride:float = spawnable_size / generated_pos
	var min_x:float = spawn_bounds.position.x + min_boundary_x_distance
	var max_x:float = min_x + spawnable_size
	var min_spawn_separation:float = minf(ideal_min_spawn_separation, stride)
	
	var last_x:float = min_x
	
	var skipped_pos:int = 0
	
	var error: Dictionary[String, Variant] = {}
	var fallback_positions: Array[Vector3] = []

	for i in generated_pos:
		var next_min_x:float = last_x + min_spawn_separation
		var x:float = maxf(min_x + randf_range(i * stride, (i + 1) * stride), next_min_x)
		
		var pos := _get_spawn_position(terrain, x, next_min_x, minf(x + stride, max_x), error)
		last_x = pos.x
		
		# Make sure not too close to a placed unit
		var should_add:bool = true
		if skipped_pos < surplus_pos:
			for placed_pos in _placed_positions:
				if absf(placed_pos.x - pos.x) < min_spawn_separation:
					skipped_pos += 1
					should_add = false
					break
		if should_add:
			if error.is_empty():
				_all_positions.push_back(pos)
			else:
				# If we couldn't find a position, add it to the fallback list
				# Add the angle so can sort by it later to pick best ones
				fallback_positions.push_back(Vector3(pos.x, pos.y, error["angle"]))

	if _all_positions.size() < requested_count:
		# We need to pick the best positions from the fallback list
		push_warning("ArtillerySpawner(%s): Using fallback positions for requested spawn count=%d; generated=%d; fallback_count=%d" %
		 [name, requested_count, _all_positions.size(), fallback_positions.size()])
		
		fallback_positions.sort_custom(func(a:Vector3, b:Vector3) -> bool: return a.z < b.z)
		for i in mini(fallback_positions.size(), requested_count - _all_positions.size()):
			var pos:Vector2 = Vector2(fallback_positions[i].x, fallback_positions[i].y)
			_all_positions.push_back(pos)

func _compute_spawn_test_bounds() -> float:
	var prototype_object: Node2D = player_type.instantiate() as TankController
	add_child(prototype_object)
	assert(prototype_object != null, "ArtillerySpawner(%s): _compute_spawn_test_bounds() - prototype_object is not a TankController" % [name])

	var bounding_box:Rect2 = prototype_object.tank.get_rect()
	remove_child(prototype_object)
	prototype_object.queue_free()

	if is_zero_approx(bounding_box.size.x):
		push_error("ArtillerySpawner(%s): _compute_spawn_test_bounds() - bounding_box.size.x is zero: %s -> %s" % [name, prototype_object.name, bounding_box])
		return default_spawn_test_size
	
	return bounding_box.size.x
	
func _choose_positions(count: int) -> void:
	if count < _all_positions.size():
		# Assuming the points are evenly distributed
		var max_position:int = _all_positions.size() - 1
		var stride:float = float(_all_positions.size()) / count
		
		var _used_indices:Array[int] = []
		
		var last_index:int = 0
		for i in range(0, count):
			var index:int = mini(last_index + roundi(randf_range(i * stride, (i + 1) * stride)), max_position)
			# Already guarded against infinite loop as clamp count to max positions
			# This shouldn't happen much - only in cases of player count to 
			while index in _used_indices:
				index -= 1
				if index < 0:
					index = max_position
			_used_indices.push_back(index)
			_used_positions.push_back(_all_positions[index])
			last_index = index
	else: 	# Special case of total positions available is count
		_used_positions.append_array(_all_positions)
	
	# Shuffle final positions since the AI to player ratio is based on the index
	_used_positions.shuffle()
	
func _choose_starting_weapons() -> Array[PackedScene]:
	assert(not artillery_ai_starting_weapons.is_empty(), "_choose_starting_weapons called on empty artillery_ai_starting_weapons")
	
	var spawn_count:int = randi_range(
		clampi(artillery_ai_starting_weapon_count.x, 1, artillery_ai_starting_weapons.size()),
		clampi(artillery_ai_starting_weapon_count.y, 1, artillery_ai_starting_weapons.size()))
	
	# Duplicate as we will be shuffling
	var weapons: Array[PackedScene] = artillery_ai_starting_weapons.duplicate()
	weapons.shuffle()
	
	var chosen_weapons: Array[PackedScene] = []
	chosen_weapons.resize(spawn_count)
	for i in spawn_count:
		chosen_weapons[i] = weapons[i]
		
	return chosen_weapons
	
func _attach_weapons(attach_to:TankController,weapon_scenes:Array[PackedScene]) -> void:
	# TankController will update each call because it expects them all at once.
	var weapons: Array[Weapon]
	attach_to.remove_all_weapons(true)
	for w in weapon_scenes:
		if w.can_instantiate():
			var instance = w.instantiate() as Weapon
			instance.use_ammo = false ## TODO Temporary
			weapons.append(instance)
	attach_to.attach_weapons(weapons)
	
func spawn_multiple_units(positions:Array[Vector2], num_human:int, parent = self) -> Array[TankController]:
	var all_spawned : Array[TankController] = []
	
	for i in range(0, positions.size()):
		var spawned
		if i < num_human:
			spawned = spawn_unit(positions[i], false, parent)
		else:
			spawned = spawn_unit(positions[i], true, parent)
			
		if spawned:
			all_spawned.push_back(spawned)

	assign_teams(all_spawned)
	return all_spawned

func spawn_unit(_global_position:Vector2, is_ai:bool = true, parent = self) -> TankController:
	var scene:PackedScene
	
	if not is_ai:
		scene = player_type
	else:
		scene = artillery_ai_types.pick_random()
	var spawned := _instantiate_controller_scene_at(scene, _global_position)
	if spawned:
		# Disable fall damage - important especially for the procedural spawning as right now we generate points on a slant
		# Must be done before adding to the scene tree
		spawned.enable_damage_before_first_turn = false

		parent.add_child(spawned)
		if is_ai:
			## Give AI random names
			var display_name = enemy_names.pick_random()
			enemy_names.erase(display_name)
			spawned.name = display_name
			if artillery_ai_starting_weapons:
				var weapons_to_attach:Array[PackedScene] = _choose_starting_weapons()
				_attach_weapons(spawned, weapons_to_attach)
		# Child nodes are null until added to the scene
		init_controller_props(spawned)
		return spawned
	else:
		return null

func assign_teams(spawned: Array[TankController]) -> void:
	if num_ai_teams <= 0:
		return

	var ai_players: Array[AITank] = []
	for controller in spawned:
		if controller is AITank:
			ai_players.append(controller)

	if group_teams_together:
		ai_players.sort_custom(func(a:AITank, b:AITank) -> bool: return a.global_position.x < b.global_position.x)
	
	var team_size:int = maxi(ceili(ai_players.size() / float(num_ai_teams)), 2)
	
	var team_number:int = -1
	var team_leader:int = -1
	for i in ai_players.size():
		if i % team_size == 0:
			team_number += 1
			team_leader = i
		else:
			# AI get color of their team leader
			ai_players[i].set_color(ai_players[team_leader].get_color())
		ai_players[i].team = team_number
		
func _get_spawn_position(terrain: Terrain, x: float, min_x:float, max_x:float, error: Dictionary[String, Variant]) -> Vector2:
	error.clear()

	var pos: Vector2 = _get_ground_position(terrain, x)
	var angle: float = _get_ground_angle_at(terrain, pos) if not pos.is_equal_approx(SENTINEL_VECTOR) else SENTINEL_ANGLE
	
	if angle <= max_slant_angle_deg:
		return pos
	
	# Need to iterate and find a new position
	# if none, are viable pick the best one
	
	var best_angle:float = angle
	var best_pos:Vector2 = pos

	var bounds_stride:float = _spawn_test_size * spawn_test_bounds_delta
	var num_iterations:int = floor((max_x - min_x) / bounds_stride)
	var test_x:float = min_x
	
	print_debug("ArtillerySpawner(%s): _get_spawn_position(%f) iterating up to %d times between [%f,%f]" % 
		[name, x, num_iterations, min_x, max_x])
		
	for i in num_iterations:
		if not is_equal_approx(test_x, x):
			var test_pos:Vector2 = _get_ground_position(terrain, test_x)
			if test_pos.is_equal_approx(SENTINEL_VECTOR):
				continue
			var test_angle:float = _get_ground_angle_at(terrain, test_pos)
			if test_angle <= max_slant_angle_deg:
				return test_pos
			if test_angle < best_angle:
				best_angle = test_angle
				best_pos = test_pos

		test_x += spawn_test_bounds_delta

	# Set error details
	error["angle"] = best_angle

	if best_pos.is_equal_approx(SENTINEL_VECTOR):
		push_error("ArtillerySpawner(%s): _get_spawn_position could not find y for x=%f" % [name, x])
		return Vector2(x, 0)
	
	push_warning("ArtillerySpawner(%s): _get_spawn_position found best_pos=%s with angle=%f > %f in range [%f, %f] for initial x=%f" %
		[name, best_pos, best_angle, max_slant_angle_deg,  min_x, max_x, x])
	
	return best_pos

func _get_ground_position(terrain: Terrain, x: float) -> Vector2:
	var from:Vector2 = Vector2(x, 0)
	var to:Vector2 = Vector2(x, get_viewport().get_visible_rect().size.y)
	
	var query_params = PhysicsRayQueryParameters2D.create(from, to,
	 Collisions.CompositeMasks.tank_snap)
	
	var space_state := terrain.get_world_2d().direct_space_state
	var result: Dictionary = space_state.intersect_ray(query_params)

	if !result:
		return SENTINEL_VECTOR
		
	return result["position"] + Vector2(0, spawn_y_offset)

func _get_ground_angle_at(terrain: Terrain, pos: Vector2) -> float:
	var half_width:float = _spawn_test_size * 0.5

	var left_point := _get_ground_position(terrain, pos.x - half_width)
	if left_point.is_equal_approx(SENTINEL_VECTOR):
		return SENTINEL_ANGLE
	
	var right_point := _get_ground_position(terrain, pos.x + half_width)
	if right_point.is_equal_approx(SENTINEL_VECTOR):
		return SENTINEL_ANGLE

	# Need at least one of these to be within the max slant angle
	var angle_left:float = MathUtils.get_angle_deg_between_points(left_point, pos)
	if angle_left <= max_slant_angle_deg:
		return angle_left

	var angle_right:float = MathUtils.get_angle_deg_between_points(pos, right_point)
	if angle_right <= max_slant_angle_deg:
		return angle_right

	# also test left to right
	var angle_all:float = MathUtils.get_angle_deg_between_points(left_point, right_point)
	if angle_all <= max_slant_angle_deg:
		return angle_all
	
	# Return minimum of all three
	return min(angle_left, angle_right, angle_all)
