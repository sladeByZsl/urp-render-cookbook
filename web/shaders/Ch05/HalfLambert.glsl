// 案例 5.2 Half-Lambert：把 [-1,1] 的 N·L 线性映射到 [0,1]，再可选地做一次幂（GLSL 版）
Shader "Cookbook/Ch05/HalfLambert"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseColor;
        uniform float _Power;
        uniform float _AmbientStrength;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            void main()
            {
                vec3 N = normalize(normalWS);
                Light mainLight = GetMainLight();
                vec3 radiance = mainLight.color * mainLight.distanceAttenuation;

                // 注意这里没有 saturate：背光面的负值也要参与映射
                float NdotL = dot(N, mainLight.direction);
                float halfLambert = NdotL * 0.5 + 0.5;          // [-1,1] -> [0,1]
                halfLambert = pow(halfLambert, _Power);         // Valve 原版取平方，让暗部重新“沉下去”

                vec3 diffuse = _BaseColor.rgb * radiance * halfLambert;
                vec3 ambient = _BaseColor.rgb * SampleSH(N) * _AmbientStrength;
                fragColor = vec4(diffuse + ambient, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }

        // ---- 投影与深度：本章先照抄，原理见第 6 章 ----
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0
            GLSLPROGRAM
            #define SHADOW_PASS
            #include "Ch05/Ch05ShadowDepth.glsl"
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask R
            GLSLPROGRAM
            #define DEPTH_PASS
            #include "Ch05/Ch05ShadowDepth.glsl"
            ENDGLSL
        }
    }
}
