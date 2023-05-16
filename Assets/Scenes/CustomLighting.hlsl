#ifndef CUSTOM_LIGHTING_INCLUDED
#define CUSTOM_LIGHTING_INCLUDED

/*
- This undef (un-define) is required to prevent the "invalid subscript 'shadowCoord'" error,
  which occurs when _MAIN_LIGHT_SHADOWS is used with 1/No Shadow Cascades with the Unlit Graph.
- It's technically not required for the PBR/Lit graph, so I'm using the SHADERPASS_FORWARD to ignore it for the pass.
*/
#ifndef SHADERGRAPH_PREVIEW
    #if VERSION_GREATER_EQUAL(9, 0)
        #include "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/ShaderPass.hlsl"
        #if (SHADERPASS != SHADERPASS_FORWARD)
            #undef REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR
        #endif
    #else
        #ifndef SHADERPASS_FORWARD
            #undef REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR
        #endif
    #endif
#endif
// Also see https://github.com/Cyanilux/URP_ShaderGraphCustomLighting

void MainLight_float(float3 WorldPos, out float3 Direction, out float3 Color, out float ShadowAtten, out float DistanceAtten)
{
#if defined(SHADERGRAPH_PREVIEW)
    Direction = float3(0.5, 0.5, 0);
    Color = 1;
    ShadowAtten = 1;
    DistanceAtten = 1;
#else
	float4 shadowCoord = TransformWorldToShadowCoord(WorldPos);

    Light mainLight = GetMainLight(shadowCoord);
    Direction = mainLight.direction;
    Color = mainLight.color;
    DistanceAtten = mainLight.distanceAttenuation;
	#if !defined(_MAIN_LIGHT_SHADOWS) || defined(_RECEIVE_SHADOWS_OFF)
		ShadowAtten = 1.0h;
    #else
	    ShadowSamplingData shadowSamplingData = GetMainLightShadowSamplingData();
	    float shadowStrength = GetMainLightShadowStrength();
	    ShadowAtten = SampleShadowmap(shadowCoord, TEXTURE2D_ARGS(_MainLightShadowmapTexture,
	    sampler_MainLightShadowmapTexture),
	    shadowSamplingData, shadowStrength, false);
    #endif
#endif
}
#ifndef SHADERGRAPH_PREVIEW
half3 LightingLambertFixed(half3 lightDir, half3 normal)
{
    half NdotL = saturate(dot(normal, lightDir));
    return NdotL;
}

half3 CalculateBlinnPhongFixed(Light light, InputData inputData, SurfaceData surfaceData)
{
    half3 attenuatedLightColor = light.color * (light.distanceAttenuation * light.shadowAttenuation);
    half lightDiffuseMask = LightingLambertFixed(light.direction, inputData.normalWS);
    half3 lightDiffuseColor = attenuatedLightColor * lightDiffuseMask;

    half3 lightSpecularColor = half3(0,0,0);
    #if defined(_SPECGLOSSMAP) || defined(_SPECULAR_COLOR)
    half smoothness = exp2(10 * surfaceData.smoothness + 1);

    lightSpecularColor += LightingSpecular(attenuatedLightColor, light.direction, inputData.normalWS, inputData.viewDirectionWS, half4(surfaceData.specular, 1), smoothness);
    #endif

    #if _ALPHAPREMULTIPLY_ON
    return lightDiffuseColor * surfaceData.albedo * surfaceData.alpha + lightSpecularColor * lightDiffuseMask;
    #else
    return lightDiffuseColor * surfaceData.albedo + lightSpecularColor * lightDiffuseMask;
    #endif
}

half4 UniversalFragmentBlinnPhongFixed(InputData inputData, SurfaceData surfaceData)
{
    #if defined(DEBUG_DISPLAY)
    half4 debugColor;

    if (CanDebugOverrideOutputColor(inputData, surfaceData, debugColor))
    {
        return debugColor;
    }
    #endif

    uint meshRenderingLayers = GetMeshRenderingLayer();
    half4 shadowMask = CalculateShadowMask(inputData);
    AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData, surfaceData);
    Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);

    MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI, aoFactor);

    inputData.bakedGI *= surfaceData.albedo;

    LightingData lightingData = CreateLightingData(inputData, surfaceData);
#ifdef _LIGHT_LAYERS
    if (IsMatchingLightLayer(mainLight.layerMask, meshRenderingLayers))
#endif
    {
        lightingData.mainLightColor += CalculateBlinnPhongFixed(mainLight, inputData, surfaceData);
    }

    #if defined(_ADDITIONAL_LIGHTS)
    uint pixelLightCount = GetAdditionalLightsCount();

    #if USE_FORWARD_PLUS
    for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
    {
        FORWARD_PLUS_SUBTRACTIVE_LIGHT_CHECK

        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
#ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
        {
            lightingData.additionalLightsColor += CalculateBlinnPhong(light, inputData, surfaceData);
        }
    }
    #endif

    LIGHT_LOOP_BEGIN(pixelLightCount)
        Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
#ifdef _LIGHT_LAYERS
        if (IsMatchingLightLayer(light.layerMask, meshRenderingLayers))
#endif
        {
            lightingData.additionalLightsColor += CalculateBlinnPhong(light, inputData, surfaceData);
        }
    LIGHT_LOOP_END
    #endif

    #if defined(_ADDITIONAL_LIGHTS_VERTEX)
    lightingData.vertexLightingColor += inputData.vertexLighting * surfaceData.albedo;
    #endif

    return CalculateFinalColor(lightingData, surfaceData.alpha);
}
#endif


void CalculateBlinnPhong_float(float3 normalWS,float3 positionWS, out float4 lighting)
{
    #if defined(SHADERGRAPH_PREVIEW)
    lighting = float4(0,0,0,0);
    #else
    InputData lightingInput = (InputData)0;
    lightingInput.normalWS = normalWS;
    lightingInput.viewDirectionWS = GetWorldSpaceViewDir(positionWS);
    lightingInput.shadowCoord = TransformWorldToShadowCoord(positionWS);
    
    SurfaceData surfaceInput = (SurfaceData)0;
    surfaceInput.albedo = half3(1,1,0);
    surfaceInput.alpha = 1;
    surfaceInput.specular = 1;
    surfaceInput.smoothness = 0.5f;
    lighting =  UniversalFragmentBlinnPhongFixed(lightingInput, surfaceInput);
    #endif

}



#endif