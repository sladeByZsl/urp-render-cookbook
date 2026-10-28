// 案例 18.4：菲涅尔边缘光（Rim Light）。不透明基础光照 + 叠加一圈轮廓亮边。（GLSL 版，对应 Ch18/FresnelRim.shader）
Shader "Cookbook/Ch18/FresnelRim"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" "RenderPipeline"="UniversalPipeline" }

        // GLSLINCLUDE 里的代码会插到本 SubShader 每个 Pass 的最前面：材质参数写一次，所有 Pass 一致
        GLSLINCLUDE
        uniform vec4  _BaseColor;
        uniform float _Smoothness;
        uniform vec4  _RimColor;
        uniform float _RimPower;
        uniform float _RimIntensity;
        uniform float _RimLightMask;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            #include "Ch18/Ch18Common.glsl"

            VARYING vec3 positionWS;
            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                positionWS = TransformObjectToWorld(positionOS.xyz);
                gl_Position = TransformWorldToHClip(positionWS);
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            void main()
            {
                vec3 N = normalize(normalWS);
                vec3 viewWS = GetWorldSpaceNormalizeViewDir(positionWS);
                vec3 color = SimpleLighting(_BaseColor.rgb, positionWS, N, _Smoothness);

                float rim = FresnelRim(N, viewWS, _RimPower);
                // 可选：只在背光一侧显示亮边（经典的“轮廓光”打法），受光侧交给正常光照
                float NdotL = dot(N, GetMainLight().direction);
                float lightMask = mix(1.0, smoothstep(0.2, -0.4, NdotL), _RimLightMask);
                color += _RimColor.rgb * rim * _RimIntensity * lightMask;
                fragColor = vec4(color, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #define SHADOW_PASS
            #include "Ch18/Ch18ShadowPass.glsl"
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #define DEPTH_PASS
            #include "Ch18/Ch18ShadowPass.glsl"
            ENDGLSL
        }
    }
}
