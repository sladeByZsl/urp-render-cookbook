// 案例 6.9 ClassicLit：完整的 Blinn-Phong + 多光源 + 阴影 Shader（后续章节会以它为基础扩展）（GLSL 版，对应 Ch06/ClassicLit.shader）
Shader "Cookbook/Ch06/ClassicLit"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        #include "Ch06/ClassicLitInput.glsl"
        ENDGLSL

        //#region forwardpass
        Pass
        {
            Name "ForwardLit"
            // 没有 GBuffer Pass 的自定义光照 Shader 要标成 UniversalForwardOnly：
            // Forward / Forward+ 下它和 UniversalForward 一样被绘制；Deferred 下它会进入“Forward Only”通道，
            // 而只标 UniversalForward 的物体在 Deferred 里会直接消失
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull [_Cull]

            GLSLPROGRAM
            // 材质关键字
            #pragma shader_feature_local _RECEIVE_SHADOWS_OFF
            #pragma shader_feature_local_fragment _ALPHATEST_ON

            // URP 关键字：主光阴影、附加光（逐像素）、附加光阴影、软阴影由网页版引擎始终定义；
            // _FORWARD_PLUS、_LIGHT_LAYERS 在网页版里分别由引擎内部 / uniform _LightLayers 处理；
            // _SCREEN_SPACE_OCCLUSION 由 _AmbientOcclusionParam.x 判断；雾由 unity_FogMode 判断
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS

            #include "Ch06/ClassicLitForwardPass.glsl"
            ENDGLSL
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

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            // 区分方向光与点光/聚光：两者计算“指向光源方向”的方式不同（GLSL 版里是 uniform _CastingPunctualLightShadow）
            #include "Ch06/ShadowCasterPass.glsl"
            ENDGLSL
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

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #include "Ch06/DepthOnlyPass.glsl"
            ENDGLSL
        }

        Pass
        {
            Name "DepthNormalsOnly"
            // 与 UniversalForwardOnly 配套：Deferred 的深度法线预渲染只收 DepthNormalsOnly；
            // Forward 下 DepthNormals 与 DepthNormalsOnly 都会被绘制，所以两者只能二选一
            Tags { "LightMode"="DepthNormalsOnly" }
            ZWrite On
            Cull [_Cull]

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #include "Ch06/DepthNormalsPass.glsl"
            ENDGLSL
        }
        //#endregion
    }
}
