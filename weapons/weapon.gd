class_name Weapon extends Node2D
## To use: attach script to a Node2D and configure in the Inspector panel.
## Contains functionality for ammo based weapons, magazines, fire rate (cycling), and reloading.
## Also TODO provide support for continuous fire weapons like a laser beam etc.
## Provide Marker2D nodes in the barrels array, shots will spawn from each point, in order.

#enum WeaponType{}
signal weapon_actions_completed(weapon: Weapon) ## Emits once all the projectiles have completed their lifespans.
signal weapon_destroyed(weapon: Weapon)

#region Variables
@export var scene_to_spawn: PackedScene ## This is the projectile or shoot effect.
@export var parent_tank: Tank ## Right now, the tank script has methods we need.
@export var display_name: String ## Not implemented

@export_group("Behavior")
@export_range(-360,360,0.0001,"radians_as_degrees") var accuracy_angle_spread: float = 0.0 ## Radians.
@export var fire_velocity: float = 100.0 ## Initial speed of the projectile.
@export var fires_continuously: bool = false ## Continuous-fire weapons don't use fire rate.
@export var use_fire_rate: bool = false ## Prevents shooting while cycling.
@export var fire_rate: float = 4.0 ## Rate of fire per second. 4.0 would fire once every quarter-second.
@export var always_shoot_for_duration:float = 0.0 ## If greater than zero, when Shoot() is called, weapon will fire as frequently as it can based on fire-rate for this duration in seconds.
@export var always_shoot_for_count:int = 1.0 ## When fired, weapon will shoot this many times, separated by fire rate delay.
@export var barrels: Array[Marker2D] = [] ## 
var barrels_sfx_fire: Array[AudioStreamPlayer2D] = []
var current_barrel: int = 0

@export_group("Ammo")
@export var retain_when_empty: bool = true ## If false, destroy the Weapon once out of ammo.
@export var use_ammo: bool = false ## Whether to check and track ammo.
@export var current_ammo: int = 16 ## Starting ammo.
@export var ammo_used_per_shot: int = 1.0
@export var use_magazines: bool = false ## If true, use a finite ammo supply.
@export var magazines: int = 3
@export var magazine_capacity: int = 16
@export var reload_delay_time: float = 2.0 ## Seconds it takes to reload a mag.

## Sound Effects
@export_group("Sounds")
@export var sfx_fire: AudioStreamPlayer2D
@export var sfx_dry_fire: AudioStreamPlayer2D
@export var sfx_reload: AudioStreamPlayer2D
@export var sfx_equip: AudioStreamPlayer2D
@export var sfx_unequip: AudioStreamPlayer2D
@export var sfx_idle: AudioStreamPlayer2D

var is_reloading: bool = false
var is_cycling: bool = false ## Weapon won't fire while cycling--see fire rate
var is_equipped: bool = false ## Used for SFX, also the weapon won't fire if unequipped.
var is_shooting: bool = false
var _shoot_for_duration_power: float
var _shoot_for_count_remaining: int
var _awaiting_lifespan_completion: int

@onready var parent = get_parent()
@onready var sounds = [
		sfx_fire,
		sfx_dry_fire,
		sfx_reload,
		sfx_equip,
		sfx_unequip,
		sfx_idle
	]
#endregion

#region Virtuals
func _ready() -> void:
	weapon_actions_completed.connect(_on_weapon_actions_completed)
	if parent_tank:
		weapon_destroyed.connect(parent_tank._on_weapon_destroyed)
	configure_barrels()
	reload()
	
func _process(delta: float) -> void:
	if is_shooting: ## Shooting for duration or count.
		_shoot(_shoot_for_duration_power)
#endregion
	
#region Public Methods
func equip() -> void:
	if not is_equipped:
		is_equipped = true
		if sfx_equip: sfx_equip.play()
		if sfx_idle: sfx_idle.play()
	#else: print("Tried to equip already equipped!")
	
func unequip() -> void:
	if is_equipped:
		is_equipped = false
		if sfx_unequip: sfx_unequip.play()
		if sfx_idle: sfx_idle.stop()
	#else: print("Tried to unequip already unequipped!")
	
func shoot(power:float = fire_velocity) -> void:
	if is_shooting: return
	if always_shoot_for_duration > 0.0:
		shoot_for_duration(always_shoot_for_duration, power)
	elif always_shoot_for_count > 1:
		shoot_for_count(always_shoot_for_count, power)
	else:
		_shoot(power)
	
func shoot_for_duration(duration:float = always_shoot_for_duration, power:float = fire_velocity) -> void:
	if is_shooting: return
	_shoot_for_duration_power = power
	is_shooting = true
	_shoot(power)
	await get_tree().create_timer(duration).timeout
	is_shooting = false

func shoot_for_count(count:int, power:float = fire_velocity) -> void:
	if is_shooting: return
	_shoot_for_duration_power = power
	_shoot_for_count_remaining = count
	is_shooting = true
	_shoot(power)
	
func reload(immediate: bool = false) -> void:
	if not is_equipped: return
	if is_reloading: return
	if use_magazines && magazines < 1: return ## Out of magazines/ammo.
	if use_ammo:
		is_reloading = true
		if not immediate: ## Instant reloading
			await get_tree().create_timer(reload_delay_time).timeout ## Reload Timer
		current_ammo = magazine_capacity ## Reset ammo
		if use_magazines: magazines -= 1
	else:
		pass
	is_reloading = false ## Finished reloading.
	if sfx_reload: sfx_reload.play() ## Trigger the SFX to play
		
func cycle() -> void:
	if use_fire_rate: ## Prevent shooting while cycling.
		is_cycling = true
		await get_tree().create_timer(1.0/fire_rate).timeout
		is_cycling = false
	current_barrel += 1
	if current_barrel+1 > barrels.size():
		current_barrel = 0
		
func restock() -> void:
	restock_ammo()
	if use_magazines: restock_magazines()
	print_debug(display_name," ammo restocked.")

func restock_magazines(new_magazines:int = 1) -> void:
	magazines += new_magazines

func restock_ammo(ammo:int = magazine_capacity) -> void:
	current_ammo += ammo

func configure_barrels() -> void:
	current_barrel = 0
	barrels_sfx_fire.clear()
	#print_debug(display_name," found ", barrels.size()," barrels.")
	if barrels.size() == 0:
		var new_marker_2d = Marker2D.new()
		add_child(new_marker_2d)
		barrels.append(new_marker_2d) ## So we can access our own basis data.
		## Typically if you're shooting from this spot you're inside of your own tank, and it will just instantly collide.
	
	for i in barrels:
		if sfx_fire: ## Set up audio stream players at the barrel points.
			var new_fire_sfx = sfx_fire.duplicate()
			add_child(new_fire_sfx)
			barrels_sfx_fire.append(new_fire_sfx)

func stop_all_sounds(only_looping: bool = true) -> void:
	for s: AudioStreamPlayer2D in sounds:
		#if it's a looping sound...
		if s.playing: s.stop()

func destroy() -> void:
	weapon_destroyed.emit(self)
	queue_free()
#endregion

#region Private Methods
func _shoot(power:float = fire_velocity) -> void:
	if not is_equipped: return
	if is_cycling: return
	if is_reloading:
		if sfx_dry_fire: sfx_dry_fire.play()
		cycle() ## To PUNISH them...
		return
	if use_ammo == true && current_ammo <= 0:
		if sfx_dry_fire: sfx_dry_fire.play()
		cycle()
		return ## We can't shoot.
		
	if not fires_continuously:
		if not barrels_sfx_fire.is_empty(): barrels_sfx_fire[current_barrel].play()
		_spawn_projectile(power)
		cycle()
		GameEvents.emit_weapon_fired(self) # This has no game effects right now.
	else:
		## Alternative handling for continuous weapons
		print_debug("Continuous fire is not yet supported")
		cycle()
		pass
		
	if use_ammo: current_ammo -= ammo_used_per_shot
	if _shoot_for_count_remaining > 0:
		_shoot_for_count_remaining -= 1
		if _shoot_for_count_remaining == 0:
			is_shooting = false
			
func _spawn_projectile(power: float = fire_velocity) -> void:
	var barrel = barrels[current_barrel]
	if scene_to_spawn and scene_to_spawn.can_instantiate():
		var new_shot = scene_to_spawn.instantiate() as Node2D
		#var container = get_tree().current_scene
		#var container = parent_tank.get_fired_weapon_container() ## TODO Refactor
		var container = SceneManager.get_current_level_root()
		if container.has_method("get_container"):
			container = container.get_container()
		
		if new_shot is WeaponProjectile:
			new_shot.set_sources(parent_tank,self)
			new_shot.completed_lifespan.connect(_on_projectile_completed_lifespan) # So we know when the projectile is finished.
			_awaiting_lifespan_completion += 1
		
		new_shot.global_transform = barrel.global_transform
		var aim_angle = barrel.global_rotation - PI/2 # 90 degrees offset
		if accuracy_angle_spread != 0.0:
			var deviation = randf_range(-accuracy_angle_spread,accuracy_angle_spread) / 2
			aim_angle += deviation
		
		var velocity = Vector2(power, 0.0)
		new_shot.linear_velocity = velocity.rotated(aim_angle)
		
		container.add_child(new_shot)
		#print_debug("Shot fired with ", velocity, " at ", aim_angle)

func _on_projectile_completed_lifespan() -> void:
	_awaiting_lifespan_completion -= 1
	if not is_shooting: # Wait til we've fired all our shots this action
		if _awaiting_lifespan_completion < 1:
			weapon_actions_completed.emit(self) # If this doesn't emit, the game turn will be stuck.

func _on_weapon_actions_completed(weapon: Weapon) -> void:
	if not retain_when_empty:
		if current_ammo < 1:
			if magazines < 1 or not use_magazines:
				destroy()
	if parent_tank is Tank: ## This is when Turn Changeover happens. It should signal to Player or AI not the game manager directly, then we could have multiple actions per turn.
		GameEvents.emit_turn_ended(parent_tank.owner)
#endregion
