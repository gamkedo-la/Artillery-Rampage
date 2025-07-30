class_name PlayerUpgradesClass extends Node # Autoload

## Emitted for each upgrade whenever the player acquires a new upgrade.
## Primarily used to get a display name for UI (mod_bundle.name).
signal acquired_upgrade(mod:ModBundle)
signal upgrades_changed() ## Futureproof for deleting/changing upgrades

var current_upgrades:Array[ModBundle]
var _dirty:bool

@onready var acquired_upgrade_sound: AudioStreamPlayer = %AcquiredUpgradeSound

func _ready() -> void:
	GameEvents.play_mode_changed.connect(_on_play_mode_changed)

func get_current_upgrades() -> Array[ModBundle]:
	return current_upgrades

func apply_all_upgrades(weapons: Array[Weapon]) -> void:
	for bundle in current_upgrades:
		bundle.apply_all_mods(weapons)

func acquire_upgrade(mod_bundle:ModBundle) -> void:
	if not mod_bundle:
		return
	acquired_upgrade_sound.play()
	_on_acquired_upgrade(mod_bundle)
	
func remove_upgrade_and_get_scrap_value(mod_bundle:ModBundle) -> int:
	if mod_bundle in current_upgrades:
		print_debug("Removed an upgrade: %s" % [mod_bundle._to_string()])
		current_upgrades.erase(mod_bundle)
		
	return mod_bundle.get_scrap_value()

func _on_acquired_upgrade(mod_bundle:ModBundle) -> void:
	print_debug("Acquired upgrade")
	_dirty = true

	current_upgrades.append(mod_bundle)
	
	acquired_upgrade.emit(mod_bundle)
	upgrades_changed.emit()

func _on_play_mode_changed(old_mode:SceneManager.PlayMode, new_mode: SceneManager.PlayMode) -> void:
	if old_mode == SceneManager.PlayMode.STORY:
		print_debug("%s: Reset upgrades after leaving story mode %s -> %s" \
			% [name, EnumUtils.enum_to_string(SceneManager.PlayMode, old_mode), EnumUtils.enum_to_string(SceneManager.PlayMode, new_mode)])
		clear()

func clear() -> void:
	current_upgrades.clear()
	_dirty = false
	upgrades_changed.emit()

#region Savable

const SAVE_STATE_KEY:StringName = &"PlayerUpgrades"

func restore_from_save_state(save: SaveState) -> void:
	if SceneManager.play_mode != SceneManager.PlayMode.STORY:
		return

	current_upgrades.clear()

	var story_save:Dictionary = StorySaveUtils.get_story_save(save)
	if SaveStateManager.consume_state_flag(SceneManager.new_story_selected, SAVE_STATE_KEY) or not story_save or not story_save.has(SAVE_STATE_KEY):
		print_debug("PlayerUpgrades: New Story - clearing upgrades")
		_dirty = true
		return

	var upgrade_state:Dictionary = story_save[SAVE_STATE_KEY]
	var current_upgrade_data:Array[Dictionary] = upgrade_state.get("upgrades", [])

	for data in current_upgrade_data:
		var result:ModBundle = ModBundle.deserialize(data)
		if result:
			current_upgrades.push_back(result)
		else:
			push_warning("PlayerUpgrades: Save data entry deserialized to null")

	print_debug("PlayerUpgrades: Restored %d upgrades - %s" % [current_upgrade_data.size(), current_upgrade_data])


func update_save_state(save:SaveState) -> void:
	if not _dirty or SceneManager.play_mode != SceneManager.PlayMode.STORY:
		return

	var story_save:Dictionary = StorySaveUtils.get_story_save(save)
	if not story_save:
		return

	var upgrade_state:Dictionary = {}
	var current_upgrade_data:Array[Dictionary] = []
	current_upgrade_data.resize(current_upgrades.size())

	for i in current_upgrades.size():
		current_upgrade_data[i] = current_upgrades[i].serialize()

	upgrade_state["upgrades"] = current_upgrade_data
	story_save[SAVE_STATE_KEY] = upgrade_state

#endregion


static func generate_random_upgrade(types:Array[ModBundle.Types], layers:int = 1, chance_bias:int = 0) -> ModBundle:
	var player_state:PlayerState = PlayerStateManager.player_state
	if not player_state:
		push_error("PlayerUpgrades: No player state available to determine available inventory to apply the generate mod bundle to")
		return null

	var weapons_inventory:Array[Weapon] = player_state.weapons
	if not weapons_inventory:
		push_error("PlayerUpgrades: Player state has empty weapons!")
		return null

	var selected_weapon:Weapon = _get_random_weighted_weapon(weapons_inventory)
	if not selected_weapon:
		push_warning("PlayerUpgrades: No available weapons with mods enabled")
		return null

	# select a random weapon to apply the upgrades to if there is a ModWeapon
	var upgrade = ModBundle.new()
	# More than 1 layer means multiple Mods in a ModBundle. Use for 'rarity'.
	# Chance bias pushes the probability more toward buff or de-buff. Use for shop
	upgrade.randomize(types, layers, false, chance_bias, selected_weapon.supported_mods)

	if upgrade.components_weapon_mods:
		for weapon_mod in upgrade.components_weapon_mods:
			print_debug("PlayerUpgrades: Applying weapon mod to %s" % selected_weapon.display_name)
			weapon_mod.target_weapon_name = selected_weapon.display_name
			weapon_mod.target_weapon_scene_path = selected_weapon.scene_file_path
		return upgrade
	return null

static func _get_random_weighted_weapon(weapons_inventory: Array[Weapon]) -> Weapon:
	var weapon_weights := _get_weapon_mod_weights(weapons_inventory)
	
	var total_weight:int = 0
	for weight in weapon_weights:
		total_weight += weight
	
	if total_weight == 0:
		push_warning("PlayerUpgrades: No weapons have any mods enabled!")
		return null

	var selected_weight_upper_bound:int = randi_range(1, total_weight)

	var selected_weapon:Weapon = null
	var weight_sum:int = 0
	for i in weapons_inventory.size():
		var weight:int = weapon_weights[i]
		weight_sum += weight
		if weight_sum >= selected_weight_upper_bound:
			selected_weapon = weapons_inventory[i]
			break
	
	return selected_weapon

static func _get_weapon_mod_weights(weapons_inventory: Array[Weapon]) -> PackedInt32Array:
	var weapon_weights:PackedInt32Array = []
	weapon_weights.resize(weapons_inventory.size())

	for i in weapon_weights.size():
		var weapon:Weapon = weapons_inventory[i]
		weapon_weights[i] = ModUtils.num_supported_mods(weapon.supported_mods)
	return weapon_weights
