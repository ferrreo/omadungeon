// Flattens whatever this node draws to a single colour, keeping only the alpha. Used by
// SpriteOutline to stamp a character's current frame as a rim: the rim has to survive a hit
// flash that has already bleached the sprite itself, so it cannot be a tinted copy.
shader_type canvas_item;

uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	COLOR = vec4(tint.rgb, COLOR.a * tint.a);
}
