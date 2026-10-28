// 案例 5.4 Phong 高光：反射向量 R 与视线 V 的夹角决定高光（GLSL 版）
Shader "Cookbook/Ch05/Phong"
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
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);   // 指向相机
                Light mainLight = GetMainLight();
                vec3 L = mainLight.direction;                         // 指向光源
                vec3 radiance = mainLight.color * mainLight.distanceAttenuation;

                float NdotL = dot(N, L);
                vec3 diffuse = _BaseColor.rgb * saturate(NdotL);

                // reflect(i, n) 要求 i 是“射入”方向，所以传 -L
                vec3 R = reflect(-L, N);
                float RdotV = saturate(dot(R, V));
                // 高光指数常常上百，用 float 计算，避免 half 精度下出现色带
                float spec = pow(RdotV, _Shininess);
                // 背光面不应该出现高光（R 可能恰好朝向相机）
                spec *= step(0.0, NdotL);

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
