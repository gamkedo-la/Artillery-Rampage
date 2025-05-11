class_name WeaponBeam extends WeaponProjectile

var speed = 8

func modulate_enabled() -> bool:
	return false

func is_affected_by_wind() -> bool:
	return false

func _physics_process(_delta: float) -> void:
	super._physics_process(_delta)
	$PhysicsShape.position.x += speed
	$PhysicsShape.scale.x += 2 * speed
	$Destructible.position.x += speed
	$Destructible.scale.x += 2 * speed
	$BeamSprite.position.x += speed
	$BeamSprite.scale.y = $PhysicsShape.scale.x
