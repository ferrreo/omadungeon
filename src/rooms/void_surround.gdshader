// The surround: everything the camera can see that is not the dungeon.
//
// It used to be one flat colour over a third of the frame, and it read as missing screen
// rather than as somewhere - worst on a light theme, where the void role is a bright block
// with no texture in it at all. This gives it two things to be, both derived from the floor
// itself rather than invented:
//
//   * depth - `depth_map` is a distance field baked from the floor grid (1 on a dungeon tile,
//     falling to 0 `surround_falloff_tiles` away from one), so the dark deepens the further
//     the eye gets from anything built. That is what makes the rooms sit *in* something.
//   * grain - a stable per-cell speckle, so the flat fill has a surface.
//
// Both only ever darken. `COLOR` arrives as the Polygon2D's own colour, which is the floor's
// lit `void` role, and every factor below is <= 1, so the drawn surround is never brighter
// than `FloorRoot.void_color()`. That matters beyond taste: the readability suites measure the
// room's floor colours against `void_color()`, and a surround that can only be darker than it
// makes every one of those measured contrast ratios a lower bound rather than an approximation.
shader_type canvas_item;

/// World-space rect of the floor grid: (x, y, width, height) in pixels.
uniform vec4 grid_rect = vec4(0.0, 0.0, 1.0, 1.0);
/// Distance field over the grid: 1 on the dungeon, 0 far from it. Sampled clamped, so the
/// margin the polygon covers beyond the grid reads the border texel - which is void - and
/// stays at full depth.
uniform sampler2D depth_map : hint_default_black, filter_linear, repeat_disable;
/// How much darker the surround gets where nothing has been built.
uniform float depth_drop : hint_range(0.0, 1.0) = 0.35;
/// What the surround keeps of itself under the lighting layer's dark
/// (`LightingProfile.unlit_floor`; 1.0 when the layer is off).
///
/// The dark is a flat MIX-toward-black `PointLight2D` over the whole floor, and it reaches every
/// tile layer, prop and body - but not this polygon: measured on `lighting_frame` gruvbox, the
/// surround drew #2f2219 with the layer off and #2f2219 with it on, pixel for pixel, while the
/// room beside it went dark. A surround that stays at full brightness in a dungeon lit only by
/// torches is the largest lit-by-nothing area on the screen, which is the exact thing the
/// owner's ruling is about. So the dark is applied here, by hand, rather than hoped for.
uniform float dark : hint_range(0.0, 1.0) = 1.0;
/// Speckle amplitude, and the size of one speckle cell in world pixels.
uniform float grain : hint_range(0.0, 1.0) = 0.08;
uniform float grain_px = 4.0;

varying vec2 world_pos;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 uv = (world_pos - grid_rect.xy) / max(grid_rect.zw, vec2(1.0, 1.0));
	float near = texture(depth_map, uv).r;
	float speck = hash21(floor(world_pos / max(grain_px, 1.0)));
	// No music here either. The surround used to be put through `music_grade()` so it cooled
	// and dimmed with the rooms; the owner's ruling deleted the grade, and the surround is
	// exactly what it says it is - the theme's own `void`, darkened by distance and grain, the
	// dark the torches are read against and never a light of its own.
	COLOR.rgb *= dark * mix(1.0 - depth_drop, 1.0, near) * (1.0 - grain * speck);
}
