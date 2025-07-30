## A [Node2D] that spawns scenes with a wide scope of options focused on firearms.
##
## Contains functionality for ammunition, magazines, fire rate (cycling), reloading, variable quantity
## of projectiles spawned at once, and duration-based continuous fire.
## [br][br]
## Use in the editor: attach script to a Node2D and configure in the Inspector panel.
## Can be set up in code but is designed to be instantiated as a scene root with [AudioStreamPlayer2D]
## children, [Marker2D] barrels (whose transform is used when spawning the projectiles), and art.
## [br][br]
##
## The various [method shoot] methods will spawn [WeaponProjectile]s at the first barrel in
## [member barrels] and continue in order for each successive shot before looping back to the first entry.
## Sound effects will play when appropriate if configured.
## Key parameters like [member accuracy_angle_spread]
## , [member power_launch_speed_mult] , [member fire_rate] , [member retain_when_empty] , and [member use_ammo]
## can completely change how the [Weapon] behaves.
## Look in [i]Behavior[/i] and [i]Ammo[/i] for details.
## The player's in-game's [b]HUD[/b] uses [member display_name] when it is called upon in
## [method Tank.push_weapon_update_to_hud].
## If configured in the Inspector, sound effects such as [member sfx_fire] will play when appropriate.
## Weapon upgrades [ModWeapon] can be attached either in the Inspector: [member weapon_mods],
## or in code using [method attach_mods].
## [br][br]
## [color=yellow]TODO[/color][i] provide support for continuous fire weapons like a laser beam etc.
## See [member fires_continuously].[/i]

class_name Weapon extends Node2D

## Emits once all the [WeaponProjectile]s fired by this [Weapon] have completed their lifespans.
signal weapon_actions_completed(weapon: Weapon)
## Emits when [method Weapon.destroy] before [method queue_free].
signal weapon_destroyed(weapon: Weapon)
## Can be used by components.
signal projectile_spawned(projectile_root_node)
## Used to emit the [member current_ammo] as an [int].
signal ammo_changed(current_ammo:int)
## Used to emit the [member magazines] as an [int].
signal magazines_changed(current_magazines:int)
## Emitted when Player presses the "Cycle Weapon Mode" key.
signal mode_change(current_mode:int)

enum TRAJECTORY_TYPES {
	NONE = 0,
	PROJECTILE = 1,
	BEAM = 2,
}

#region Variables
## This scene is spawned and set up when this weapon is fired. It is designed to use
## [WeaponProjectile], but it also accepts other types, you may need to tinker.
## As long as it derives from [RigidBody2D], it will be given a starting [code]linear_velocity[/code].
@export var scene_to_spawn: PackedScene

## Used by [Tank] in [method connect_to_tank], and used to initialize some properties
## of [ModProjectile] when shot, in [method _spawn_projectile].
var parent_tank: Tank

## Used by the player's in-game HUD UI.
@export var display_name: String#:
	#get:
		#if not weapon_mods.is_empty():
			#return str(display_name + ": Modified")
		#else: return display_name

## Used by the Story Shop UI to provide tooltip info about the weapon.
@export_multiline var description: String

## Used for applying upgrades and nerfs at runtime. This array is applied in the [method _ready] function.
## The [ModWeapon] directly (permanently) alters the exposed properties of this instance.
## They can contain [ModProjectile] within that is automatically applied to [WeaponProjectile]
## spawned by this weapon. See also [member projectile_mods].
@export var weapon_mods: Array[ModWeapon]
## Used for applying upgrades and nerfs at runtime. This array is applied to every [WeaponProjectile]
## spawned by this weapon. See also [member weapon_mods].
var projectile_mods: Array[ModProjectile]


@export_group("Behavior")

@export var trajectory_indicator_type: TRAJECTORY_TYPES = TRAJECTORY_TYPES.PROJECTILE

## Inaccuracy of projectiles fired. A value of 0.0 is always perfectly accurate.
@export_range(0.0,360,0.0001,"radians_as_degrees") var accuracy_angle_spread: float = 0.0

## Default used if not provided one by the controlling object when
## calling [method shoot], [method shoot_for_count], or [method shoot_for_duration].
## [br][br]
## Use [member power_launch_speed_mult] instead for tweaking relative projectile launch speed.
## The Player and AI for example choose their power and pass it to the [method shoot] function, where
## this property has no effect; see [method Tank.shoot] & [member Tank.max_power].
@export var fire_velocity: float = 100.0

## Tune projectile's initial velocity.
## [br]
## Use this to make projectiles faster or slower than "default". This number is multiplied by
## [param power] in [method shoot], [method shoot_for_count], & [method shoot_for_duration].
@export_range(0.01, 10.0, 0.01,"or_greater","or_less") var power_launch_speed_mult: float = 1.00
## @experimental: Not yet functional
## Continuous-fire weapons don't use fire rate, and fire for a duration of time.
## See [member always_shoot_for_duration] and [method shoot_for_duration].
@export var fires_continuously: bool = false
## Whether to utilize the [member fire_rate] when shooting. This provides for machine gun/automatic
## rifle behavior. Shooting is prevented for the interval [member fire_rate]--see [method cycle].
@export var use_fire_rate: bool = false
## Rate of fire, per second. 4.0 would fire once every quarter-second.
## 0.5 would fire once every two seconds.
## [member use_fire_rate] must be [code]true[/code] for this to have any effect. See [method cycle].
@export var fire_rate: float = 4.0
## This many scenes are spawned and set up each time this weapon shoots.
## This provides for shotgun behavior. It is preferable to using [member always_shoot_for_count] with
## [code]use_fire_rate = false[/code], because they are instanced all at once.
@export var number_of_scenes_to_spawn:int = 1:
	get: return maxi(1, number_of_scenes_to_spawn)

## @experimental:
## If greater than zero, when Shoot() is called, weapon will fire as frequently as it can based on fire-rate for this duration in seconds.
@export var always_shoot_for_duration:float = 0.0:
	get(): return maxf(0.0, always_shoot_for_duration)
## When fired, weapon will shoot this many times, separated by fire rate delay.
## Keep in mind that each shot will spawn [member number_of_scenes_to_spawn].
@export var always_shoot_for_count:int = 1:
	get(): return maxi(1, always_shoot_for_count)
## @experimental: Emit signals necessary for game logic. Disable for alternate use cases.
## Implemented as a fix for TrajectoryPreviewer--see [Tank].
@export var emit_action_signals:bool = true
## Each time [method _shoot] is called, the spawned scene(s) will appear at and be launched from
## this transform, as will the [member sfx_fire] sound effect, if configured.
## [br][br]
## [b]Note:[/b] Automatically assigned through code for [Tank] weapons with
## [method TankController.attach_weapons], but can be manually specified otherwise.
@export var barrels: Array[Marker2D] = []
## Contains references to the instanced [AudioStreamPlayer2D] spawned at each barrel location.
var barrels_sfx_fire: Array[AudioStreamPlayer2D] = []
## Iterator index for [member barrels], used by [method cycle].
var current_barrel: int = 0

## Indicates whether the wobble mechanic makes sense for this weapon.
## Some weapons like the shield and parachute are not aimed so shouldn't have wobble.
@export var supports_wobble:bool = true

@export_flags(
	"Accuracy Angle Spread", "Always Shoot for Count",
	"Number of Scenes to Spawn", "Power Launch Speed Multiplier",
	"Retain when Empty", "Use ammo"
)
# Set to all by default by setting all the mask bits
var supported_mods:int = (1 << 6) - 1

@export_group("Ammo")
## If false, call [method destroy] once out of ammo (and magazines, if configured).
@export var retain_when_empty: bool = true
## Whether to check and track ammo. If [code]false[/code], you have infinite ammo.
@export var use_ammo: bool = false
## Starting ammo when this [Weapon] is instanced. Use [method reload] to refill this property.
@export var current_ammo: int = 16:
	set(value):
		current_ammo = maxi(value, 0)
## Each time [method _shoot] is called, decrement [member current_ammo] by this number. For example,
## if [code]number_of_scenes_to_spawn = 10[/code] and [code]ammo_used_per_shot = 3[/code], assuming
## the weapon is shot only once, 10 instances of the [member scene_to_spawn] will spawn, but [member current_ammo]
## will only have 3 deducted.[br]
## Following that example, if the [Weapon] were shot five times, there would be 50 instances of
## [member scene_to_spawn], and the [Weapon] will have spent 15 ammo.
@export var ammo_used_per_shot: int = 1:
	get: return maxi(0, ammo_used_per_shot)
## If [code]true[/code], use a finite ammo supply. Calling [method reload] will set [member current_ammo] to
## be equal to [member magazine_capacity], if there is a [member magazine] available.[br][br]
## If [code]false[/code], calling [method reload] will always refill the [member current_ammo] to its
## initial value.
@export var use_magazines: bool = false
## The current number of magazines available full of ammunition. The total available ammunition is
## [code]current_ammo + (magazines * magazine_capacity)[/code]. See [member use_magazines].[br][br]
## [b]Note:[/b] Magazines don't actually hold ammo, they simply represent the ability to reload
## [member current_ammo] to [member magazine_capacity].
@export var magazines: int = 3:
	get: return maxi(0, magazines)
## The number to set [member current_ammo] to upon [method reload]. See [member use_magazines].
@export var magazine_capacity: int = 16:
	get: return maxi(1, magazine_capacity)
## The time in seconds it takes to set [member current_ammo], during which the [Weapon] can not be fired.
@export var reload_delay_time: float = 2.0


@export_group("Sounds")
## Plays when [method _shoot] shoots successfully.
@export var sfx_fire: AudioStreamPlayer2D
## If true, the fire sfx will be Stopped when weapon actions are completed (all projectiles are finished).
@export var sfx_fire_sustain:bool = false
## Plays when the weapon tries to shoot but is stopped, for example from being out of ammo.
@export var sfx_dry_fire: AudioStreamPlayer2D
## Plays when [method reload] reloads successfully.
@export var sfx_reload: AudioStreamPlayer2D
## Plays when [method equip].
@export var sfx_equip: AudioStreamPlayer2D
## Plays when [method unequip].
@export var sfx_unequip: AudioStreamPlayer2D
## Starts playback when [method equip], and stops when [method unequip].
@export var sfx_idle: AudioStreamPlayer2D

# State variables
## Used to force [method configure_barrels] so that a barrel is ready for [method _spawn_projectile].
var is_configured: bool = false
## Used to prevent some conditional actions while reloading, such as [method shoot] and [method reload].
var is_reloading: bool = false
## Weapon won't fire while cycling--see [member use_fire_rate].
var is_cycling: bool = false
## Used for SFX, also [s]the weapon won't fire if unequipped.[/s]
## [i]Bypassed for now as there's no use case in our game for this logic yet.[/i]
var is_equipped: bool = false:
	set(value):
		is_equipped = value
	get:
		return true
## Used to [method shoot_for_duration], to prevent new shooting actions while already shooting,
## and when tracking [signal WeaponProjectile.completed_lifespan].
var is_shooting: bool = false

var _shoot_for_duration_power: float ## Internal: Cache of the requested power from [method shoot_for_duration].
var _shoot_for_count_remaining: int ## Internal: Counter for [method shoot_for_count].
var _awaiting_lifespan_completion: int ## Internal: Counter for [signal weapon_actions_completed].

var mode:int = 0 ## Subclasses and components can make use of this counter.
var modes_total:int = 0 ## Subclasses and components can make use of this counter.
var mode_node:WeaponModes ## Subclasses and components can make use of this pointer.

var active_projectiles:Array[Node2D]

var _enforced_projectile_properties:Dictionary
var _cached_projectile_instance

@onready var _starting_ammo:int = current_ammo ## Internal: Cache of [member current_ammo] on instantiation.
@onready var _starting_magazines:int = magazines ## Internal: Cache of [member magazines] on instantiation.

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
	GameEvents.game_paused.connect(_on_game_paused)
	apply_all_mods() # If the weapon's state is retained across scene trees, this could stack the effect unintentionally.
	
func _exit_tree() -> void:
	if is_instance_valid(_cached_projectile_instance):
		_cached_projectile_instance.queue_free()
	
func _process(_delta: float) -> void:
	if is_shooting: ## Shooting for duration or count.
		_shoot(_shoot_for_duration_power)
#endregion
	
#region Public Methods
## Should be called by a [Tank] to set up this [Weapon] for use by it.
## [br][br]
## Sets the [member parent_tank] to [param tank], connects signals
## [signal weapon_actions_completed], [signal weapon_destroyed], [signal ammo_changed], &
## [signal magazines_changed] to the [param tank]'s receiver methods, gets the location for a barrel
## from the [method Tank.get_weapon_fire_locations] and appends it to [member barrels], then calls
## [method configure_barrels] and finally [method reload]s the [Weapon] so it's ready to shoot.
func connect_to_tank(tank: Tank) -> void:
	parent_tank = tank
	
	if not weapon_actions_completed.is_connected(parent_tank._on_weapon_actions_completed):
		weapon_actions_completed.connect(parent_tank._on_weapon_actions_completed)
		
	if not weapon_destroyed.is_connected(parent_tank._on_weapon_destroyed): # Will push error
		weapon_destroyed.connect(parent_tank._on_weapon_destroyed)
		
	if not ammo_changed.is_connected(parent_tank._on_weapon_ammo_changed):
		ammo_changed.connect(parent_tank._on_weapon_ammo_changed)
	
	if not magazines_changed.is_connected(parent_tank._on_weapon_magazines_changed):
		magazines_changed.connect(parent_tank._on_weapon_magazines_changed)
	
	if not mode_change.is_connected(parent_tank._on_weapon_mode_changed):
		mode_change.connect(parent_tank._on_weapon_mode_changed)
		
	barrels.append(parent_tank.get_weapon_fire_locations())
	configure_barrels()
	#Reload immediately during configuration but we must wait until tank parent ready runs so wait a tick
	await get_tree().process_frame
	
	if OS.is_debug_build():
		print_debug("%s: connect to %s - use_ammo=%s; use_magazines=%s; ammo=%d; magazines=%d" % [display_name, tank.get_parent().name, str(use_ammo), str(use_magazines), current_ammo, magazines])
	
	reload(true) 
## Should be called by a [Tank] when exiting tree to disconnect this [Weapon].
## [br][br]
func disconnect_from_tank(tank: Tank) -> void:
	if parent_tank != tank:
		return

	is_configured = false
	is_equipped = false
	is_reloading = false
	
	barrels.clear()

## The [Weapon] must be [member is_equipped] to be fired. This method also uses sound effects if configured.
## See [member sfx_equip] & [member sfx_idle].
func equip() -> void:
	if not is_equipped:
		is_equipped = true
		if sfx_equip: sfx_equip.play()
		if sfx_idle: sfx_idle.play()
	#else: print("Tried to equip already equipped!")
	
## The [Weapon] must be [member is_equipped] to be fired. This method also uses sound effects if configured.
## See [member sfx_unequip] & [member sfx_idle].
func unequip() -> void:
	if is_equipped:
		is_equipped = false
		if sfx_unequip: sfx_unequip.play()
		if sfx_idle: sfx_idle.stop()
	#else: print("Tried to unequip already unequipped!")
	
## The primary way to fire the weapon, spawning projectiles according to the configuration.
## [br][br]
## A front door method that determines which function to call next. If [member always_shoot_for_duration]
## or [member always_shoot_for_count] is configured, it will employ those options.
## The [param power] will be cached and used for all the queued projectiles firing velocity.
## Will automatically configure [member barrels] if not [member is_configured] before.
## See [method shoot_for_duration], [method shoot_for_count], and [method _shoot].
func shoot(power:float = fire_velocity) -> void:
	if is_shooting: return
	if not is_configured:
		configure_barrels()
		await reload()
	elif use_ammo and current_ammo == 0 and can_reload():
		await reload()

	if always_shoot_for_duration > 0.0:
		shoot_for_duration(always_shoot_for_duration, power)
		return
	if always_shoot_for_count > 1:
		shoot_for_count(always_shoot_for_count, power)
		return
	else:
		_shoot(power)
	
## Make the [Weapon] shoot continuously for a duration of time [param duration] in seconds.
## The [param power] will be cached and used for all the queued projectiles firing velocity.
func shoot_for_duration(duration:float = always_shoot_for_duration, power:float = fire_velocity) -> void:
	if is_shooting: return
	_shoot_for_duration_power = power
	is_shooting = true
	
	if use_fire_rate == false and fires_continuously == false:
		## Prevent projectiles spawning every frame.
		push_error("You must use_fire_rate on this Weapon to shoot for duration!")
		use_fire_rate = true
	
	_shoot(power)
	await get_tree().create_timer(duration).timeout
	is_shooting = false

## Make the [Weapon] shoot continuously until it has [method _shoot] for [param count] number of times.
## The [param power] will be cached and used for all the queued projectiles firing velocity.
func shoot_for_count(count:int, power:float = fire_velocity) -> void:
	if is_shooting: return
	_shoot_for_duration_power = power
	_shoot_for_count_remaining = count
	is_shooting = true
	_shoot(power)
	
## Simply plays the [member sfx_dry_fire] sound effect if configured.
func dry_fire() -> void:
	if sfx_dry_fire: sfx_dry_fire.play()
	
## Manipulates [member current_ammo], if not prevented by ongoing weapon actions.
## If [member use_magazines], [member current_ammo] will be set to [member magazine_capacity] and
## [member magazines] will decrement by 1. [param immediate] is by default [code]false[/code], but
## if [code]true[/code], will skip creating a one-shot [Timer] with [member reload_delay_time] that
## prevents [Weapon] actions for a time using [member is_reloading], and instead immediately
## manipulate the ammunition/magazines.
## Also plays a sound effect if [member sfx_reload] is configured.
func reload(immediate: bool = false) -> void:
	if not is_equipped or not use_ammo: return
	if is_reloading: return
	if use_magazines && magazines < 1: return ## Out of magazines/ammo.
	
	is_reloading = true
	#if sfx_reload: sfx_reload.play() ## Trigger the SFX to play on start
	if not immediate: ## Instant reloading
		await get_tree().create_timer(reload_delay_time).timeout ## Reload Timer
	if use_magazines:
		magazines -= 1
		## Special case when starting with partial magazine from save
		if immediate and _starting_ammo > 0:
			current_ammo = _starting_ammo
		else:
			current_ammo = magazine_capacity ## Reset ammo
			ammo_changed.emit(current_ammo)
			magazines_changed.emit(magazines)
	else:
		current_ammo = _starting_ammo
		
	is_reloading = false ## Finished reloading.
	if sfx_reload: sfx_reload.play() ## Trigger the SFX to play on completion
	# This could definitely be a start and stop pair of sounds.
		
## Checks if weapon can be reloading during gameplay.
## This only applies to weapons with magazines as weapons without them just use all their available weapon and are only "reloaded" at round start.
func can_reload() -> bool:
	return is_equipped and use_ammo and (is_reloading or (use_magazines and magazines > 0))

## This function is called after every time the weapon shoots, to start the waiting timer
## if [member use_fire_rate], and to advance to the next member of [member barrels].
func cycle() -> void:
	if use_fire_rate: ## Prevent shooting while cycling.
		is_cycling = true
		await get_tree().create_timer(1.0/fire_rate).timeout
		is_cycling = false
	current_barrel += 1
	if current_barrel+1 > barrels.size():
		current_barrel = 0
		
## This method is different from [method reload] because it refills both
## [member current_ammo] as well as [member magazines] with their initial values
## from when this scene was [signal ready].
func restock() -> void:
	restock_ammo(_starting_ammo if not use_magazines else magazine_capacity)
	if use_magazines: restock_magazines(_starting_magazines)
	print_debug(display_name," ammo restocked.")

## Adds [param new_magazines] to [member magazines] and emits [signal magazines_changed].
func restock_magazines(new_magazines:int = 1) -> void:
	# Magazines don't actually hold ammo, they simply represent
	# the ability to reload current_ammo to magazine_capacity.
	magazines += new_magazines
	magazines_changed.emit(magazines)

## Adds [param ammo] to the [member current_ammo] and emits [signal ammo_changed].
func restock_ammo(ammo:int = magazine_capacity) -> void:
	current_ammo += ammo
	ammo_changed.emit(current_ammo)

## Sets up [member barrels] so that the weapon can shoot from them in [method _spawn_projectile].
## [br][br]
## If there are any existing barrels and instanced copies of [member sfx_fire], clears them.
## If there are no [Marker2D] in [member barrels], sets one up as a child of [Weapon].
## Instances copies of [member sfx_fire] at every [code]barrel[/code] location.
func configure_barrels() -> void:
	is_configured = true
	current_barrel = 0
	barrels_sfx_fire.clear()
	#print_debug(display_name," found ", barrels.size()," barrels.")
	if barrels.size() == 0:
		var new_marker_2d = Marker2D.new()
		add_child(new_marker_2d)
		barrels.append(new_marker_2d) # So we can access our own basis data.
		if not SceneManager.is_precompiler_running: push_warning("Weapon was configured with no barrels.")
		# Typically if you're shooting from this spot you're inside of your own tank, and it will just instantly collide.
	
	for i in barrels:
		if sfx_fire: ## Set up audio stream players at the barrel points.
			var new_fire_sfx = sfx_fire.duplicate()
			add_child(new_fire_sfx)
			barrels_sfx_fire.append(new_fire_sfx)
			
## Applies all modifications in [member weapon_mods], using the current state
## of the [Weapon] and its properties. This can result in stacking mods' effects.
## [br]TODO cache the initial state maybe. If you want to reset the weapon,
## you can just instantiate a new version of this weapon if it's a saved scene
## --like all our weapons are so far--and then reattach your mods and apply.
func apply_all_mods() -> void:
	for mod in weapon_mods:
		mod.modify_weapon(self)
		
## The argument [param mods] can be an [ModWeapon] or [ModProjectile], as an [Array] or as a singular object.
## [param apply_immediately] can be set [code]false[/code] to only append this mod to [member weapon_mods].
func attach_mods(mods, apply_immediately:bool = true) -> void:
	if mods is Array:
		for mod in mods:
			_attach_new_mod(mod, apply_immediately)
	else:
		_attach_new_mod(mods, apply_immediately)
		
# Internal
func _attach_new_mod(mod, apply:bool) -> void:
	if mod is ModWeapon:
		weapon_mods.append(mod)
		if apply: mod.modify_weapon(self)
	elif mod is ModProjectile:
		projectile_mods.append(mod)

## Directly applies a [ModWeapon]'s effect to this [Weapon] without keeping it in
## [member weapon_mods]. This method will not do anything when provided a [ModProjectile].
func apply_new_mod(mod) -> void:
	push_warning("This method only applies the mod's effects one-shot.
		It does not append a reference to the weapon_mods array property.
		You can ignore if this is intended use.")
	if mod is ModWeapon:
		mod.modify_weapon(self)

## Will stop all [AudioStreamPlayer2D] in [member sounds].
func stop_all_sounds(_only_looping: bool = true) -> void: # TODO args
	for s in sounds:
		if is_instance_valid(s):
			#if it's a looping sound...
			if s.playing: s.stop()
		
## Related to [signal weapon_actions_completed].
## [br]Connects the
## [param projectile]'s
## [signal WeaponProjectile.completed_lifespan]
## and increments an internal counter.
func _add_projectile_awaiting(projectile: WeaponProjectile) -> void:
	active_projectiles.append(projectile)
	projectile.completed_lifespan.connect(_on_projectile_completed_lifespan) # So we know when the projectile is finished.
	_awaiting_lifespan_completion += 1

## Related to [signal weapon_actions_completed].
## [br]Connects the
## [beam projectile]'s
## [signal WeaponNonPhysicalBeam.completed_lifespan]
## and increments an internal counter.
func _add_beam_awaiting(beam: WeaponNonPhysicalBeam) -> void:
	active_projectiles.append(beam)
	beam.completed_lifespan.connect(_on_beam_completed_lifespan)
	_awaiting_lifespan_completion += 1

func _add_node_awaiting(node: Node2D) -> void:
	active_projectiles.append(node)
	node.completed_lifespan.connect(_end_lifespan)
	_awaiting_lifespan_completion += 1
	
## The [Weapon] class doesn't inherently use modes, but components and subclasses can make use of them.
func next_mode() -> void:
	## Or override this for functionality
	#print_debug("Mode changed")
	mode += 1
	if mode >= modes_total:
		mode = 0
	mode_change.emit(mode)
	
## Caches a property-value key-value pair to apply the spawned [member scene_to_spawn] during [method _spawn_projectile].
## You can pass "null" as a value to erase the key and remand behavior to [WeaponProjectile].
func enforce_projectile_property(property, value) -> void:
	if value == null:
		_enforced_projectile_properties.erase(property)
	else:
		_enforced_projectile_properties[property] = value

func get_projectile_instance() -> Object:
	if not _cached_projectile_instance or _cached_projectile_instance == null:
		if scene_to_spawn and scene_to_spawn.can_instantiate():
			_cached_projectile_instance = scene_to_spawn.instantiate()
		else:
			push_error("Can't instantiate scene_to_spawn.")
			_cached_projectile_instance = null
	return _cached_projectile_instance
		
func kill_all_projectiles() -> void:
	for p in active_projectiles:
		if is_instance_valid(p) and p.has_method("destroy"):
			p.destroy()
	
	# clear any previously freed projectiles or those that don't have a destroy method (e.g. Parachute Weapon spawn)
	active_projectiles.clear()
	
## Emits death signals if appropriate and calls [method queue_free].
func destroy() -> void:
	if emit_action_signals: weapon_destroyed.emit(self)
	queue_free()
#endregion

#region Private Methods
## The internal source of shooting. Used by [method shoot], [method shoot_for_duration], & [method shoot_for_count].
func _shoot(power:float = fire_velocity) -> void:
	## Prevented from shooting
	if not is_equipped:
		push_warning("Tried to shoot weapon that is not equipped.")
		return
	if is_cycling: return
	if is_reloading:
		dry_fire()
		cycle()
		return
	if use_ammo == true && current_ammo <= 0:
		dry_fire()
		cycle()
		return ## We can't shoot.
		
	## Shooting
	if not fires_continuously:
		# Play sound effect
		if not barrels_sfx_fire.is_empty(): barrels_sfx_fire[current_barrel].play()
		
		# Determine how many scenes to spawn.
		# This is affected by ammo remaining if ammo is used.
		var scenes_to_spawn:int = number_of_scenes_to_spawn
		if use_ammo:
			if current_ammo < ammo_used_per_shot:
				scenes_to_spawn = maxi(
					1,
					floor(
						lerp(0, number_of_scenes_to_spawn, float(current_ammo) / float(ammo_used_per_shot))
					)
				)
		
		
		# Spawn projectiles
		var scaled_speed := power * power_launch_speed_mult
		for projectile in scenes_to_spawn:
			_spawn_projectile(scaled_speed)
		# Cycle the gun
		cycle()
		
		#print_debug("Weapon %s spawned %s projectiles." % [display_name, scenes_to_spawn])
		
		# Signals
		if emit_action_signals:
			GameEvents.weapon_fired.emit(self)
	else:
		## Alternative handling for continuous weapons
		push_error("Continuous fire is not yet supported.")
		cycle()
		pass
		
	## Counters
	if use_ammo:
		current_ammo -= ammo_used_per_shot ## Clamped in current_ammo setter
		ammo_changed.emit(current_ammo)
	if _shoot_for_count_remaining > 0:
		_shoot_for_count_remaining -= 1
	if _shoot_for_count_remaining == 0 or current_ammo <= 0:
		is_shooting = false
	
## Instances the [member scene_to_spawn], configures critical properties and signals for [WeaponProjectile],
## childs it to the [member GameLevel.container_for_spawnables] or [member SceneManager.current_scene],
## then applies transforms and velocity, making use of [member accuracy_angle_spread]. If there is a
## [member _enforced_projectile_mass], it is applied to the [member WeaponProjectile.mass]. See [method enforce_projectile_property].
func _spawn_projectile(power: float = fire_velocity) -> void:
	var barrel = barrels[current_barrel]
	if scene_to_spawn and scene_to_spawn.can_instantiate():
		var new_shot = scene_to_spawn.instantiate()
		
		var container = SceneManager.get_spawnables_container()
			
		## Enforced projectile properties (used for trajectory previewer)
		for property:String in _enforced_projectile_properties:
			if property as StringName in new_shot:
				if not new_shot.get(property) == _enforced_projectile_properties[property]: # Avoid triggering setters if already equal
					new_shot.set(property, _enforced_projectile_properties[property])
					#print_debug(name, ": Setting property ", property, " to ", _enforced_projectile_properties[property])
		
		if new_shot is WeaponProjectile:
			_setup_new_projectile(new_shot, barrel, power)
		elif new_shot is WeaponNonPhysicalBeam:
			_setup_new_beam(new_shot, barrel)
		else:
			_setup_spawned_scene(new_shot, barrel)
		
		container.add_child(new_shot)
		
		#print_debug("Shot fired with ", velocity, " at ", aim_angle)
		projectile_spawned.emit(new_shot)

## If [member scene_to_spawn] is a [WeaponProjectile], use this method for class-specific setup on the new shot.
func _setup_new_projectile(new_shot: WeaponProjectile, barrel: Marker2D, power: float) -> void:
	new_shot.set_sources(parent_tank,self)
	new_shot.apply_all_mods(projectile_mods)
	_add_projectile_awaiting(new_shot) # Uses signals in class
	new_shot.global_transform = barrel.global_transform # TODO micro offsets might be a good idea for shotguns etc
	
	var aim_angle = barrel.global_rotation
	if accuracy_angle_spread != 0.0:
		var deviation = randf_range(-accuracy_angle_spread,accuracy_angle_spread) / 2
		aim_angle += deviation
		# TODO this should also rotate the object
		
	if new_shot is RigidBody2D and new_shot is not WeaponBeam and new_shot is not WeaponBeam2:
		var velocity = Vector2(power, 0.0)
		new_shot.linear_velocity = velocity.rotated(aim_angle)
		# TODO alternative for other types of objects?
		# Can't think of a specific use yet.

## If [member scene_to_spawn] is a [WeaponNonPhysicalBeam], use this method for class-specific setup on the new shot.
func _setup_new_beam(new_shot: WeaponNonPhysicalBeam, barrel: Marker2D) -> void:
	new_shot.set_sources(parent_tank, self)
	_add_beam_awaiting(new_shot)
	new_shot.global_position = barrel.global_position
	new_shot.aim_angle = barrel.global_rotation

## If [member scene_to_spawn] is another [Node2D], use this method for reflection-based fallback set up
func _setup_spawned_scene(new_shot: Node2D, barrel: Marker2D) -> void:
	if new_shot.has_method("set_sources"):
		new_shot.set_sources(parent_tank, self)
	new_shot.global_transform = barrel.global_transform
	assert(new_shot.has_signal("completed_lifespan"), "new_shot missing required signal - will cause turn to hang!")
	_add_node_awaiting(new_shot)
	
func _on_projectile_completed_lifespan(projectile:WeaponProjectile) -> void:
	_end_lifespan(projectile)

func _on_beam_completed_lifespan(beam: WeaponNonPhysicalBeam) -> void:
	_end_lifespan(beam)

func _end_lifespan(projectile: Node2D) -> void:
	_awaiting_lifespan_completion -= 1
	active_projectiles.erase(projectile)
	
	if not emit_action_signals: return
	if not is_shooting: # Wait til we've fired all our shots this action
		if _awaiting_lifespan_completion < 1:
			weapon_actions_completed.emit(self) # If this doesn't emit, the game turn will be stuck.
			
func _on_weapon_actions_completed(_weapon: Weapon) -> void:
	if sfx_fire_sustain: ## For laser beam specifically right now
		for s in barrels_sfx_fire:
			if is_instance_valid(s):
				if s.playing:
					s.stop()
	if not retain_when_empty:
		if current_ammo < 1:
			if magazines < 1 or not use_magazines:
				destroy()
				
func _on_game_paused(paused:bool) -> void:
	if paused:
		for s in sounds:
			if is_instance_valid(s):
				s.stream_paused = true
	else:
		for s in sounds:
			if is_instance_valid(s):
				s.stream_paused = false
#endregion
