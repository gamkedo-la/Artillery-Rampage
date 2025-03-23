class_name SniperBruteAIBehavior extends BruteAIBehavior

@export_group("Sniper")
## Max target distance
@export_range(100.0, 1.0, 0.01) var max_target_distance: float = 500.0

@export_group("Sniper")
@export_range(0.0, 90.0, 1.0) var max_aim_error: float = 30.0

@export_group("Sniper")
@export_range(0.0, 10.0, 0.1) var aim_error_dev: float = 2.0

@onready var sniper_error_calc: SniperAIErrorCalculation = $SniperErrorCalc

func _is_perfect_shot(_opponent_data: Dictionary) -> bool:
	# Manually calculate the error
	return false

func _is_better_fallback_opponent(_candidate: TankController, _current_best: TankController, candidate_dist_sq: float, current_best_dist_sq) -> bool:
	return candidate_dist_sq > current_best_dist_sq and candidate_dist_sq <= max_target_distance * max_target_distance

func _is_better_viable_opponent(_candidate: TankController, _current_best: TankController, candidate_dist_sq: float, current_best_dist_sq) -> bool:
	return candidate_dist_sq > current_best_dist_sq

func get_aim_error(perfect_shot_angle: float, opponent_data: Dictionary) -> float:
	# Aim error increases with closer distance
	var distance: float = opponent_data.distance
	var angle_sgn: float = sign(perfect_shot_angle)
	
	var aim_error: float = max_aim_error * angle_sgn * sniper_error_calc.get_error_fract(_get_playable_x_extent(), distance)
	if is_zero_approx(aim_error):
		return 0.0
	
	return aim_error + randf_range(0.0, aim_error_dev)
