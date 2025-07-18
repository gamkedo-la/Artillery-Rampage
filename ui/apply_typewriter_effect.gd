class_name ApplyTypewriterEffect extends Node

@export var apply_to:Node ## The node to apply this effect to. If empty, the parent is used.
@export var connect_to_events:bool = true ## Will react to visibility changes to the [member apply_to] node.

var effect:TypewriterEffect.TypewriterTextRevealer
var cached_text:String

# Needed for when we duplicate a node and the parent was derived instead of explicitly set
# In that case we want to always replace it on ready
var _derived_apply_to:bool

func _ready() -> void:
	if not apply_to or _derived_apply_to:
		apply_to = get_parent()
		_derived_apply_to = true

	if connect_to_events:
		if apply_to is CanvasItem:
			apply_to.visibility_changed.connect(_on_visibility_changed)

func run() -> void:
	stop()
	effect = TypewriterEffect.apply_to(apply_to)
	
func stop() -> void: if effect: effect.kill()

func _on_visibility_changed() -> void:
	if apply_to.visible: run()
	else: stop()
