// 边缘光（三种做法）与风格化高光（三种做法）。漫反射部分沿用上一案例的色阶。
Shader "Cookbook/Ch14/ToonRimSpec"
{
    Properties
    {
        [MainColor] _BaseColor ("Base Color", Color) = (0.35, 0.55, 0.95, 1)
        _ShadeColor ("Shade Color", Color) = (0.22, 0.25, 0.55, 1)
        _Threshold ("Threshold", Range(0, 1)) = 0.5
        _Softness ("Edge Softness", Range(0, 0.5)) = 0.02
        [Header(Rim)]
        [KeywordEnum(Off, Fresnel, LightMasked, Depth)] _Rim ("Rim Mode", Float) = 2
        [HDR] _RimColor ("Rim Color", Color) = (1, 0.95, 0.85, 1)
        _RimWidth ("Fresnel Rim Width", Range(0, 1)) = 0.3
        _RimWidthPx ("Depth Rim Width (px)", Range(0, 20)) = 5
        _RimDepthThreshold ("Depth Rim Threshold (m)", Range(0.01, 2)) = 0.2
        [Header(Specular)]
        [KeywordEnum(Off, Blinn, Toon, Stylized)] _Spec ("Specular Mode", Float) = 2
        [HDR] _SpecColor ("Specular Color", Color) = (1, 1, 1, 1)
        _SpecThreshold ("Specular Threshold", Range(0.5, 1)) = 0.97
        _SpecShiftScale ("Shift T/B, Scale T/B", Vector) = (0, 0, 0, 0)
        _SpecSplit ("Split T/B", Vector) = (0, 0, 0, 0)
        _SpecSquare ("Squareness", Range(0, 1)) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor, _ShadeColor, _RimColor, _SpecColor;
            half  _Threshold, _Softness, _RimWidth, _RimWidthPx, _RimDepthThreshold;
            half  _SpecThreshold, _SpecSquare;
            half4 _SpecShiftScale;
            half4 _SpecSplit;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ToonForward"
            Tags { "LightMode"="UniversalForwardOnly" }

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex ToonVert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _RIM_OFF _RIM_FRESNEL _RIM_LIGHTMASKED _RIM_DEPTH
            #pragma shader_feature_local_fragment _SPEC_OFF _SPEC_BLINN _SPEC_TOON _SPEC_STYLIZED
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch14/ToonCommon.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            //#region depthrim
            // 屏幕空间深度边缘光：沿法线在屏幕上的投影方向偏移若干像素读深度，
            // 如果那里的深度比自己“深很多”，说明自己处在轮廓边上
            half DepthRim(ToonVaryings i, half3 N)
            {
                float3 normalCS = TransformWorldToHClipDir(N);
                float2 dirPx = normalize(normalCS.xy * _ScreenParams.xy + 1e-6);
            #if UNITY_UV_STARTS_AT_TOP
                dirPx.y = -dirPx.y;   // 这些平台的像素坐标 y 朝下，与裁剪空间 y 相反
            #endif
                int2 p = int2(i.positionCS.xy + dirPx * _RimWidthPx);
                p = clamp(p, int2(0, 0), int2(_ScreenParams.xy) - 1);
                float sceneDepth = LinearEyeDepth(LoadSceneDepth(p), _ZBufferParams);
                float selfDepth = LinearEyeDepth(i.positionCS.z, _ZBufferParams);
                return step(_RimDepthThreshold, sceneDepth - selfDepth);
            }
            //#endregion

            //#region frag
            half4 frag(ToonVaryings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                half3 N = normalize(i.normalWS);
                half3 T = normalize(i.tangentWS.xyz);
                half3 B = cross(N, T) * i.tangentWS.w;
                half3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                Light light = GetMainLight();
                half3 L = light.direction;
                half NoL = dot(N, L);
                half band = ToonBand(NoL * 0.5 + 0.5, _Threshold, _Softness);
                half3 color = lerp(_ShadeColor.rgb, _BaseColor.rgb, band) * light.color;
                color += SampleSH(half3(0, 0, 0)) * _BaseColor.rgb * 0.3;

                // ---------- 高光 ----------
                half3 H = normalize(L + V);
                half spec = 0;
            #if defined(_SPEC_BLINN)
                spec = pow(saturate(dot(N, H)), 64.0);                                // 对照：普通 Blinn-Phong
            #elif defined(_SPEC_TOON)
                spec = ToonBand(saturate(dot(N, H)), _SpecThreshold, 0.005);          // 色阶化：一个硬边色块
            #elif defined(_SPEC_STYLIZED)
                spec = StylizedSpecular(N, T, B, H, _SpecShiftScale, _SpecSplit.xy, _SpecSquare, _SpecThreshold, 0.005);
            #endif
                color += spec * band * _SpecColor.rgb * light.color;                  // 只在亮部出现

                // ---------- 边缘光 ----------
                half rim = 0;
            #if defined(_RIM_FRESNEL)
                rim = FresnelRim(N, V, _RimWidth, 0.02);
            #elif defined(_RIM_LIGHTMASKED)
                // 只保留朝光一侧的边缘：边缘光“像是被主光勾出来的”，背光侧不会到处发亮
                rim = FresnelRim(N, V, _RimWidth, 0.02) * ToonBand(NoL, 0.0, 0.1);
            #elif defined(_RIM_DEPTH)
                rim = DepthRim(i, N) * ToonBand(NoL, -0.2, 0.1);
            #endif
                color = lerp(color, _RimColor.rgb * light.color, rim);

                color = MixFog(color, i.fogFactor);
                return half4(color, 1);
            }
            //#endregion
            ENDHLSL
        }

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
