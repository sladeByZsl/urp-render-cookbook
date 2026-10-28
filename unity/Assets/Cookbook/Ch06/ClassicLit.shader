// 案例 6.9 ClassicLit：完整的 Blinn-Phong + 多光源 + 阴影 Shader（后续章节会以它为基础扩展）
Shader "Cookbook/Ch06/ClassicLit"
{
    Properties
    {
        [MainTexture] _BaseMap("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor("Base Color", Color) = (1, 1, 1, 1)
        _SpecColor("Specular Color", Color) = (0.2, 0.2, 0.2, 1)
        _Smoothness("Smoothness", Range(0, 1)) = 0.5
        [HDR] _EmissionColor("Emission", Color) = (0, 0, 0, 1)

        [Toggle(_ALPHATEST_ON)] _AlphaClip("Alpha Clip", Float) = 0
        _Cutoff("Alpha Cutoff", Range(0, 1)) = 0.5
        [Toggle(_RECEIVE_SHADOWS_OFF)] _ReceiveShadowsOff("Receive Shadows Off", Float) = 0
        [Enum(UnityEngine.Rendering.CullMode)] _Cull("Cull", Float) = 2
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Assets/Cookbook/Ch06/ClassicLitInput.hlsl"
        ENDHLSL

        //#region forwardpass
        Pass
        {
            Name "ForwardLit"
            // 没有 GBuffer Pass 的自定义光照 Shader 要标成 UniversalForwardOnly：
            // Forward / Forward+ 下它和 UniversalForward 一样被绘制；Deferred 下它会进入“Forward Only”通道，
            // 而只标 UniversalForward 的物体在 Deferred 里会直接消失
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull [_Cull]

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex ClassicLitVertex
            #pragma fragment ClassicLitFragment

            // 材质关键字
            #pragma shader_feature_local _RECEIVE_SHADOWS_OFF
            #pragma shader_feature_local_fragment _ALPHATEST_ON

            // URP 关键字（与 URP 14 Lit.shader 的 ForwardLit 保持一致的子集）
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile _ _LIGHT_LAYERS
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Assets/Cookbook/Ch06/ClassicLitForwardPass.hlsl"
            ENDHLSL
        }
        //#endregion

        //#region shadowpass
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull [_Cull]

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex ShadowCasterVertex
            #pragma fragment ShadowCasterFragment
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma multi_compile_instancing
            // 区分方向光与点光/聚光：两者计算“指向光源方向”的方式不同
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch06/ShadowCasterPass.hlsl"
            ENDHLSL
        }
        //#endregion

        //#region depthpasses
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask R
            Cull [_Cull]

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch06/DepthOnlyPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthNormalsOnly"
            // 与 UniversalForwardOnly 配套：Deferred 的深度法线预渲染只收 DepthNormalsOnly；
            // Forward 下 DepthNormals 与 DepthNormalsOnly 都会被绘制，所以两者只能二选一
            Tags { "LightMode"="DepthNormalsOnly" }
            ZWrite On
            Cull [_Cull]

            HLSLPROGRAM
            #pragma target 2.0
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RenderingLayers.hlsl"
            #include "Assets/Cookbook/Ch06/DepthNormalsPass.hlsl"
            ENDHLSL
        }
        //#endregion
    }
}
