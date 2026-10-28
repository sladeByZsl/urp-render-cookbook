// 本章的完整卡通 Shader：色阶（两层阴影色 / 可选 Ramp 贴图）+ 卡通化接收阴影 + 风格化高光 + 边缘光
// + 附加光 + 平坦环境光 + 背面外扩描边（裁剪空间等宽，可选平滑法线来源）。
Shader "Cookbook/Ch14/ToonLit"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        [Header(Shading)]
        _ShadeColor ("1st Shade Color", Color) = (0.7, 0.6, 0.75, 1)
        _ShadeColor2 ("2nd Shade Color", Color) = (0.45, 0.38, 0.55, 1)
        _Threshold ("1st Shade Threshold", Range(0, 1)) = 0.5
        _Shade2Threshold ("2nd Shade Threshold", Range(0, 1)) = 0.2
        _Shade2Strength ("2nd Shade Strength", Range(0, 1)) = 1
        _Softness ("Edge Softness", Range(0, 0.3)) = 0.02
        [Toggle(_RAMPMAP)] _UseRamp ("Use Ramp Map (overrides shade colors)", Float) = 0
        [NoScaleOffset] _RampTex ("Ramp Map", 2D) = "white" {}
        [Header(Shadows)]
        _ReceiveShadow ("Receive Shadow", Range(0, 1)) = 1
        _ShadowSoftness ("Shadow Edge Softness", Range(0, 0.5)) = 0.05
        _ShadowNormalOffset ("Shadow Receiver Normal Offset (m)", Range(0, 0.1)) = 0.03
        [Header(Specular)]
        [HDR] _SpecColor ("Specular Color", Color) = (1, 1, 1, 1)
        _SpecThreshold ("Specular Threshold", Range(0.5, 1)) = 0.97
        _SpecStrength ("Specular Strength", Range(0, 1)) = 1
        [Header(Rim)]
        [HDR] _RimColor ("Rim Color", Color) = (1, 0.95, 0.9, 1)
        _RimWidth ("Rim Width", Range(0, 1)) = 0.25
        _RimStrength ("Rim Strength", Range(0, 1)) = 0.6
        [Header(Ambient and Extra Lights)]
        _AmbientStrength ("Ambient Strength", Range(0, 1)) = 0.35
        _AddLightStrength ("Additional Lights Strength", Range(0, 2)) = 1
        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0.15, 0.1, 0.12, 1)
        _OutlineWidth ("Outline Width (px)", Range(0, 10)) = 2.5
        [KeywordEnum(Mesh, Tangent, VertexColor)] _OutlineNormal ("Outline Normal Source", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor, _ShadeColor, _ShadeColor2, _SpecColor, _RimColor, _OutlineColor;
            half  _Threshold, _Shade2Threshold, _Shade2Strength, _Softness;
            half  _ReceiveShadow, _ShadowSoftness, _ShadowNormalOffset;
            half  _SpecThreshold, _SpecStrength, _RimWidth, _RimStrength;
            half  _AmbientStrength, _AddLightStrength, _OutlineWidth;
        CBUFFER_END
        TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
        TEXTURE2D(_RampTex); SAMPLER(sampler_RampTex);
        ENDHLSL

        Pass
        {
            Name "ToonForward"
            Tags { "LightMode"="UniversalForwardOnly" }

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex ToonVert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _ _RAMPMAP
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch14/ToonCommon.hlsl"

            //#region diffuse
            // 主光的色阶：输入是“半 Lambert × 卡通化后的阴影”，输出是最终的漫反射颜色
            half3 ToonDiffuse(half3 albedo, half halfLambert, half shadow)
            {
                // 接收阴影卡通化：把 PCF 的软阴影值也切成硬边，再“乘进”明暗，而不是在最后乘一次
                half toonShadow = lerp(1.0, ToonBand(shadow, 0.5, _ShadowSoftness), _ReceiveShadow);
                // 投影区域只压到“第一层阴影”的位置，而不是压到 0（那会掉进第二层阴影，比背光面还暗）
                half shadowedX = min(halfLambert, (_Threshold + _Shade2Threshold) * 0.5);
                half x = lerp(shadowedX, halfLambert, toonShadow);
            #if defined(_RAMPMAP)
                return albedo * SAMPLE_TEXTURE2D(_RampTex, sampler_RampTex, float2(clamp(x, 0.01, 0.99), 0.5)).rgb;
            #else
                half band1 = ToonBand(x, _Threshold, _Softness);
                half band2 = ToonBand(x, _Shade2Threshold, _Softness);
                half3 shade = lerp(albedo * _ShadeColor2.rgb, albedo * _ShadeColor.rgb, lerp(1.0, band2, _Shade2Strength));
                return lerp(shade, albedo, band1);
            #endif
            }
            //#endregion

            //#region addlight
            // 附加光：同样做一次硬边，得到一圈有清晰边界的彩色光斑
            half3 ToonAdditional(half3 albedo, half3 N, Light light)
            {
                half atten = light.distanceAttenuation * light.shadowAttenuation;
                half x = saturate(dot(N, light.direction)) * saturate(atten * 4.0);
                return albedo * light.color * ToonBand(x, 0.3, _Softness + 0.02) * _AddLightStrength;
            }
            //#endregion

            //#region frag
            half4 frag(ToonVaryings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                half3 N = normalize(i.normalWS);
                half3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, TRANSFORM_TEX(i.uv, _BaseMap)).rgb * _BaseColor.rgb;

                // ---------- 主光 + 阴影 ----------
                // 接收端法线偏移：沿法线挪一点再查阴影图，消除明暗交界处的自阴影锯齿（shadow acne）
                float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS + N * _ShadowNormalOffset);
                Light mainLight = GetMainLight(shadowCoord, i.positionWS, half4(1, 1, 1, 1));
                half NoL = dot(N, mainLight.direction);
                half3 color = ToonDiffuse(albedo, NoL * 0.5 + 0.5, mainLight.shadowAttenuation) * mainLight.color;

                // 高光与边缘光只出现在“真正被照亮”的区域
                half litMask = ToonBand((NoL * 0.5 + 0.5) * lerp(1.0, ToonBand(mainLight.shadowAttenuation, 0.5, _ShadowSoftness), _ReceiveShadow), _Threshold, _Softness);
                half3 H = normalize(mainLight.direction + V);
                half spec = ToonBand(saturate(dot(N, H)), _SpecThreshold, 0.005) * litMask;
                color += spec * _SpecStrength * _SpecColor.rgb * mainLight.color;
                half rim = FresnelRim(N, V, _RimWidth, 0.02) * litMask;
                color = lerp(color, _RimColor.rgb * albedo * mainLight.color * 1.6, rim * _RimStrength);

                // ---------- 附加光 ----------
            #if defined(_ADDITIONAL_LIGHTS)
                InputData inputData = (InputData)0;         // Forward+ 的光源循环宏需要它
                inputData.positionWS = i.positionWS;
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);
              #if USE_FORWARD_PLUS
                for (uint li = 0; li < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); li++)
                    color += ToonAdditional(albedo, N, GetAdditionalLight(li, i.positionWS, half4(1, 1, 1, 1)));
              #endif
                uint lightCount = GetAdditionalLightsCount();
                LIGHT_LOOP_BEGIN(lightCount)
                    color += ToonAdditional(albedo, N, GetAdditionalLight(lightIndex, i.positionWS, half4(1, 1, 1, 1)));
                LIGHT_LOOP_END
            #endif

                // ---------- 环境光：只取球谐常数项，整块抬亮暗部 ----------
                color += SampleSH(half3(0, 0, 0)) * albedo * _AmbientStrength;

                return half4(MixFog(color, i.fogFactor), 1);
            }
            //#endregion
            ENDHLSL
        }

        //#region outline
        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            ZWrite On
            HLSLPROGRAM
            #pragma vertex OutlineVert
            #pragma fragment OutlineFrag
            #pragma shader_feature_local_vertex _OUTLINENORMAL_MESH _OUTLINENORMAL_TANGENT _OUTLINENORMAL_VERTEXCOLOR
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch14/ToonOutlinePass.hlsl"
            ENDHLSL
        }
        //#endregion
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Back
            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            // URP 自带的阴影 Pass 只在 _ALPHATEST_ON 时才读 _BaseMap，其余部分与材质无关，直接复用
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R Cull Back
            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On Cull Back
            HLSLPROGRAM
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthNormalsPass.hlsl"
            ENDHLSL
        }
    }
}
