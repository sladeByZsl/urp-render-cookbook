// 案例 6.1 多光源 Lambert：主光 + 附加光循环，同时支持 Forward 与 Forward+（GLSL 版，对应 Ch06/MultiLightLambert.shader）
Shader "Cookbook/Ch06/MultiLightLambert"
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
            // Forward 路径：URP 按 Asset 的“Additional Lights”设置打开 _ADDITIONAL_LIGHTS（逐像素）
            // 或 _ADDITIONAL_LIGHTS_VERTEX（逐顶点）；Forward+ 路径打开 _FORWARD_PLUS。
            // 网页版引擎始终定义 _ADDITIONAL_LIGHTS（逐像素），Forward / Forward+ 的区别由引擎在
            // GetAdditionalLightsCount() / GetAdditionalLight() 内部处理（见下面的循环）
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            //#endregion

            uniform sampler2D _BaseMap;

            VARYING vec2 uv;
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
        #if defined(_ADDITIONAL_LIGHTS_VERTEX)
            VARYING vec3 vertexLight;
        #endif

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = pos.positionCS;
                positionWS = pos.positionWS;
                normalWS = TransformObjectToWorldNormal(normalOS);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            #if defined(_ADDITIONAL_LIGHTS_VERTEX)
                // 逐顶点模式：URP 的 VertexLighting() 在顶点里把所有附加光的 Lambert 累加好
                vertexLight = vec3(0.0);
                for (int i = 0; i < GetAdditionalLightsCount(); i++)
                {
                    Light l = GetAdditionalPerObjectLight(i, pos.positionWS);
                    vertexLight += LightingLambert(l.color * l.distanceAttenuation, l.direction, normalWS);
                }
            #endif
            }
            #endif

            #ifdef FRAGMENT
            vec3 LambertLight(Light light, vec3 normalWS)
            {
                vec3 radiance = light.color * (light.distanceAttenuation * light.shadowAttenuation);
                return radiance * saturate(dot(normalWS, light.direction));
            }

            //#region frag
            void main()
            {
                vec3 albedo = texture(_BaseMap, uv).rgb * _BaseColor.rgb;
                vec3 N = normalize(normalWS);

                // HLSL 版里 LIGHT_LOOP_BEGIN 在 Forward+ 下会直接读取名为 inputData 的变量，所以要先填好它；
                // GLSL 版的循环是普通 for，这里保留同样的写法便于对照
                InputData inputData = InitInputData();
                inputData.positionWS = positionWS;
                inputData.normalWS = N;
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(gl_FragCoord);

                // 主光源
                vec3 lighting = LambertLight(GetMainLight(), N);

            #if defined(_ADDITIONAL_LIGHTS)
                // Forward：lightCount = 本物体受影响的灯数（Per Object Limit 以内），循环变量是“本物体的第几盏灯”；
                // Forward+：HLSL 版先单独循环附加的方向光，再用 LIGHT_LOOP_BEGIN 遍历当前像素所在 tile / z-bin 的灯。
                // 网页版没有分簇结构，Forward+ 下 GetAdditionalLightsCount() 直接返回全部可见附加光（方向光排在最前面），
                // 所以两种路径都写成同一个普通 for 循环
                int lightCount = GetAdditionalLightsCount();
                for (int lightIndex = 0; lightIndex < lightCount; lightIndex++)
                {
                    Light light = GetAdditionalLight(lightIndex, inputData.positionWS);
                    lighting += LambertLight(light, N);
                }
            #endif

            #if defined(_ADDITIONAL_LIGHTS_VERTEX)
                lighting += vertexLight;
            #endif

                vec3 color = albedo * lighting + albedo * SampleSH(N) * _AmbientStrength;
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
