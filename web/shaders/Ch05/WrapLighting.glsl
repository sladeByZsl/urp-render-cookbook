// 案例 5.3 Wrap Lighting：让光“绕过”明暗交界线，可选能量守恒和交界线染色（GLSL 版）
Shader "Cookbook/Ch05/WrapLighting"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseColor;
        uniform float _Wrap;
        uniform vec4  _TerminatorTint;
        uniform float _AmbientStrength;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _WRAP_ENERGY_CONSERVING
            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif

            #ifdef FRAGMENT
            //#region wrap
            float WrapDiffuse(float NdotL, float w)
            {
            #if defined(_WRAP_ENERGY_CONSERVING)
                // 分母 (1+w)^2：被照亮的范围变大了，峰值相应压低，总能量与 Lambert 相同
                return saturate((NdotL + w) / ((1.0 + w) * (1.0 + w)));
            #else
                // 经典写法：w = 0 时退化为 Lambert，w = 1 时等价于未平方的 Half-Lambert
                return saturate((NdotL + w) / (1.0 + w));
            #endif
            }
            //#endregion

            //#region frag
            void main()
            {
                vec3 N = normalize(normalWS);
                Light mainLight = GetMainLight();
                vec3 radiance = mainLight.color * mainLight.distanceAttenuation;

                float NdotL = dot(N, mainLight.direction);
                float wrap = WrapDiffuse(NdotL, _Wrap);

                // 交界线染色：只在“Wrap 有、Lambert 没有”的那一圈加颜色，模拟光在皮下散射后带出的红色
                float scatter = saturate(wrap - saturate(NdotL));
                vec3 diffuse = _BaseColor.rgb * radiance * wrap
                             + _TerminatorTint.rgb * radiance * scatter;

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
