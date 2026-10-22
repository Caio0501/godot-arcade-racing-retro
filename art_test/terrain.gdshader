shader_type spatial;
// Terreno estilizado: cor por vértice (grama/terra/areia) com variação de
// ruído em espaço de mundo para quebrar a uniformidade.

uniform sampler2D detail_noise : filter_linear_mipmap, repeat_enable;
uniform float detail_scale = 0.08;
uniform float detail_strength = 0.18;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n1 = texture(detail_noise, world_pos.xz * detail_scale).r;
	float n2 = texture(detail_noise, world_pos.xz * detail_scale * 4.3).r;
	float n = mix(n1, n2, 0.4);
	// Cores de vértice são definidas em sRGB no script.
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * (1.0 + (n - 0.5) * 2.0 * detail_strength);
	ROUGHNESS = 0.95;
	SPECULAR = 0.2;
}
