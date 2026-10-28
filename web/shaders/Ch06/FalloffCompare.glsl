// 案例 6.2 点光/聚光的衰减：URP 的平滑衰减 vs 纯平方反比 vs 线性衰减（GLSL 版，对应 Ch06/FalloffCompare.shader）
Shader "Cookbook/Ch06/FalloffCompare"
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
            #pragma shader_feature_local_fragment _FALLOFF_URP _FALLOFF_INVERSESQUARE _FALLOFF_LINEAR

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
            //#region punctual
            // 不用 GetAdditionalLight()，直接读 URP 上传的光源数组，自己算衰减。
            // （网页版的光源数组与 URP 14 同名：_AdditionalLightsPosition / Color / Attenuation / SpotDir）
            vec3 PunctualLight(int loopIndex, vec3 positionWS, vec3 normalWS)
            {
                // Forward+：循环变量就是全局光源下标；Forward：先查“本物体的第几盏灯”对应的全局下标。
                // HLSL 版用 #if USE_FORWARD_PLUS 区分；网页版的 GetPerObjectLightIndex 在 Forward+ 下原样返回
                int i = GetPerObjectLightIndex(loopIndex);
                vec4 lightPos   = _AdditionalLightsPosition[i];     // w = 0 表示方向光
                vec3 color      = _AdditionalLightsColor[i].rgb;
                vec4 attenParam = _AdditionalLightsAttenuation[i];  // x = 1/range²，zw = 聚光角度参数
                vec4 spotDir    = _AdditionalLightsSpotDir[i];

                vec3  lightVector = lightPos.xyz - positionWS * lightPos.w;
                float d2 = max(dot(lightVector, lightVector), HALF_MIN);
                vec3  L = lightVector * inversesqrt(d2);

            #if defined(_FALLOFF_INVERSESQUARE)
                float atten = 1.0 / d2;                                        // 物理上的平方反比，没有窗口
            #elif defined(_FALLOFF_LINEAR)
                float atten = saturate(1.0 - sqrt(d2 * attenParam.x));         // 1 - d/range
            #else
                float atten = DistanceAttenuation(d2, attenParam.xy);          // URP：平方反比 × 平滑窗口
            #endif
                atten *= AngleAttenuation(spotDir.xyz, L, attenParam.zw);      // 聚光锥；点光的参数让它恒为 1

                return color * atten * saturate(dot(normalWS, L));
            }
            //#endregion

            // ---- 网页版专用：模拟 Forward+ 的分簇剔除（HLSL 版没有这段，由 URP 的 LIGHT_LOOP_BEGIN 自动完成）----
            // URP 的 Forward+ 把屏幕切成 8×8 像素的 tile，再按深度分段（z-bin），只有“范围球”碰到当前 tile 与 z-bin 的灯
            // 才会进入这个像素的光源循环。网页版没有分簇结构，这里逐像素做同样的判断，好让“纯平方反比”在灯的 Range
            // 之外被截断、露出 tile 形状的锯齿边——这正是本案例要演示的现象
            bool ForwardPlusClusterHasLight(int i, vec3 positionWS)
            {
                vec4 lp = _AdditionalLightsPosition[i];
                if (lp.w == 0.0) return true;                                 // 方向光不参与分簇
                float r = inversesqrt(max(_AdditionalLightsAttenuation[i].x, 1e-8));
                vec3 c = TransformWorldToView(lp.xyz);                        // 观察空间：相机朝 -z
                // z-bin：像素深度要落在灯的 [深度 - r, 深度 + r] 里
                float z = -TransformWorldToView(positionWS).z;
                if (z < -c.z - r || z > -c.z + r) return false;
                // tile：把灯心投影到屏幕上，夹到当前 tile 的矩形里，取过这一点的视线；
                // 灯心到这条视线的距离小于 r，就认为范围球碰到了这个 tile 的视锥
                vec2 p = vec2(unity_MatrixP[0][0], unity_MatrixP[1][1]);
                vec2 t0 = floor(gl_FragCoord.xy / 8.0) * 8.0;
                vec2 ndcMin = t0 / _ScreenParams.xy * 2.0 - 1.0, ndcMax = (t0 + 8.0) / _ScreenParams.xy * 2.0 - 1.0;
                vec2 ndcC = c.z < 0.0 ? c.xy * p / -c.z : vec2(0.0);
                vec3 d = normalize(vec3(clamp(ndcC, ndcMin, ndcMax) / p, -1.0));
                vec3 closest = d * max(dot(c, d), 0.0);
                return length(c - closest) < r;
            }

            void main()
            {
                vec3 albedo = texture(_BaseMap, uv).rgb * _BaseColor.rgb;
                vec3 N = normalize(normalWS);

                InputData inputData = InitInputData();
                inputData.positionWS = positionWS;
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(gl_FragCoord);

                Light mainLight = GetMainLight();
                vec3 lighting = mainLight.color * mainLight.distanceAttenuation * saturate(dot(N, mainLight.direction));

            #if defined(_ADDITIONAL_LIGHTS)
                // HLSL 版：Forward+ 先循环附加方向光，再 LIGHT_LOOP_BEGIN；网页版统一成普通 for（见案例 6.1）
                int lightCount = GetAdditionalLightsCount();
                for (int lightIndex = 0; lightIndex < lightCount; lightIndex++)
                {
                    // Forward+（_PerObjectLights = 0）时模拟分簇剔除；Forward 路径按物体选灯，不受 Range 截断
                    if (_PerObjectLights < 0.5 && !ForwardPlusClusterHasLight(lightIndex, inputData.positionWS)) continue;
                    lighting += PunctualLight(lightIndex, inputData.positionWS, N);
                }
            #endif

                vec3 color = albedo * lighting + albedo * SampleSH(N) * _AmbientStrength;
                fragColor = vec4(color, 1.0);
            }
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
