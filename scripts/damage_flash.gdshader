shader_type canvas_item;

// Full-screen red vignette used as a hit-feedback flash. Edges pulse in,
// center stays clear, driven entirely by `intensity` (animate 0 -> 1 -> 0).
uniform vec4 flash_color : source_color = vec4(0.8, 0.0, 0.0, 1.0);
uniform float intensity : hint_range(0.0, 1.0) = 0.0;
uniform float inner_radius : hint_range(0.0, 1.0) = 0.35;
uniform float feather : hint_range(0.01, 1.0) = 0.65;

void fragment() {
	vec2 centered = UV * 2.0 - 1.0;
	float dist = length(centered);
	float edge_alpha = smoothstep(inner_radius, inner_radius + feather, dist);
	COLOR = vec4(flash_color.rgb, edge_alpha * intensity * flash_color.a);
}
