// 案例 28.3：距离雾 + 高度雾（解析积分）+ 太阳方向的内散射着色。
// 两种雾都换算成“光学厚度 τ”，相加后统一用 T = exp(-τ) 求透射率，这样叠加在物理上是自洽的。
Shader "Cookbook/Ch28/HeightFog"
{
    Properties
    {
        _FogColor ("Fog Color", Color) = (0.62, 0.68, 0.76, 1)
        [Header(Distance Fog)]
        _DistanceDensity ("Distance Density (1/m)", Float) = 0.04
        _FogStart ("Start Distance", Float) = 2
        [Header(Height Fog)]
        _HeightDensity ("Height Density at Base (1/m)", Float) = 0.25
        _HeightFalloff ("Height Falloff (1/m)", Float) = 1.2
        _FogBaseHeight ("Base Height", Float) = 0
        [Header(Sky and Sun)]
        _SkyDistance ("Distance Used For Sky", Float) = 120
        _SunScatterColor ("Sun Scatter Tint", Color) = (1, 0.8, 0.55, 1)
        _SunScatterPower ("Sun Scatter Power", Float) = 8
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off

        Pass
        {
            Name "HeightFog"
            HLSLPROGRAM
            #pragma vertex VertRay
            #pragma fragment Frag
            #include "Assets/Cookbook/Ch28/ScreenSpaceCommon.hlsl"
            // Shadows.hlsl 用到 CommonMaterial.hlsl 里的 LerpWhiteTo，但自己没 include（Lit 走 Lighting.hlsl 时会间接带上）
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/RealtimeLights.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _FogColor, _SunScatterColor;
                float _DistanceDensity, _FogStart, _HeightDensity, _HeightFalloff, _FogBaseHeight;
                float _SkyDistance, _SunScatterPower;
            CBUFFER_END

            //#region heightfog
            // 高度雾的光学厚度：密度 σ(y) = a·exp(-b·(y - h0))，沿射线 c + t·v (0≤t≤L) 积分
            float HeightFogOpticalDepth(float3 camPos, float3 viewDir, float rayLength)
            {
                float a = _HeightDensity, b = _HeightFalloff;
                float densityAtCam = a * exp(-b * (camPos.y - _FogBaseHeight));
                float k = b * viewDir.y * rayLength;          // 射线跨过的“高度衰减量”
                // (1 - e^{-k}) / k 在 k→0 时趋于 1；用泰勒展开避免水平视线除零
                float factor = abs(k) > 1e-3 ? (1 - exp(-k)) / k : 1 - 0.5 * k;
                return densityAtCam * rayLength * factor;
            }
            //#endregion

            //#region frag
            half4 Frag(VaryingsRay input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, uv);
                float rawDepth = SampleSceneDepth(uv);

                float3 viewDir = normalize(input.farRayWS);
                float rayLength = IsSkyDepth(rawDepth) ? _SkyDistance
                                : length(ReconstructPositionWSFromRay(input.farRayWS, rawDepth) - _WorldSpaceCameraPos);

                float tauDistance = _DistanceDensity * max(0, rayLength - _FogStart);
                float tauHeight = HeightFogOpticalDepth(_WorldSpaceCameraPos, viewDir, rayLength);
                float transmittance = exp(-(tauDistance + tauHeight));

                // 朝太阳看时雾更亮更暖（前向散射的廉价近似）
                Light mainLight = GetMainLight();
                float sunAmount = pow(saturate(dot(viewDir, mainLight.direction)), _SunScatterPower);
                half3 fogColor = lerp(_FogColor.rgb, _SunScatterColor.rgb * mainLight.color, sunAmount);

                color.rgb = color.rgb * transmittance + fogColor * (1 - transmittance);
                return color;
            }
            //#endregion
            ENDHLSL
        }
    }
}
