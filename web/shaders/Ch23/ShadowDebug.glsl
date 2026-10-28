// 本章的调试 Shader（GLSL 版）：
//   _Mode = 0：按 ComputeCascadeIndex 给每一级级联上色（红/绿/蓝/黄，超出阴影距离为灰）
//   _Mode = 1：只输出主光阴影衰减（白 = 受光，黑 = 阴影），用来观察屏幕空间阴影贴图等
Shader "Cookbook/Ch23/ShadowDebug"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            uniform float _Mode;
            uniform float _Tint;

            VARYING vec3 positionWS;
            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs p = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = p.positionCS; positionWS = p.positionWS;
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            vec4 frag()
            {
                vec4 shadowCoord = TransformWorldToShadowCoord(positionWS);
                float shadow = MainLightRealtimeShadow(shadowCoord);
                if (_Mode > 0.5) return vec4(vec3(shadow), 1);

                vec3 n = normalize(normalWS);
                Light l = GetMainLight();
                vec3 shade = vec3(saturate(dot(n, l.direction)) * shadow * 0.8 + 0.25);
                // _MAIN_LIGHT_SHADOWS_CASCADE 关键字在网页版是个 uniform（级联数 > 1 时为 1）
                float cascade = _MainLightShadowsCascade > 0.5 ? ComputeCascadeIndex(positionWS) : 0.0;   // 0..3，超出所有级联球为 4
                vec3 kColors[5] = vec3[5](
                    vec3(1.0, 0.35, 0.3), vec3(0.35, 0.9, 0.4), vec3(0.35, 0.55, 1.0),
                    vec3(1.0, 0.85, 0.3), vec3(0.6, 0.6, 0.6)
                );
                vec3 tint = mix(vec3(1, 1, 1), kColors[int(cascade)], _Tint);
                return vec4(shade * tint, 1);
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #define CH23_SHADOW_PASS
            #include "Ch23/Ch23Common.glsl"
            ENDGLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #define CH23_DEPTH_PASS
            #include "Ch23/Ch23Common.glsl"
            ENDGLSL
        }
    }
}
