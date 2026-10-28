// 案例 5.8 逐顶点（Gouraud）与逐像素光照：同一套 Blinn-Phong，只是放在不同阶段算（GLSL 版）
Shader "Cookbook/Ch05/Gouraud"
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
            #pragma shader_feature_local _PER_VERTEX

        #if defined(_PER_VERTEX)
            // 顶点里算好的颜色，光栅化时线性插值
            // （HLSL 版叫 color；GLSL 版顶点输入里已经有个 color 属性，所以改名 vertexColor）
            VARYING vec3 vertexColor;
        #else
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;     // 插值的是法线，到片元里再算光照
        #endif

            //#region shade
            vec3 ShadeBlinnPhong(vec3 positionWS, vec3 N)
            {
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                Light mainLight = GetMainLight();
                vec3 L = mainLight.direction;
                vec3 radiance = mainLight.color * mainLight.distanceAttenuation;
                float NdotL = dot(N, L);
                float spec = pow(saturate(dot(N, SafeNormalize(L + V))), _Shininess) * step(0.0, NdotL);
                vec3 color = (_BaseColor.rgb * saturate(NdotL) + _SpecColor.rgb * spec) * radiance;
                return color + _BaseColor.rgb * SampleSH(N) * _AmbientStrength;
            }
            //#endregion

            //#region vertfrag
            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
                vec3 nWS = TransformObjectToWorldNormal(normalOS);
                gl_Position = pos.positionCS;
            #if defined(_PER_VERTEX)
                vertexColor = ShadeBlinnPhong(pos.positionWS, nWS);
            #else
                positionWS = pos.positionWS;
                normalWS = nWS;
            #endif
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
            #if defined(_PER_VERTEX)
                fragColor = vec4(vertexColor, 1.0);
            #else
                fragColor = vec4(ShadeBlinnPhong(positionWS, normalize(normalWS)), 1.0);
            #endif
            }
            #endif
            //#endregion
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
