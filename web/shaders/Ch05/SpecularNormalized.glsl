// 案例 5.6 高光归一化：让高光指数只改变“形状”，不改变“总能量”（GLSL 版）
Shader "Cookbook/Ch05/SpecularNormalized"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseColor;
        uniform vec4  _SpecColor;
        uniform float _Shininess;
        uniform float _AmbientStrength;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _MODEL_BLINNPHONG _MODEL_PHONG
            #pragma shader_feature_local_fragment _NORMALIZE_SPECULAR
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
            //#region spec
            // 返回“乘上 N·L 之后”的高光项，与 URP 的约定一致：漫反射写成 albedo * N·L（没有 1/π），
            // 所以这里的归一化系数也整体乘了 π：Blinn-Phong 用 (n+8)/8，Phong 用 (n+2)/2
            float SpecularTerm(vec3 N, vec3 L, vec3 V, float n)
            {
                float NdotL = saturate(dot(N, L));
            #if defined(_MODEL_PHONG)
                float lobe = pow(saturate(dot(reflect(-L, N), V)), n);
                float norm = (n + 2.0) / 2.0;
            #else
                float lobe = pow(saturate(dot(N, SafeNormalize(L + V))), n);
                float norm = (n + 8.0) / 8.0;
            #endif
            #if !defined(_NORMALIZE_SPECULAR)
                norm = 1.0;
            #endif
                return norm * lobe * NdotL;
            }
            //#endregion

            void main()
            {
                vec3 N = normalize(normalWS);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                Light mainLight = GetMainLight();
                vec3 L = mainLight.direction;
                vec3 radiance = mainLight.color * mainLight.distanceAttenuation;

                vec3 diffuse = _BaseColor.rgb * saturate(dot(N, L));
                vec3 specular = _SpecColor.rgb * SpecularTerm(N, L, V, _Shininess);
                vec3 color = (diffuse + specular) * radiance;
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
