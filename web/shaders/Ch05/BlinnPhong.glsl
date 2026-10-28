// 案例 5.5 Blinn-Phong 高光：用半程向量 H 代替反射向量 R（GLSL 版）
Shader "Cookbook/Ch05/BlinnPhong"
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
            //#region frag
            void main()
            {
                vec3 N = normalize(normalWS);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                Light mainLight = GetMainLight();
                vec3 L = mainLight.direction;
                vec3 radiance = mainLight.color * mainLight.distanceAttenuation;

                float NdotL = dot(N, L);
                vec3 diffuse = _BaseColor.rgb * saturate(NdotL);

                // 半程向量：L 与 V 的“角平分线”。L、V 几乎相反时 L+V 接近零向量，用 SafeNormalize 防 NaN
                vec3 H = SafeNormalize(L + V);
                float NdotH = saturate(dot(N, H));
                float spec = pow(NdotH, _Shininess) * step(0.0, NdotL);

                vec3 color = (diffuse + _SpecColor.rgb * spec) * radiance;
                color += _BaseColor.rgb * SampleSH(N) * _AmbientStrength;
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
