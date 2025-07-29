class_name DefaultProjectileScorer extends WeaponScorer

@export_range(1.0, 10.0, 0.1) 
var non_explode_penalty_factor:float = 4.0
@export_range(0.0, 10.0, 0.1)
var reuse_penalty_factor:float = 3.0

var _max_target_distance:float

var _use_tracker:Dictionary[int,int] = {}
var _total_uses:int = 0

func _ready() -> void:
	_max_target_distance = get_viewport().get_visible_rect().size.x

func handles_weapon(_weapon: Weapon, projectile: Node2D) -> bool:
	return projectile is WeaponProjectile

func on_chosen(weapon:Weapon, _projectile: Node2D) -> void:
	_total_uses += 1
	var id:int = weapon.get_instance_id()
	var use_count:int = _use_tracker.get(id, 0)
	use_count += 1
	_use_tracker[weapon.get_instance_id()] = use_count

func compute_score(_tank: Tank, weapon: Weapon, in_projectile: Node2D, target_distance:float, _opponents: Array[TankController], _comparison_result:int) -> float:
	var projectile: WeaponProjectile = in_projectile as WeaponProjectile
	if not projectile or target_distance <= projectile.max_falloff_distance:
		# 0 signifies a netural result so won't be picked as best or worst
		return 0.0

	var count_multiplier: float = weapon.number_of_scenes_to_spawn
	if weapon.always_shoot_for_duration > 0:
		count_multiplier *= weapon.always_shoot_for_duration * weapon.fire_rate
	else:
		count_multiplier *= weapon.ammo_used_per_shot
	var score: float = projectile.max_damage * projectile.max_damage * projectile.min_falloff_distance * projectile.max_falloff_distance * count_multiplier
	# The bounce makes it more difficult to hit the target, so we want to reduce the score
	# TODO: Could spit out into a bouncing ball weapon scorer implementation
	if not projectile.should_explode_on_impact:
		# Bigger peanlty for closer targets as more likely to miss
		score *= exp(-non_explode_penalty_factor * (_max_target_distance - target_distance) / _max_target_distance)
	
	score *= _compute_reuse_penalty(weapon)
	return score

func _compute_reuse_penalty(weapon: Weapon) -> float:
	# If the weapon has been used before, apply a penalty
	var use_count:int = _use_tracker.get(weapon.get_instance_id(), 0)
	if use_count > 0:
		var use_fraction:float = float(use_count) / _total_uses
		return exp(-reuse_penalty_factor * use_count * use_fraction)
	return 1.0	
