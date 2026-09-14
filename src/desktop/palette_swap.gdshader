// Maps an 8-index authoring ramp to live theme colours, with crossfade support.
// Sprites are authored with exact ramp colours (see docs §10); index is looked up
// by nearest ramp colour so imports need no special handling.
shader_type canvas_item;

const int RAMP_SIZE = 8;
uniform vec4 ramp[RAMP_SIZE] : source_color;
uniform vec4 target_colors[RAMP_SIZE] : source_color;
uniform vec4 previous_colors[RAMP_SIZE] : source_color;
uniform float blend : hint_range(0.0, 1.0) = 1.0;
uniform float tolerance : hint_range(0.0, 0.5) = 0.02;

// COLOR already carries TEXTURE * modulate when fragment() runs, so the modulate is
// captured here and re-applied to the replacement colour instead of multiplying the
// authored ramp pixel back in (which darkened every tinted tile).
varying vec4 item_modulate;

void vertex() {
	item_modulate = COLOR;
}

void fragment() {
	vec4 tex = texture(TEXTURE, UV);
	vec4 out_color = tex;
	float best = 1e9;
	int best_index = -1;
	for (int i = 0; i < RAMP_SIZE; i++) {
		float d = distance(tex.rgb, ramp[i].rgb);
		if (d < best) {
			best = d;
			best_index = i;
		}
	}
	if (best_index >= 0 && best < tolerance) {
		vec4 mixed = mix(previous_colors[best_index], target_colors[best_index], blend);
		// The theme's colour, and nothing on top of it. A `music_grade()` used to run here and
		// multiply every swapped pixel by the track's tint and exposure; the owner's ruling took
		// it out, because a grade over the whole frame is a light with nothing casting it. What
		// the music does now it does to the torches (`MusicMoodState`), and a surface is lit by
		// those or by nothing.
		out_color = vec4(mixed.rgb, tex.a * mixed.a);
	}
	COLOR = out_color * item_modulate;
}
