extends "res://tests/previews/fp_arms_preview.gd"
## Reuse the gameplay camera capture with a fixed review resolution, without
## saving or changing the player's display settings.
func shot(out: String, tag: String) -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = Vector2i(1280, 720)
	await super.shot(out, tag)
