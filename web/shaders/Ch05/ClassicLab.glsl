// 案例 5.9 经典光照实验台：用关键字自由组合漫反射模型与高光模型（GLSL 版）
Shader "Cookbook/Ch05/ClassicLab"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseMap_ST;
        uniform vec4  _BaseColor;
        uniform float _Wrap;
        uniform float _Roughness;
        uniform vec4  _SpecColor;
        uniform float _Smoothness;
        uniform float _AmbientStrength;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _DIFFUSE_LAMBERT _DIFFUSE_HALFLAMBERT _DIFFUSE_WRAP _DIFFUSE_ORENNAYAR
            #pragma shader_feature_local_fragment _SPECULAR_NONE _SPECULAR_PHONG _SPECULAR_BLINNPHONG
            #include "Ch05/ClassicLighting.glsl"

            uniform sampler2D _BaseMap;

            VARYING vec2 uv;
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = pos.positionCS;
                positionWS = pos.positionWS;
                normalWS = TransformObjectToWorldNormal(normalOS);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            void main()
            {
                vec3 albedo = texture(_BaseMap, uv).rgb * _BaseColor.rgb;
                vec3 N = normalize(normalWS);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                Light mainLight = GetMainLight();
                vec3 L = mainLight.direction;
                vec3 radiance = mainLight.color * mainLight.distanceAttenuation;

            #if defined(_DIFFUSE_HALFLAMBERT)
                float d = DiffuseHalfLambert(N, L, 2.0);
            #elif defined(_DIFFUSE_WRAP)
                float d = DiffuseWrap(N, L, _Wrap);
            #elif defined(_DIFFUSE_ORENNAYAR)
                float d = DiffuseOrenNayar(N, L, V, _Roughness);
            #else
                float d = DiffuseLambert(N, L);
            #endif

                float n = ShininessFromSmoothness(_Smoothness);
            #if defined(_SPECULAR_PHONG)
                float s = SpecularPhong(N, L, V, n);
            #elif defined(_SPECULAR_BLINNPHONG)
                float s = SpecularBlinnPhong(N, L, V, n);
            #else
                float s = 0.0;
            #endif

                vec3 color = (albedo * d + _SpecColor.rgb * s) * radiance;
                color += albedo * SampleSH(N) * _AmbientStrength;
                fragColor = vec4(color, 1.0);
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
