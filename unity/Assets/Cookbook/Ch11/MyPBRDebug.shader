// MyPBR 的调试视图：把 BRDF 的每一项、光照的每一部分单独输出，用来验证实现和写书配图。
// 与 MyPBR 共用全部 HLSL，只换了片元函数。_View 用 uniform 分支（不产生变体），调试用足够了。
Shader "Cookbook/Ch11/MyPBRDebug"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        [MainColor]   _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _Metallic   ("Metallic", Range(0, 1)) = 0
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
        [Toggle(_MASKMAP)] _UseMaskMap ("Use Mask Map", Float) = 0
        [NoScaleOffset] _MaskMap ("Mask", 2D) = "white" {}
        _OcclusionStrength ("Occlusion Strength", Range(0, 1)) = 1
        [Toggle(_NORMALMAP)] _UseNormalMap ("Use Normal Map", Float) = 0
        [NoScaleOffset][Normal] _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Scale", Float) = 1
        [Toggle(_EMISSION)] _UseEmission ("Use Emission", Float) = 0
        [NoScaleOffset] _EmissionMap ("Emission Map", 2D) = "white" {}
        [HDR] _EmissionColor ("Emission Color", Color) = (0, 0, 0, 1)
        [Toggle(_DFG_LUT)] _UseDFGLut ("Use DFG LUT", Float) = 0
        [NoScaleOffset] _DFGLut ("DFG LUT", 2D) = "black" {}
        _EnergyCompensation ("Multi-Scatter Compensation", Range(0, 1)) = 1
        _SpecularOcclusion ("Specular Occlusion", Range(0, 1)) = 1
        _Cutoff ("Alpha Cutoff", Range(0, 1)) = 0.5
        [Enum(Final,0,D,1,G2,2,F,3,DirectSpecular,4,DirectDiffuse,5,IndirectDiffuse,6,IndirectSpecular,7,Direct,8,Indirect,9,PrefilteredEnv,10,EnvBRDF,11)]
        _View ("View", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Assets/Cookbook/Ch11/MyPBR_Input.hlsl"
        float _View;   // 调试专用，故意放在 CBUFFER 外（这个 Shader 不追求 SRP Batcher 兼容）
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex MyPBRVert
            #pragma fragment DebugFrag
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local_fragment _MASKMAP
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _DFG_LUT
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile _ _FORWARD_PLUS
            #include "Assets/Cookbook/Ch11/MyPBR_ForwardPass.hlsl"

            //#region debug_frag
            half4 DebugFrag(Varyings i) : SV_Target
            {
                MySurface s  = MySampleSurface(i.uv);
                InputData id = MyInitInputData(i, s.normalTS);
                MyMaterial m = MyInitMaterial(s.albedo, s.metallic, s.perceptualRoughness);
                int view = (int)_View;

                // 1~3：只看主光方向上的单项，便于和第 9 章的公式图对照
                if (view >= 1 && view <= 3)
                {
                    Light L = GetMainLight();
                    float3 N = id.normalWS, V = id.viewDirectionWS, H = SafeNormalize(L.direction + V);
                    float NoV = abs(dot(N, V)) + 1e-5, NoL = saturate(dot(N, L.direction));
                    float NoH = saturate(dot(N, H)), LoH = saturate(dot(L.direction, H));
                    if (view == 1)   // 归一化的 D：除以峰值 1/(π α²)，范围 0~1
                        return MyD_GGX(NoH, m.a2) * PI * m.a2 * (NoL > 0);
                    if (view == 2)   // G2 = V * 4 NoL NoV，范围 0~1
                        return MyV_SmithGGXCorrelated(NoV, NoL, m.a2) * 4.0 * NoL * NoV;
                    return half4(MyF_Schlick(m.f0, 1.0, LoH) * (NoL > 0), 1);
                }

                MyLightingTerms t = MyComputeLighting(s, m, id);
                float3 c;
                switch (view)
                {
                    case 4:  c = t.directSpecular; break;
                    case 5:  c = t.directDiffuse; break;
                    case 6:  c = t.indirectDiffuse; break;
                    case 7:  c = t.indirectSpecular; break;
                    case 8:  c = t.directDiffuse + t.directSpecular; break;
                    case 9:  c = t.indirectDiffuse + t.indirectSpecular; break;
                    case 10: c = MySamplePrefilteredEnv(reflect(-id.viewDirectionWS, id.normalWS), m.perceptualRoughness,
                                                        id.positionWS, id.normalizedScreenSpaceUV); break;
                    case 11:
                    {
                        float NoV = saturate(dot(id.normalWS, id.viewDirectionWS));
                        float2 dfg = MyEnvDFG(NoV, m.perceptualRoughness);
                        c = m.f0 * dfg.x + dfg.y; break;
                    }
                    default: c = t.directDiffuse + t.directSpecular + t.indirectDiffuse + t.indirectSpecular + t.emission; break;
                }
                return half4(c, 1);
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex MyShadowVert
            #pragma fragment MyShadowFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch11/MyPBR_DepthPasses.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex MyDepthVert
            #pragma fragment MyDepthFrag
            #include "Assets/Cookbook/Ch11/MyPBR_DepthPasses.hlsl"
            ENDHLSL
        }
    }
}
