class_name ShopWeaponRow extends HBoxContainer

var shop_item:ShopItemResource

@onready var weapon_label: Label = %Weapon
@onready var cost_label: Label = %CostLabel

@onready var weapon_buy_control: WeaponBuyControl = $WeaponBuy
@onready var ammo_purchase_control: AmmoPurchaseControl = $AmmoPurchase

var _weapon:Weapon

signal on_buy_state_changed(weapon: Weapon, buy:bool)
signal on_ammo_state_changed(weapon: Weapon, new_ammo: int, old_ammo: int, cost:int)

func _exit_tree() -> void:
	if is_instance_valid(_weapon):
		_weapon.queue_free()

var enabled:bool:
	get: return weapon_buy_control.enabled or ammo_purchase_control.enabled
	set(value):
		weapon_buy_control.enabled = value
		# TODO: What to do about the ammo control if we could have afforded to buy it
		# Will need to get more granular in the story shop control and cast it to weapon and check individual costs
		ammo_purchase_control.enabled = value

func reset() -> void:
	weapon_buy_control.reset()
	ammo_purchase_control.reset()
		
func _ready() -> void:
	if not shop_item:
		push_error("%s: No shop item set!" % name)
		return
	var player_state := PlayerStateManager.player_state
	if not player_state:
		push_error("%s: No player_state exists!" % name)
		return
	var weapon_scene:PackedScene = shop_item.item_scene
	if not weapon_scene or not weapon_scene.can_instantiate():
		push_error("%s: Invalid weapon scene specified for shop item: %s" % [name, weapon_scene])
		return
	_weapon = weapon_scene.instantiate() as Weapon
	if not _weapon:
		push_error("%s: Invalid weapon scene specified for shop item: %s" % [name, weapon_scene.resource_path])
		return
	
	weapon_label.text = _weapon.display_name
	
	weapon_buy_control.weapon = _weapon
	weapon_buy_control.player_state = player_state
	weapon_buy_control.update()
	
	if weapon_buy_control.already_owned:
		cost_label.text = "(Owned)"
	else:
		cost_label.text = ShopUtils.format_cost(shop_item.unlock_cost,shop_item.unlock_cost_type)
	
	if not _weapon.use_ammo:
		ammo_purchase_control.visible = false
	else:
		ammo_purchase_control.item = shop_item
		ammo_purchase_control.weapon = _weapon
		ammo_purchase_control.initialize()
		
	_connect_signals()
	
func _connect_signals() -> void:
	if weapon_buy_control.enabled:
		weapon_buy_control.buy_button.toggled.connect(func(toggled_on:bool)->void:
			on_buy_state_changed.emit(_weapon, toggled_on)
		)
	
	if ammo_purchase_control.enabled:
		ammo_purchase_control.ammo_updated.connect(func(new_ammo:int, old_ammo:int)->void:
			on_ammo_state_changed.emit(_weapon, new_ammo, old_ammo)
		)
