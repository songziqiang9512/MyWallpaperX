
varying vec2 v_TexCoord;

uniform sampler2D g_Texture0;
uniform vec2 g_HDRParams;

void main() {
	vec4 albedo = texSample2D(g_Texture0, v_TexCoord);

	float maxHDR = g_HDRParams.y * 2.0;
	albedo.rgb /= maxHDR;
	albedo.rgb = saturate(albedo.rgb);
	albedo.rgb *= maxHDR;

	gl_FragColor = albedo;
}
