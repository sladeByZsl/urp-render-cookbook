// 案例 5.7 粗糙漫反射：Oren-Nayar（定性模型）与 Minnaert（GLSL 版）
Shader "Cookbook/Ch05/RoughDiffuse"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseColor;
        uniform float _Roughness;
        uniform float _MinnaertK;
        uniform float _AmbientStrength;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _MODEL_LAMBERT _MODEL_ORENNAYAR _MODEL_MINNAERT
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = pos.positionCS;
                positionWS = pos.positionWS;
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif

            #ifdef FRAGMENT
            //#region orennayar
            // Oren-Nayar 定性模型，返回值已乘 N·L（URP 约定，不含 1/π）。
            // 原式 A + B·max(0, cos(φi-φr))·sinα·tanβ 里的三角函数可以全部消掉：
            //   s = L·V - (N·L)(N·V) = sinθi·sinθr·cos(φi-φr)
            //   sinα·tanβ = sinθi·sinθr / max(cosθi, cosθr)
            // 于是 cos(φi-φr)·sinα·tanβ = s / max(N·L, N·V)
            float OrenNayar(vec3 N, vec3 L, vec3 V, float sigma)
            {
                float NdotL = saturate(dot(N, L));
                float NdotV = saturate(dot(N, V));
                float s2 = sigma * sigma;
                float A = 1.0 - 0.5 * s2 / (s2 + 0.33);
                float B = 0.45 * s2 / (s2 + 0.09);
                float s = dot(L, V) - NdotL * NdotV;
                float t = max(max(NdotL, NdotV), 1e-4);
                return NdotL * (A + B * max(0.0, s) / t);
            }
            //#endregion

            //#region minnaert
            // Minnaert：k = 1 时就是 Lambert；k < 1 边缘变亮（天鹅绒、月面感），k > 1 边缘更暗
            float Minnaert(vec3 N, vec3 L, vec3 V, float k)
            {
                float NdotL = saturate(dot(N, L));
                float NdotV = max(saturate(dot(N, V)), 1e-3);
                return pow(NdotL, k) * pow(NdotV, k - 1.0);
            }
            //#endregion

            void main()
            {
                vec3 N = normalize(normalWS);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                Light mainLight = GetMainLight();
                vec3 L = mainLight.direction;
                vec3 radiance = mainLight.color * mainLight.distanceAttenuation;

            #if defined(_MODEL_ORENNAYAR)
                float d = OrenNayar(N, L, V, _Roughness);
            #elif defined(_MODEL_MINNAERT)
                float d = Minnaert(N, L, V, _MinnaertK);
            #else
                float d = saturate(dot(N, L));
            #endif

                vec3 color = _BaseColor.rgb * radiance * d;
                color += _BaseColor.rgb * SampleSH(N) * _AmbientStrength;
                fragColor = vec4(color, 1.0);
            }
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
