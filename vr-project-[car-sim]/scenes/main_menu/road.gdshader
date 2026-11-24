shader_type spatial;
// Simple procedural road: asphalt, white edge lines and a dashed center line.
// Expects a PlaneMesh whose size matches road_width x road_length.

uniform vec4 asphalt_color : source_color = vec4(0.17, 0.18, 0.21, 1.0);
uniform vec4 center_line_color : source_color = vec4(1.0, 0.8, 0.2, 1.0);
uniform vec4 edge_line_color : source_color = vec4(0.92, 0.92, 0.92, 1.0);
uniform float road_width = 8.0;
uniform float road_length = 400.0;
uniform float line_width = 0.18;
uniform float dash_length = 3.0;
uniform float edge_inset = 0.4;

void fragment() {
	// Position on the road in meters.
	vec2 m = vec2((UV.x - 0.5) * road_width, UV.y * road_length);
	float d = abs(m.x);
	float dash = step(fract(m.y / (dash_length * 2.0)), 0.5);
	float center = step(d, line_width * 0.5) * dash;
	float edge_start = road_width * 0.5 - edge_inset - line_width;
	float edge = step(edge_start, d) * step(d, edge_start + line_width);

	vec3 color = asphalt_color.rgb;
	color = mix(color, edge_line_color.rgb, edge);
	color = mix(color, center_line_color.rgb, center);
	ALBEDO = color;
	ROUGHNESS = mix(0.92, 0.6, max(edge, center));
}
