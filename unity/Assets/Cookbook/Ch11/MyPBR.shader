// 第 11 章最终成果：完全手写 BRDF 的 PBR Shader，可直接在项目中使用。
// 支持：Forward / Forward+、主光与附加光阴影、SH + 反射探针 IBL、DFG（解析或 LUT）、多次散射补偿、
//       法线贴图、Mask Map（R 金属 G AO A 光滑）、自发光、SSAO、光照贴图、Light Layers、
//       Rendering Debugger、SRP Batcher、GPU Instancing。
Shader "Cookbook/Ch11/MyPBR"
{
    //#region properties
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        [MainColor]   _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _Metallic   ("Metallic", Range(0, 1)) = 0
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5

        [Toggle(_MASKMAP)] _UseMaskMap ("Use Mask Map", Float) = 0
        [NoScaleOffset] _MaskMap ("Mask (R Metal, G AO, A Smooth)", 2D) = "white" {}
        _OcclusionStrength ("Occlusion Strength", Range(0, 1)) = 1

        [Toggle(_NORMALMAP)] _UseNormalMap ("Use Normal Map", Float) = 0
        [NoScaleOffset][Normal] _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Scale", Float) = 1

        [Toggle(_EMISSION)] _UseEmission ("Use Emission", Float) = 0
        [NoScaleOffset] _EmissionMap ("Emission Map", 2D) = "white" {}
        [HDR] _EmissionColor ("Emission Color", Color) = (0, 0, 0, 1)

        [Toggle(_DFG_LUT)] _UseDFGLut ("Use DFG LUT (else analytic)", Float) = 0
        [NoScaleOffset] _DFGLut ("DFG LUT", 2D) = "black" {}
        _EnergyCompensation ("Multi-Scatter Compensation", Range(0, 1)) = 1
        _SpecularOcclusion ("Specular Occlusion", Range(0, 1)) = 1

        [Toggle(_ALPHATEST_ON)] _AlphaClip ("Alpha Clip", Float) = 0
        _Cutoff ("Alpha Cutoff", Range(0, 1)) = 0.5
    }
    //#endregion

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        // 所有 Pass 共享同一份 CBUFFER 声明，保证 SRP Batcher 兼容
        #include "Assets/Cookbook/Ch11/MyPBR_Input.hlsl"
        ENDHLSL

        //#region pass_forward
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex MyPBRVert
            #pragma fragment MyPBRFrag

            // ---- 材质关键字（只编译用到的组合）----
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local_fragment _MASKMAP
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _DFG_LUT
            #pragma shader_feature_local_fragment _ALPHATEST_ON

            // ---- URP 管线关键字（抄自 URP 14 Lit.shader 的 ForwardLit Pass）----
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ EVALUATE_SH_MIXED EVALUATE_SH_VERTEX
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BLENDING
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_BOX_PROJECTION
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile _ _LIGHT_LAYERS
            #pragma multi_compile _ _FORWARD_PLUS
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"

            // ---- Unity 内置关键字：光照贴图、雾、调试 ----
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile_fog
            #pragma multi_compile_fragment _ DEBUG_DISPLAY
            #pragma multi_compile_instancing

            #include "Assets/Cookbook/Ch11/MyPBR_ForwardPass.hlsl"
            ENDHLSL
        }
        //#endregion

        //#region pass_shadow
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex MyShadowVert
            #pragma fragment MyShadowFrag
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma multi_compile_instancing
            // 方向光与点/聚光的法线偏移公式不同，URP 用这个关键字区分
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch11/MyPBR_DepthPasses.hlsl"
            ENDHLSL
        }
        //#endregion

        //#region pass_depth
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask R
            Cull Back

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex MyDepthVert
            #pragma fragment MyDepthFrag
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch11/MyPBR_DepthPasses.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex MyDepthNormalsVert
            #pragma fragment MyDepthNormalsFrag
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"
            #include "Assets/Cookbook/Ch11/MyPBR_DepthPasses.hlsl"
            ENDHLSL
        }
        //#endregion

        //#region pass_meta
        Pass
        {
            Name "Meta"
            Tags { "LightMode"="Meta" }
            Cull Off

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex MyMetaVert
            #pragma fragment MyMetaFrag
            #pragma shader_feature_local_fragment _MASKMAP
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature EDITOR_VISUALIZATION
            #include "Assets/Cookbook/Ch11/MyPBR_MetaPass.hlsl"
            ENDHLSL
        }
        //#endregion
    }
    FallBack "Hidden/Universal Render Pipeline/FallbackError"
}
