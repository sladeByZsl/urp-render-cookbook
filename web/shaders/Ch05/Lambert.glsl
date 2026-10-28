// 案例 5.1 Lambert 漫反射：只计算主光源的 N·L，再加一点球谐环境光（GLSL 版，对应 Ch05/Lambert.shader）
Shader "Cookbook/Ch05/Lambert"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseColor;
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
                // 法线要用“逆转置矩阵”变换，TransformObjectToWorldNormal 已经处理了非等比缩放
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                // 插值后的法线长度不再是 1，必须重新归一化
                vec3 N = normalize(normalWS);

                Light mainLight = GetMainLight();
                // direction 指向光源；color 已经乘过 Intensity，是线性空间的 HDR 值
                vec3 radiance = mainLight.color * mainLight.distanceAttenuation;

                // 余弦定律：背光面 N·L < 0，必须截断到 0，否则会“吸收”别的光
                float NdotL = saturate(dot(N, mainLight.direction));
                vec3 diffuse = _BaseColor.rgb * radiance * NdotL;

                // 环境光：来自天空的球谐光照，第 8 章细讲。没有它，背光面会是纯黑
                vec3 ambient = _BaseColor.rgb * SampleSH(N) * _AmbientStrength;

                fragColor = vec4(diffuse + ambient, 1.0);
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
