shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_linear;
const int pixel_size = 4;

void fragment() {
	float x = float(int(FRAGCOORD.x) % pixel_size);
	float y = float(int(FRAGCOORD.y) % pixel_size);
	
	x = FRAGCOORD.x + float(float(pixel_size) / 2.0) - x;
	y = FRAGCOORD.y + float(float(pixel_size) / 2.0) - y;
	
	ALBEDO = texture(SCREEN_TEXTURE, vec2(x,y) / VIEWPORT_SIZE).xyz;
}
