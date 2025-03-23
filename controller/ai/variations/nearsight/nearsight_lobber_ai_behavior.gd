class_name NearsightLobberAIBehavior extends LobberAIBehavior

@export_group("Nearsight")
@export_range(0.0, 90.0, 1.0) var max_aim_error: float = 30.0

@export_group("Nearsight")
@export_range(0.0, 1.0, 0.01) var max_power_error: float = 0.1

@export_group("Nearsight")
@export_range(0.0, 10.0, 0.1) var aim_error_dev: float = 2.0

@onready var nearsight_error_calc: NearsightAIErrorCalculation = $NearsightErrorCalculation

func _is_perfect_shot(_opponent_data: Dictionary) -> bool:
	# Manually calculate the error
	return false
	
func get_power_error(_perfect_power: float, opponent_data: Dictionary) -> float:
	# Power error increases with closer distance
	var distance: float = opponent_data.distance

	var power_error: float = max_power_error * nearsight_error_calc.get_error_fract(_get_playable_x_extent(), distance)
	if is_zero_approx(power_error):
		return 0.0
	
	return power_error if randf() > 0.5 else -power_error

func get_aim_error(perfect_shot_angle: float, opponent_data: Dictionary) -> float:
	# Aim error increases with closer distance
	var distance: float = opponent_data.distance
	var angle_sgn: float = sign(perfect_shot_angle)
	
	var aim_error: float = max_aim_error * angle_sgn * nearsight_error_calc.get_error_fract(_get_playable_x_extent(), distance)
	if is_zero_approx(aim_error):
		return 0.0
	
	return aim_error + randf_range(0.0, aim_error_dev)
