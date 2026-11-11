extends RefCounted
## Shared explosion: visuals, sound, falloff damage to characters (blocked by
## walls/cover) and blast damage to destructible props. Used by frag grenades
## and explosive barrels.

const FX = preload("res://scripts/fx/fx.gd")
const Sfx = preload("res://scripts/fx/sfx.gd")
const Layers = preload("res://scripts/core/layers.gd")


## `deal_damage` is false for effect-only copies on other multiplayer peers.
static func detonate(ctx: Node, pos: Vector3, damage: float, radius: float, by: Node, exclude: Array = [], deal_damage: bool = true) -> void:
	if ctx == null or not ctx.is_inside_tree():
		return
	FX.explosion(ctx, pos)
	Sfx.play(ctx, "explosion", pos, 6.0, 0.08)
	var tree := ctx.get_tree()
	var space := (ctx as Node3D).get_world_3d().direct_space_state
	var origin := pos + Vector3.UP * 0.3
	var attacker: Node = by if is_instance_valid(by) else null
	if not deal_damage:
		tree.call_group("camera_rig", "explosion_at", pos)
		return
	var targets: Array = tree.get_nodes_in_group("enemies") + tree.get_nodes_in_group("player")
	for t in targets:
		if not is_instance_valid(t) or t.is_dead:
			continue
		var chest: Vector3 = t.global_position + Vector3(0, 1.0, 0)
		var d := chest.distance_to(origin)
		if d > radius:
			continue
		var q := PhysicsRayQueryParameters3D.create(origin, chest, Layers.WORLD, exclude)
		if not space.intersect_ray(q).is_empty():
			continue
		var k := 1.0 - d / radius
		t.apply_damage(damage * pow(k, 1.3) + 12.0 * k, chest, (chest - origin).normalized(), attacker)
	# props: the blast wrecks whatever it can reach directly
	for p in tree.get_nodes_in_group("destructibles"):
		if not is_instance_valid(p) or p.destroyed:
			continue
		var c: Vector3 = p.center()
		var d := c.distance_to(origin)
		if d > radius + p.extent():
			continue
		var q := PhysicsRayQueryParameters3D.create(origin, c, Layers.WORLD, exclude)
		var hit := space.intersect_ray(q)
		if not hit.is_empty() and hit.collider != p:
			continue
		var k := clampf(1.0 - maxf(d - p.extent(), 0.0) / radius, 0.0, 1.0)
		p.apply_blast(damage * (0.4 + 0.6 * k) * k, origin)
	tree.call_group("enemies", "hear_noise", pos, 40.0)
	tree.call_group("camera_rig", "explosion_at", pos)
