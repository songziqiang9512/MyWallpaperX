#include "common_fragment.h"

uniform vec4 g_Color4;

uniform sampler2D g_Texture0;
uniform vec4 g_Texture0Resolution;
uniform sampler2D g_Texture1;

uniform vec4 g_RenderVar0;
uniform vec4 g_RenderVar1;
uniform vec4 g_RenderVar2;
uniform vec4 g_RenderVar3;

varying vec2 v_TexCoord;

#define MSDF_RANGE g_RenderVar0.x
#define OUTLINE_WIDTH g_RenderVar0.y
#define BLUR_RADIUS g_RenderVar0.z
#define DROP_SHADOW_RADIUS g_RenderVar0.w

#define OUTLINE_COLOR g_RenderVar1.xyz
#define DROP_SHADOW_COLOR g_RenderVar2.xyz
#define DROP_SHADOW_OFFSET vec2(g_RenderVar1.w, g_RenderVar2.w)
#define DROP_SHADOW_OPACITY g_RenderVar3.x

float median(float r, float g, float b)
{
	return max(min(r, g), min(max(r, g), b));
}

vec2 sqr(vec2 x) { return x*x; }

float ScreenPxRange(vec2 texCoord)
{
	vec2 unitRange = CAST2(MSDF_RANGE)/g_Texture0Resolution.xy;
	// If inversesqrt is not available, use vec2(1.0)/sqrt
	vec2 screenTexSize = CAST2(1.0) / sqrt(sqr(ddx(texCoord))+sqr(ddy(texCoord)));
	// Can also be approximated as screenTexSize = vec2(1.0)/fwidth(texCoord);
	return max(0.5*dot(unitRange, screenTexSize), 1.0);
}

float GetMsdfDistance(vec3 msdf, vec2 texCoord)
{
	float sd = median(msdf.r, msdf.g, msdf.b);
	return ScreenPxRange(texCoord.xy)*(sd - 0.5);
}

float GetAtlasMsdfDistance(vec3 msdf)
{
	float sd = median(msdf.r, msdf.g, msdf.b);
	return MSDF_RANGE * (sd - 0.5);
}

float SampleMSDF(float msdfDistance, float threshold, float blurRadius)
{
#if BLUR_ENABLED || DROP_SHADOW_ENABLED
	float halfWidth = max(blurRadius, 0.5);
	return smoothstep(-halfWidth, halfWidth, msdfDistance + threshold - 0.5);
#else
	return clamp(msdfDistance + threshold, 0.0, 1.0);
#endif
}

vec4 ApplyOutline(float msdfDistance, float fillCoverage, float outlineWidth, float blurRadius, vec3 fillColor, float baseAlpha)
{
#if OUTLINE_ENABLED
	float outlineCoverage = SampleMSDF(msdfDistance, 0.5 + outlineWidth, blurRadius);
	return vec4(mix(OUTLINE_COLOR, fillColor, fillCoverage), outlineCoverage * baseAlpha);
#else
	return vec4(fillColor, fillCoverage * baseAlpha);
#endif
}

vec4 ApplyDropShadow(vec4 glyphFrag, vec2 texCoord)
{
#if DROP_SHADOW_ENABLED
	vec2 offsetUV = DROP_SHADOW_OFFSET / g_Texture0Resolution.xy;
	vec2 shadowTexCoord = texCoord - offsetUV;
	vec3 shadowMsdf = texSample2D(g_Texture0, shadowTexCoord).rgb;
	float shadowAtlasDistance = GetAtlasMsdfDistance(shadowMsdf);
#if OUTLINE_ENABLED
	float shadowThreshold = 0.5 + OUTLINE_WIDTH;
#else
	float shadowThreshold = 0.5;
#endif
	float shadowAlpha = saturate(DROP_SHADOW_OPACITY * SampleMSDF(shadowAtlasDistance, shadowThreshold, DROP_SHADOW_RADIUS)) * g_Color4.a;

	float outAlpha = glyphFrag.a + shadowAlpha * (1.0 - glyphFrag.a);
	vec3 outRGB = (glyphFrag.rgb * glyphFrag.a + DROP_SHADOW_COLOR * shadowAlpha * (1.0 - glyphFrag.a)) / max(outAlpha, 1e-6);
	return vec4(outRGB, outAlpha);
#else
	return glyphFrag;
#endif
}

/*

float BEZEL_SAMPLE_RADIUS = 1;
vec2 dxUV = vec2(BEZEL_SAMPLE_RADIUS, 0.0) / g_Texture0Resolution.xy;
vec2 dyUV = vec2(0.0, BEZEL_SAMPLE_RADIUS) / g_Texture0Resolution.xy;

vec3 msdfRight = texSample2D(g_Texture0, v_TexCoord.xy + dxUV).rgb;
vec3 msdfLeft  = texSample2D(g_Texture0, v_TexCoord.xy - dxUV).rgb;
vec3 msdfUp    = texSample2D(g_Texture0, v_TexCoord.xy + dyUV).rgb;
vec3 msdfDown  = texSample2D(g_Texture0, v_TexCoord.xy - dyUV).rgb;

float sdRight = median(msdfRight.r, msdfRight.g, msdfRight.b);
float sdLeft  = median(msdfLeft.r,  msdfLeft.g,  msdfLeft.b);
float sdUp    = median(msdfUp.r,    msdfUp.g,    msdfUp.b);
float sdDown  = median(msdfDown.r,  msdfDown.g,  msdfDown.b);

vec2 bezel = vec2(sdRight - sdLeft, sdUp - sdDown) * 5;
float light = dot(vec2(0.707, 0.707), bezel) * 0.5 + 0.5;
*/

void main() {
#if MSDF // SDF scaling
	vec3 msdf = texSample2D(g_Texture0, v_TexCoord.xy).rgb;

#if BLUR_ENABLED
	float msdfDistance = GetAtlasMsdfDistance(msdf);
	float outlineWidth = OUTLINE_WIDTH;
	float blurRadius = BLUR_RADIUS;
#else
	float msdfDistance = GetMsdfDistance(msdf, v_TexCoord.xy);
	float outlineWidth = OUTLINE_WIDTH * (ScreenPxRange(v_TexCoord.xy) / MSDF_RANGE);
	float blurRadius = 0.0;
#endif

	float opacity = SampleMSDF(msdfDistance, 0.5, blurRadius);

#if COLORFONT
	vec3 color = texSample2D(g_Texture1, v_TexCoord.xy).rgb;
	gl_FragColor = ApplyOutline(msdfDistance, opacity, outlineWidth, blurRadius, color, g_Color4.a);
#else
	gl_FragColor = ApplyOutline(msdfDistance, opacity, outlineWidth, blurRadius, g_Color4.rgb, g_Color4.a);
#endif

	gl_FragColor = ApplyDropShadow(gl_FragColor, v_TexCoord.xy);
	
	//gl_FragColor = vec4(msdf, 1.0);

#else // Basic rasterization
#if COLORFONT
	vec4 _sample = texSample2D(g_Texture0, v_TexCoord.xy);
	gl_FragColor = vec4(_sample.rgb, _sample.a * g_Color4.a);
#else
	float _sample = ConvertSampleR8(texSample2D(g_Texture0, v_TexCoord.xy));
	gl_FragColor = vec4(g_Color4.rgb, _sample * g_Color4.a);
#endif
#endif
}