
varying vec2 v_TexCoord;

uniform sampler2D g_Texture0;

// Proper gamma conversion http://chilliant.blogspot.com/2012/08/srgb-approximations-for-hlsl.html
vec3 lin(vec3 v)
{
	vec3 c = step(0.04045, v);
	return c * (pow((v + 0.055) / 1.055, CAST3(2.4))) + (1.0 - c) * (v / 12.92);
}

void main() {
	vec4 albedo = texSample2D(g_Texture0, v_TexCoord);
	albedo.rgb = lin(albedo.rgb);

	gl_FragColor = albedo;
}
