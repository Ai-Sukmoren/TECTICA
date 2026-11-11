extends Node3D
## Lightweight ballistic debris (shell casings, dropped magazines). Bounces on
## the floor plane and fades out; far cheaper than a RigidBody per casing.

var velocity := Vector3.ZERO
var spin := Vector3.ZERO
var life := 4.0
var radius := 0.01
var bounce_sound := ""
var _bounces := 0
var _fade := 0.6
const Terrain = preload("res://scripts/world/terrain.gd")


func _process(delta: float) -> void:
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if _bounces < 4:
		velocity.y -= 9.8 * delta
		position += velocity * delta
		rotation += spin * delta
		var floor_y := Terrain.height(global_position.x, global_position.z) + radius
		if global_position.y < floor_y:
			global_position.y = floor_y
			if velocity.y < 0.0:
				velocity.y = -velocity.y * 0.32
				velocity.x *= 0.45
				velocity.z *= 0.45
				spin *= 0.4
				_bounces += 1
				if _bounces == 1 and bounce_sound != "":
					preload("res://scripts/fx/sfx.gd").play(self, bounce_sound, global_position, -14.0, 0.25)
				if velocity.y < 0.3:
					_bounces = 4
					rotation.x = 0.0 if absf(rotation.x) < 0.8 else PI * 0.5
	if life < _fade:
		scale = Vector3.ONE * maxf(life / _fade, 0.01)
