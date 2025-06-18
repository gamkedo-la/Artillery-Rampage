class_name Juice

## Contains floats to be used as durations for various effects, and helper methods
## for animating parameters with tweens (see [Tween]).
## The tweens made by these methods run even if the [SceneTree] is paused.

const SNAP = 0.2
const SNAPPY = 0.3
const FAST = 0.45
const SMOOTH = 0.7
const PATIENT = 0.9
const SLOW = 1.5
const LONG = 3.5
const VERYLONG = 7.0

## Linearly animates [member CanvasItem.modulate] from [param from] to [member Color.WHITE].
static func fade_in(node, speed:float = SNAPPY, from:Color = Color.TRANSPARENT) -> Tween:
	var tween:Tween = node.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(node, "modulate", Color.WHITE, speed).from(from)
	return tween

## Linearly animates [member CanvasItem.modulate] from the current value to [param to], which is
## [member Color.TRANSPARENT] by default.
static func fade_out(node, speed:float = SMOOTH, to:Color = Color.TRANSPARENT) -> Tween:
	var tween:Tween = node.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(node, "modulate", to, speed)
	return tween

## Fades [member CanvasItem.modulate] from the current value to [param to] with
## transition and ease types available to be set.
## By default, the [member Tween.TransitionType.TRANS_SINE] type is used,
## instead of [b]Linear[/b], and no easing is applied.
static func advanced_fade(
	node,
	speed:float = SMOOTH,
	to:Color = Color.TRANSPARENT,
	trans:Tween.TransitionType = Tween.TransitionType.TRANS_SINE,
	easing = null
	) -> Tween:

	var tween:Tween = node.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.set_trans(trans)
	if easing is Tween.EaseType:
		tween.set_ease(easing)

	tween.tween_property(node, "modulate", to, speed)

	return tween
