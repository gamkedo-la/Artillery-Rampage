class_name ModDisplayPanel extends Control

var mods:Array:
	set(value):
		mods = value
		configure_from_mods()

var confirming:bool = false

@onready var everything: VBoxContainer = %Everything

@onready var header_label: Label = %HeaderLabel
@onready var header_sublabel: Label = %HeaderSublabel

@onready var display_property: Label = %Property
@onready var display_operation: Label = %Operation
@onready var display_value: Label = %Value

@onready var hide_timer: Timer = %HideTimer
@onready var buttons: VBoxContainer = %Buttons
@onready var delete: Button = %Delete
@onready var cancel: Button = %Cancel
@onready var confirm: Button = %Confirm
@onready var confirm_label: Label = %ConfirmLabel


func _enter_tree() -> void:
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)

func _ready() -> void:
	buttons.hide()
	delete.show()
	cancel.hide()
	confirm.hide()
	confirm_label.hide()
	
	if not mods.is_empty():
		configure_from_mods()
	else:
		push_warning("ModDisplayPanel: Mods not configured before ready.")
	
func configure_from_mods() -> void:
	for mod in mods:
		if mod is ModWeapon:
			header_label.text = mod.target_weapon_name
			#header_sublabel.text =
			display_property.text = mod.property_to_display_string()
			display_operation = mod.operation_to_display_string()
			display_value = mod.get_property_value_to_string()
		if mod is ModProjectile:
			# Find the appropriate weapon and display it
			pass
	
func exchange_mod_for_scrap() -> void:
	print("Foo!")
	# TASK
	queue_free()
	
func toggle_buttons(to_confirm:bool = true) -> void:
	if to_confirm:
		confirming = true
		delete.hide()
		# Are you sure?
		confirm_label.show()
		cancel.show()
		confirm.show()
	else:
		confirming = false
		delete.show()
		# Are you sure?
		confirm_label.hide()
		cancel.hide()
		confirm.hide()

func _on_mouse_entered() -> void:
	hide_timer.stop()
	buttons.show()
	
func _on_mouse_exited() -> void:
	hide_timer.start()


func _on_delete_pressed() -> void:
	toggle_buttons(true)

func _on_cancel_pressed() -> void:
	toggle_buttons(false)

func _on_confirm_pressed() -> void:
	toggle_buttons(false)
	delete.disabled = true
	
	exchange_mod_for_scrap() # Expecting to queue free


func _on_hide_timer_timeout() -> void:
	toggle_buttons(false)
	buttons.hide()
