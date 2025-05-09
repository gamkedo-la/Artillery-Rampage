class_name ModBundle extends Resource

## This class is a nice way to package upgrading things the player has. The weapon,
## the weapon's projectile, the tank, they all have different classes, and
## different tweakable properties. This class should be able to have a component of
## each available aspect of the player's control that we want to upgrade through
## game progression.
@export var display_name:String = "Mystery"
var display_name_components:Dictionary
@export_group("Components", "component_")
@export var components_weapon_mods:Array[ModWeapon]
@export var components_projectile_mods:Array[ModProjectile]
## ideas
#@export var component_tank_mods:Array[ModTank]
#@export var component_player_mods:Array[ModPlayer]
#@export var component_world_mods:Array[ModWorld]

enum Types{
	ANY,
	WEAPON,
	PROJECTILE,
	#TANK,
	#PLAYER,
	#WORLD,
}

var target_weapon:String:
	get():
		var names:String = ""
		for mod in components_weapon_mods:
			if names.is_empty():
				names = mod.target_weapon_name
			else:
				names = names + ", " + mod.target_weapon_name
		return names

## apply mods where they need to go
## weapons hold projectile mods to apply at spawn time
## Player is not used but retained parameter to not break existing code at this time
func apply_all_mods(_player:Player, weapons:Array[Weapon]) -> void:
	for mod in components_weapon_mods:
		for weapon in weapons:
			if mod.target_weapon_name.to_lower() == weapon.display_name.to_lower(): # this is lousy
				weapon.apply_mod(mod)

## Was looking for the most efficient random bool method and came across a discussion;
## I appreciated this method proposed by a contributor.
## -- This method via Chaosus on Github Godot issues #8721
func chance(probability: int = 50) -> bool: return true if (randi() % 100) < probability else false

func randomize(selectable_types:Array[ModBundle.Types], number_of_mods:int = 1, clearall:bool = true) -> void:
	if clearall: clear_all()
	
	for i in number_of_mods:
		var mod # Could be any mod type
		var type_rand:int = randi_range(0, selectable_types.size())
		var type = selectable_types[type_rand]
		
		if type == Types.ANY:
			type = randi_range(1, Types.size()) as Types # Pick one
		
		match type:
			Types.WEAPON:
				mod = _new_rand_mod_weapon()
				components_weapon_mods.append(mod)
			Types.PROJECTILE:
				mod = _new_rand_mod_projectile()
				components_projectile_mods.append(mod)
			#Types.TANK:
				#pass
			#Types.PLAYER:
				#pass
			#Types.WORLD:
				#pass
			_:
				mod = null
	pass
	
func clear_all() -> void:
	components_weapon_mods.clear()
	components_projectile_mods.clear()
	#component_tank_mods.clear()
	#component_player_mods.clear()
	#component_world_mods.clear()

func _new_rand_mod_weapon() -> ModWeapon:
	var mod = ModWeapon.new()
	var type:int = randi_range(0, 5)
	var buff:bool # Buff or debuff. Probability is set per type.
	
	match type:
		0:
			## Accuracy
			mod.property = ModWeapon.Modifiables.ACCURACY_ANGLE_SPREAD
			buff = chance(75)
			if buff:
				mod.operation = ModWeapon.Operations.MULTIPLY
				mod.value = randf_range(randfn(0.5, 0.25), 0.95)
				_add_to_display_name_components("Reduce Spread", mod.value)
			else:
				mod.operation = ModWeapon.Operations.ADD
				mod.value = randf_range(PI/36, PI/9)
				_add_to_display_name_components("Increase Spread", mod.value)
		1:
			## Number of bullets to spawn.
			## This is for MG (serial shooting) behavior.
			mod.property = ModWeapon.Modifiables.ALWAYS_SHOOT_FOR_COUNT
			buff = chance(80)
			if buff:
				mod.operation = ModWeapon.Operations.ADD
				mod.value = randi_range(1,randi_range(1,5))
				_add_to_display_name_components("More Shots", mod.value)
			else:
				mod.operation = ModWeapon.Operations.MULTIPLY
				mod.value = randf_range(0.52, 0.9)
				_add_to_display_name_components("Fewer Shots", mod.value)
		2:
			## Number of bullets to spawn.
			## This is for shotgun (parallel shooting) behavior.
			mod.property = ModWeapon.Modifiables.NUMBER_OF_SCENES_TO_SPAWN
			buff = chance(80)
			if buff:
				mod.operation = ModWeapon.Operations.ADD
				mod.value = randi_range(1,randi_range(1,5))
				_add_to_display_name_components("More Projectiles", mod.value)
			else:
				mod.operation = ModWeapon.Operations.MULTIPLY
				mod.value = randf_range(0.52, 0.9)
				_add_to_display_name_components("Fewer Projectiles", mod.value)
		3:
			## Projectile shooting velocity.
			mod.property = ModWeapon.Modifiables.POWER_LAUNCH_SPEED_MULT
			mod.operation = ModWeapon.Operations.MULTIPLY
			buff = chance(80)
			if buff:
				mod.value = randf_range(randfn(0.25,0.25),0.99)
				_add_to_display_name_components("Increase Max Power", mod.value)
			else:
				mod.value = randf_range(randfn(2.5, 0.5),randfn(8.5,4.0))
				_add_to_display_name_components("Reduce Max Power", mod.value)
		4:
			## Keep this weapon even when out of ammo.
			mod.property = ModWeapon.Modifiables.RETAIN_WHEN_EMPTY
			buff = true
			if buff:
				mod.operation = ModWeapon.Operations.SET_TRUE # Retain when out of ammo
				# mod.value not needed
				_add_to_display_name_components("Retain when Empty", true)
			else:
				mod.operation = ModWeapon.Operations.SET_FALSE # Discard when out of ammo
				# mod.value not needed
				_add_to_display_name_components("Retain when Empty", false)
		5:
			## Infinite Ammo
			mod.property = ModWeapon.Modifiables.USE_AMMO
			buff = chance(90)
			if buff:
				mod.operation = ModWeapon.Operations.SET_FALSE # Infinite ammo
				# mod.value not needed
				_add_to_display_name_components("Requires Ammunition", false)
			else:
				mod.operation = ModWeapon.Operations.SET_TRUE # Noninfinite ammo
				# mod.value not needed
				_add_to_display_name_components("Requires Ammunition", true)
	
	return mod

func _new_rand_mod_projectile() -> ModProjectile:
	var mod = ModProjectile.new()
	#TODO
	push_error("Not implemented")
	return mod

func _add_to_display_name_components(name:String, value) -> void:
	if display_name_components[name]:
		display_name_components[name] += value
	else: display_name_components[name] = value
