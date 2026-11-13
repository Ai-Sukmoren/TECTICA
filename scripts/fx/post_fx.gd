extends CanvasLayer
## Full-screen lens pass under the HUD: film grain, chromatic aberration and
## desaturation that react to damage / low health.

var grain := 0.012
var aberration := 0.0
var desaturate := 0.0
## Night vision 0..1 (green phosphor, tube vignette, noise).
var nvg := 0.0
var _rect: ColorRect
var _mat: ShaderMaterial
var _t := 0.0
var _crt_layer: CanvasLayer
var _crt: ColorRect
var _crt_mat: ShaderMaterial

const CRT_SHADER := """
shader_type canvas_item;
// Retro CRT pass drawn ABOVE the HUD: scanlines, phosphor triads,
// vignette and a faint rolling flicker band. Reads no screen texture.
uniform float time_s = 0.0;
uniform float strength = 1.0;
void fragment() {
	vec2 px = FRAGCOORD.xy;
	float line = 0.5 + 0.5 * sin(px.y * 3.14159 * 0.5);          // 4-px period scanlines
	float scan = mix(1.0, 0.0, pow(line, 2.0)) * 0.20;
	int col = int(mod(px.x, 3.0));
	vec3 mask = col == 0 ? vec3(1.0, 0.0, 0.0) : (col == 1 ? vec3(0.0, 1.0, 0.0) : vec3(0.0, 0.0, 1.0));
	vec2 uv = SCREEN_UV - 0.5;
	float vig = smoothstep(0.42, 0.85, length(uv * vec2(1.0, 0.82)));
	float band = smoothstep(0.0, 0.06, abs(fract(SCREEN_UV.y * 0.6 - time_s * 0.07) - 0.5) - 0.44);
	float dark = scan + vig * 0.4 + (1.0 - band) * 0.02;
	// tint: subtract a little of the other channels -> faint RGB triad
	vec3 tint = (vec3(1.0) - mask) * 0.035;
	COLOR = vec4(tint, clamp(dark * strength, 0.0, 0.9));
}
"""


func _ready() -> void:
	layer = 1
	process_mode = Node.PROCESS_MODE_ALWAYS
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float grain = 0.012;
uniform float aberration = 0.0;
uniform float desaturate = 0.0;
uniform float time_s = 0.0;
uniform float nvg = 0.0;
float rand(vec2 co) { return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - 0.5;
	float ab = (aberration * 0.009) * length(dir) * 2.0;
	vec3 col;
	col.r = texture(screen_tex, uv + dir * ab).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - dir * ab).b;
	float l = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(l), desaturate);
	float n = rand(floor(uv * vec2(960.0, 540.0)) + fract(time_s * 7.0)) - 0.5;
	col += n * grain;
	if (nvg > 0.0) {
		// image intensifier: luminance only, highlights compressed so lamps and
		// muzzle flashes bloom instead of whiting out, green P43 phosphor
		float y = dot(col, vec3(0.3, 0.59, 0.11));
		y = y / (y + 0.45) * 1.45;
		float sn = rand(floor(uv * vec2(640.0, 360.0)) + fract(time_s * 13.0)) - 0.5;
		y += sn * 0.09;                                                  // sensor noise
		y *= 0.93 + 0.07 * sin(uv.y * 900.0);                            // faint scan lines
		vec3 g = vec3(0.22, 1.0, 0.42) * y + vec3(0.0, 0.025, 0.01);
		// tube vignette: a soft circle, the edges fall to black
		vec2 d = (uv - 0.5) * vec2(1.6, 1.0);
		g *= 1.0 - smoothstep(0.45, 0.62, length(d));
		col = mix(col, g, nvg);
	}
	COLOR = vec4(col, 1.0);
}
"""
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_rect = ColorRect.new()
	_rect.material = _mat
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_rect)
	_crt_layer = CanvasLayer.new()
	_crt_layer.layer = 50
	add_child(_crt_layer)
	var csh := Shader.new()
	csh.code = CRT_SHADER
	_crt_mat = ShaderMaterial.new()
	_crt_mat.shader = csh
	_crt = ColorRect.new()
	_crt.material = _crt_mat
	_crt.set_anchors_preset(Control.PRESET_FULL_RECT)
	_crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crt_layer.add_child(_crt)


func _process(delta: float) -> void:
	_t += delta
	# Avoid copying and sampling the screen when all lens effects are off.
	_rect.visible = grain > 0.0 or aberration > 0.0 or desaturate > 0.0 or nvg > 0.0
	_mat.set_shader_parameter("nvg", nvg)
	_mat.set_shader_parameter("grain", grain)
	_mat.set_shader_parameter("aberration", aberration)
	_mat.set_shader_parameter("desaturate", desaturate)
	_mat.set_shader_parameter("time_s", _t)
	var crt_on := bool(preload("res://scripts/core/settings.gd").v.get("retro_crt", false))
	_crt.visible = crt_on
	if crt_on:
		_crt_mat.set_shader_parameter("time_s", _t)
