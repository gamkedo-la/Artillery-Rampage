extends Control

@onready var angle_text:HUDElement = %Angle
@onready var power_text:HUDElement = %Power
@onready var health_text:HUDElement = %Health
@onready var walls_text:HUDElement = %Walls

@onready var active_player_text = $CenterBackground/VBoxContainer3/ActivePlayer
@onready var wind_text = $CenterBackground/VBoxContainer3/Wind
@onready var weapon_text = $CenterBackground/VBoxContainer3/Weapon

@onready var debug_level_name: Label = %DebugLevelName
@onready var tooltipper: Control = %Tooltipper

func _ready() -> void:
	init_signals()
	_on_user_options_changed() # Apply user options

func init_signals():
	GameEvents.connect("turn_started", _on_turn_started);
	GameEvents.connect("aim_updated", _on_aim_updated);
	GameEvents.connect("power_updated", _on_power_updated)
	GameEvents.connect("wind_updated", _on_wind_updated)
	GameEvents.connect("weapon_updated", _on_weapon_updated)
	GameEvents.connect("level_loaded", _on_level_changed)
	GameEvents.user_options_changed.connect(_on_user_options_changed)
	
	if OS.is_debug_build():
		debug_level_name.show()

func _on_turn_started(player: TankController) -> void:
	active_player_text.text = player.name
	health_text.set_value(ceil(player.tank.health))
	
	_on_aim_updated(player)
	_on_power_updated(player)

func _on_aim_updated(player: TankController) -> void:
	var angleRads = player.tank.get_turret_rotation()
	
	angle_text.set_value(str(int(abs(rad_to_deg(angleRads))))+"°") 

func _on_power_updated(player: TankController) -> void:
	power_text.set_value(int(player.tank.power))

func _on_wind_updated(wind: Wind) -> void:
	var vector := wind.wind
	var value := vector.length()
	
	var direction := vector.x
	wind_text.set_value("%d %s" % [_fmt_wind_value(value), _get_direction_string(direction)])

func _fmt_wind_value(value: float) -> int:
	return int(abs(value))

func _get_direction_string(value: float) -> String:
	return "▶" if value >= 0 else "◀"
	
func _on_weapon_updated(weapon: Weapon) -> void:
	weapon_text.set_label(weapon.display_name)
	weapon_text.set_value(str(weapon.current_ammo) if weapon.use_ammo else char(9854))

func _on_level_changed(level: GameLevel) -> void:
	if OS.is_debug_build():
		var file_name = SceneManager.current_scene.scene_file_path
		debug_level_name.text = file_name
	walls_text.value.text =_fmt_walls_value(level.walls)

func _on_user_options_changed() -> void:
	if UserOptions.show_hud:
		if not visible: show()
	else:
		if visible: hide()

func _fmt_walls_value(walls:Walls) -> String:
	match walls.wall_mode:
		Walls.WallType.NONE: return "None"
		Walls.WallType.WARP: return "Warp"
		Walls.WallType.ELASTIC: return "Elastic"
		Walls.WallType.ACCELERATE: return "Accelerate"
		Walls.WallType.STICKY: return "Sticky"
		_: return "<!ERROR>"
