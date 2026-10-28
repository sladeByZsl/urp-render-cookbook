// 案例 6.3 接收主光源阴影：Lambert + MainLightRealtimeShadow（GLSL 版，对应 Ch06/ShadowReceive.shader）
Shader "Cookbook/Ch06/ShadowReceive"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseMap_ST;
        uniform vec4  _BaseColor;
        uniform float _AmbientStrength;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            //#region keywords
            // 主光阴影：无 / 单张阴影图 / 级联 / 屏幕空间（由 URP Asset 与 Renderer 设置决定，运行时自动开关）。
            // 软阴影：_SHADOWS_SOFT 在运行时按每盏灯的质量分支。
            // 这两组是 URP 全局关键字，网页版引擎始终定义 _MAIN_LIGHT_SHADOWS 与 _SHADOWS_SOFT，不用声明。
            // 材质级开关：不接收阴影
            #pragma shader_feature_local _RECEIVE_SHADOWS_OFF
            //#endregion

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

                // 世界坐标 -> 阴影图坐标（xy = 阴影图 UV，z = 在光源空间里的深度）。
                // 开了级联时，这里会先按距离选出级联号，再用对应的矩阵变换
                vec4 shadowCoord = TransformWorldToShadowCoord(positionWS);

                // 采样阴影图并与 z 比较：1 = 受光，0 = 在阴影里（软阴影时是 0~1 的过渡）。
                // URP 的 MainLightRealtimeShadow 在 _RECEIVE_SHADOWS_OFF 时直接返回 1（宏 MAIN_LIGHT_CALCULATE_SHADOWS 未定义）
            #if defined(_RECEIVE_SHADOWS_OFF)
                float shadow = 1.0;
            #else
                float shadow = MainLightRealtimeShadow(shadowCoord);
            #endif

                // 超出“阴影距离”的地方，阴影要平滑淡出，而不是突然消失
                shadow = mix(shadow, 1.0, GetMainLightShadowFade(positionWS));

                Light mainLight = GetMainLight();
                vec3 radiance = mainLight.color * mainLight.distanceAttenuation * shadow;
                vec3 color = albedo * radiance * saturate(dot(N, mainLight.direction));
                color += albedo * SampleSH(N) * _AmbientStrength;
                fragColor = vec4(color, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }

        // ---- 投影与深度：见案例 6.4 与 6.8 ----
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0

            GLSLPROGRAM
            #include "Ch06/ShadowCasterPass.glsl"
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask R

            GLSLPROGRAM
            #include "Ch06/DepthOnlyPass.glsl"
            ENDGLSL
        }
    }
}
