
## Keeps track of persistent state across rounds
## used in conjunction with setting pending_state on the controller
## prior to adding it to the tree
class_name PlayerState

# Create explicit private variable so we can access in the "destructor" notification
var _weapons: Array[Weapon]
var _all_unlocked_weapon_scenes: Array[String]

var _empty_weapon_cache: Dictionary[String, Weapon] = {}

var weapons: Array[Weapon]:
	set(value):
		# Possible memory leak but we treat player state as immmutable
		if not _weapons.is_empty():
			push_warning("PlayerState: weapons already set - clearing - possible memory leak!")
		_weapons.clear()
		_weapons.resize(value.size())
	# Make sure copy doesn't retain parent reference
		for i in range(value.size()):
			_weapons[i] = value[i].duplicate()
			var w: Weapon = _weapons[i]
			# Remove any parent reference if it was also duplicated
			if w.get_parent():
				w.get_parent().remove_child(w)
			# TODO: Hack to force reconfigure on attach - maybe best to create the state in the weapon itself
			w.barrels.clear()
	get:
		# Explicit function to get a copy as don't want to make expensive copies by default
		return _weapons

var health: float
var max_health: float

func include_unlocks_from(other:PlayerState) -> PlayerState:
	if not other:
		return self
	
	# Retain any unlocked weapons so take union
	for unlock in other._all_unlocked_weapon_scenes:
		if not unlock in _all_unlocked_weapon_scenes:
			_all_unlocked_weapon_scenes.push_back(unlock)

	return self
func get_empty_weapon_if_unlocked(scene_file_path:String) -> Weapon:
	if not scene_file_path in _all_unlocked_weapon_scenes:
		return null
	var weapon:Weapon = _empty_weapon_cache.get(scene_file_path)
	if weapon:
		return weapon
	
	var scene:PackedScene = load(scene_file_path) as PackedScene
	if not scene or not scene.can_instantiate():
		push_error("PlayerState: scene_file_path=%s is not a PackedScene for weapon" % [scene_file_path])
		return null
	weapon = scene.instantiate() as Weapon
	if not scene:
		push_error("PlayerState: scene_file_path=%s -> %s is not a PackedScene for weapon" % [scene, scene_file_path])
		return null

	weapon.current_ammo = 0
	_empty_weapon_cache[scene_file_path] = weapon

	return weapon

func get_weapons_copy() -> Array[Weapon]:
	var copy: Array[Weapon] = []
	copy.resize(weapons.size())
	for i in copy.size():
		copy[i] = _fix_up_magazines(weapons[i].duplicate())
	return copy

func _fix_up_magazines(weapon:Weapon) -> Weapon:
	#HACK: Hack for getting magazine count deserialized correctly for partially filled magazine
	if weapon.use_magazines and weapon.current_ammo > 0 and weapon.current_ammo != weapon.magazine_capacity:
		weapon.magazines += 1
	return weapon

func _notification(what: int) -> void:
	# Cannot access property or self see - https://github.com/godotengine/godot/issues/80834
	if what == NOTIFICATION_PREDELETE:
		for w in _weapons:
			if is_instance_valid(w):
				w.queue_free()
		_weapons.clear()

		for w in _empty_weapon_cache.values():
			if is_instance_valid(w):
				w.queue_free()
		_empty_weapon_cache.clear()

# Don't add to Savable group as this is managed by PlayerStateManager
#region Savable

const SAVE_STATE_KEY:StringName = &"player"

static func delete_save_state(root_state: Dictionary) -> void:
	if root_state:
		root_state.erase(SAVE_STATE_KEY)
		
static func deserialize_from_save_state(root_state: Dictionary) -> PlayerState:
	if not root_state or not root_state.has(SAVE_STATE_KEY):
		print_debug("No save state found")
		return null
	
	var serialized_player_state: Dictionary = root_state[SAVE_STATE_KEY]
	var state:PlayerState = PlayerState.new()

	state.health = serialized_player_state.health
	state.max_health = serialized_player_state.max_health
	
	var _weapons_array:Array[Weapon] = []
	for w in serialized_player_state.weapons:
		if w.has("res"):
			var weapon:Weapon = SaveState.safe_load_scene(w.res) as Weapon
			if weapon:
				weapon.current_ammo = w.ammo
				if w.has("magazines"):
					weapon.magazines = w.magazines
				_weapons_array.push_back(weapon)
			else:
				push_warning("PlayerState: weapon is not valid - skipping")
		else:
			push_warning("PlayerState: weapon does not have res - skipping")
	
	# Don't use setter as it makes a copy and will cause a memory leak!
	state._weapons = _weapons_array

	if serialized_player_state.has("unlocks"):
		state._all_unlocked_weapon_scenes = serialized_player_state["unlocks"].get("weapons", [])
	
	return state

func serialize_save_state(root_state:Dictionary) -> void:
	var serialized_player_state:Dictionary = {}
	serialized_player_state.health = health
	serialized_player_state.max_health = max_health

	var serialized_weapon_state: Array[Dictionary] = []
	
	for w in weapons:
		if is_instance_valid(w):
			var res:String = w.scene_file_path
			if not res in _all_unlocked_weapon_scenes:
				_all_unlocked_weapon_scenes.push_back(res)
			var weapon_state: Dictionary = _create_weapon_state(w)
			serialized_weapon_state.push_back(weapon_state)
		else:
			push_warning("PlayerState: weapon is not valid - skipping")

	serialized_player_state.weapons = serialized_weapon_state
	serialized_player_state.unlocks = {
		weapons = _all_unlocked_weapon_scenes
	}
	root_state[SAVE_STATE_KEY] = serialized_player_state

func _create_weapon_state(weapon: Weapon) -> Dictionary:
	var weapon_state: Dictionary = {}

	weapon_state.res = weapon.scene_file_path
	weapon_state.ammo = weapon.current_ammo
	if weapon.use_magazines:
		weapon_state.magazines = weapon.magazines

	return weapon_state

#endregion

func duplicate() -> PlayerState:
	# Duplicate with a serialization clone since RefCounted doesn't support duplicate natively
	var root_state:Dictionary = {}

	serialize_save_state(root_state)
	return deserialize_from_save_state(root_state)
