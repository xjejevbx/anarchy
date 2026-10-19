shader_type canvas_item;
// Vent sur la canopée : le bas du sprite (tronc) reste fixe, le haut se balance.
// La phase dépend de la position de l'arbre (ils ne bougent pas tous ensemble) ; une rafale lente module la force.

uniform float amplitude = 0.035;  // part de la hauteur du sprite
uniform float speed = 1.3;

void vertex() {
	vec2 origin = MODEL_MATRIX[3].xy;
	float phase = origin.x * 0.011 + origin.y * 0.007;
	float gust = 0.5 + 0.5 * sin(TIME * 0.35 + origin.x * 0.0015 + origin.y * 0.001);
	float h = clamp(1.0 - UV.y, 0.0, 1.0);
	float sway = sin(TIME * speed + phase) * 0.6 + sin(TIME * speed * 2.3 + phase * 1.7) * 0.25;
	float tex_height = 1.0 / TEXTURE_PIXEL_SIZE.y;
	VERTEX.x += sway * (0.4 + 0.6 * gust) * amplitude * tex_height * h * h;
}
