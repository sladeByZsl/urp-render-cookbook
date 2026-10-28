// 案例 28.3：距离雾 + 高度雾（解析积分）+ 太阳方向的内散射着色。
// 两种雾都换算成“光学厚度 τ”，相加后统一用 T = exp(-τ) 求透射率，这样叠加在物理上是自洽的。
Shader "Cookbook/Ch28/HeightFog"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off

        Pass
        {
            Name "HeightFog"
            GLSLPROGRAM
            #define USE_VIEW_RAY
            #include "Ch28/ScreenSpaceCommon.glsl"

            uniform vec4 _FogColor, _SunScatterColor;
            uniform float _DistanceDensity, _FogStart, _HeightDensity, _HeightFalloff, _FogBaseHeight;
            uniform float _SkyDistance, _SunScatterPower;

            //#region heightfog
            // 高度雾的光学厚度：密度 σ(y) = a·exp(-b·(y - h0))，沿射线 c + t·v (0≤t≤L) 积分
            float HeightFogOpticalDepth(vec3 camPos, vec3 viewDir, float rayLength)
            {
                float a = _HeightDensity, b = _HeightFalloff;
                float densityAtCam = a * exp(-b * (camPos.y - _FogBaseHeight));
                float k = b * viewDir.y * rayLength;          // 射线跨过的“高度衰减量”
                // (1 - e^{-k}) / k 在 k→0 时趋于 1；用泰勒展开避免水平视线除零
                float factor = abs(k) > 1e-3 ? (1.0 - exp(-k)) / k : 1.0 - 0.5 * k;
                return densityAtCam * rayLength * factor;
            }
            //#endregion

            #ifdef FRAGMENT
            //#region frag
            vec4 Frag()
            {
                vec2 uv = texcoord;
                vec4 color = SamplePointClamp(_BlitTexture, uv);
                float rawDepth = SampleSceneDepth(uv);

                vec3 viewDir = normalize(farRayWS);
                float rayLength = IsSkyDepth(rawDepth) ? _SkyDistance
                                : length(ReconstructPositionWSFromRay(farRayWS, rawDepth) - _WorldSpaceCameraPos);

                float tauDistance = _DistanceDensity * max(0.0, rayLength - _FogStart);
                float tauHeight = HeightFogOpticalDepth(_WorldSpaceCameraPos, viewDir, rayLength);
                float transmittance = exp(-(tauDistance + tauHeight));

                // 朝太阳看时雾更亮更暖（前向散射的廉价近似）
                Light mainLight = GetMainLight();
                float sunAmount = pow(saturate(dot(viewDir, mainLight.direction)), _SunScatterPower);
                vec3 fogColor = mix(_FogColor.rgb, _SunScatterColor.rgb * mainLight.color, sunAmount);

                color.rgb = color.rgb * transmittance + fogColor * (1.0 - transmittance);
                return color;
            }
            //#endregion
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }
    }
}
