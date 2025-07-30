class_name ModUtils

#region Savable

static func serialize_mod_array(array) -> Array[Dictionary]:
	var mod_array:Array[Dictionary] = []
	mod_array.resize(array.size())
	for i in array.size():
		mod_array[i] = array[i].serialize()
	
	return mod_array

static func deserialize_mod_array(in_array:Array[Dictionary], out_array, deserializer:Callable):
	for data in in_array:
		var result = deserializer.call(data)
		if result:
			out_array.push_back(result)
	return out_array

#endregion

## Returns true if [param a]'s [ModWeapon.target_weapon_name] is alphabetically above [param b]'s
## corresponding weapon name. If the weapon names match, sorts by property name.
## Accepts both [ModBundle] and [ModWeapon] as arguments. The method will choose the first
## [Weapon] in the ModBundle.
static func sort_by_target_weapon(a, b, ascending:bool = true) -> bool:
	var a_weapon:ModWeapon
	var b_weapon:ModWeapon
	if a is ModBundle:
		a_weapon = a.components_weapon_mods.front()
	elif a is ModWeapon:
		a_weapon = a
	else:
		push_error("Bad paramter. Not a ModBundle or ModWeapon!")
		return false
		
	if b is ModBundle:
		b_weapon = b.components_weapon_mods.front()
	elif b is ModWeapon:
		b_weapon = b
	else:
		push_error("Bad paramter. Not a ModBundle or ModWeapon!")
		return false
	
	if ascending:
		if a_weapon.target_weapon_name == b_weapon.target_weapon_name:
			return a_weapon.property_to_display_string() < b_weapon.property_to_display_string()
		else:
			return a_weapon.target_weapon_name < b_weapon.target_weapon_name
	else:
		if a_weapon.target_weapon_name == b_weapon.target_weapon_name:
			return a_weapon.property_to_display_string() > b_weapon.property_to_display_string()
		else:
			return a_weapon.target_weapon_name > b_weapon.target_weapon_name

#region Mod Flags
static func supported_mods_to_bundle_types(supported_mods_flags:int, num_types:int) -> Array[int]:
	var types:Array[int] = []

	for i in num_types + 1:
		if supported_mods_flags & (1 << i):
			types.push_back(i)
	return types

static func num_supported_mods(supported_mods_flags:int) -> int:
	var count:int = 0
	var flags:int = supported_mods_flags
	
	# Brian Kernighan's algorithm for counting set bits
	while flags != 0:
		flags &= flags - 1
		count += 1
	return count

#endregion
