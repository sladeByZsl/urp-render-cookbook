// 案例 28.2：扫描线 / 雷达波。用重建出的世界坐标算到扫描中心的距离，
// 在“波前”附近画一圈亮边，波前后方拖一条渐隐的尾迹，尾迹里显示世界空间网格。
Shader "Cookbook/Ch28/RadarScan"
{
    Properties
    {
        _ScanCenter ("Scan Center (WS)", Vector) = (0, 0, 0, 0)
        [Toggle] _UseTime ("Use _Time", Float) = 0
        _Progress ("Progress (0-1, 拍摄用)", Range(0, 1)) = 0.5
        _Speed ("Speed (圈/秒)", Float) = 0.25
        _MaxRadius ("Max Radius", Float) = 20
        _TrailWidth ("Trail Width", Float) = 4
        _EdgeWidth ("Edge Width", Float) = 0.15
        [HDR] _ScanColor ("Scan Color", Color) = (0.2, 1.6, 2.4, 1)
        _GridSize ("Grid Size", Float) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off

        Pass
        {
            Name "RadarScan"
            HLSLPROGRAM
            #pragma vertex VertRay
            #pragma fragment Frag
            #include "Assets/Cookbook/Ch28/ScreenSpaceCommon.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _ScanCenter;
                float _UseTime, _Progress, _Speed, _MaxRadius, _TrailWidth, _EdgeWidth, _GridSize;
                half4 _ScanColor;
            CBUFFER_END

            //#region frag
            half4 Frag(VaryingsRay input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, uv);
                float rawDepth = SampleSceneDepth(uv);
                if (IsSkyDepth(rawDepth)) return color;
                float3 positionWS = ReconstructPositionWSFromRay(input.farRayWS, rawDepth);

                // 当前波前半径：运行时用 _Time 循环，拍摄/调试时用 _Progress 定格
                float t = _UseTime > 0.5 ? frac(_Time.y * _Speed) : _Progress;
                float radius = t * _MaxRadius;

                // 水平距离：只看 xz，扫描波像贴着地面向外扩
                float d = distance(positionWS.xz, _ScanCenter.xz);
                float behind = radius - d;                     // >0 表示已被波前扫过

                // 波前亮边：|behind| 很小的一圈
                float edge = 1 - smoothstep(0, _EdgeWidth, abs(behind));
                // 尾迹：波前后方 _TrailWidth 米内从 1 渐隐到 0
                float trail = (behind > 0) ? pow(saturate(1 - behind / _TrailWidth), 2) : 0;

                // 尾迹里的世界网格（xz 平面），fwidth 让线宽恒定为 ~1 像素
                float2 g = abs(frac(positionWS.xz / _GridSize + 0.5) - 0.5) * _GridSize;
                float2 gw = fwidth(positionWS.xz);
                float grid = 1 - min(smoothstep(gw.x * 0.5, gw.x * 1.5, g.x), smoothstep(gw.y * 0.5, gw.y * 1.5, g.y));

                // 越扩越淡，扫完一圈自然消失
                float fade = 1 - smoothstep(0.7, 1.0, t);
                float intensity = (edge * 1.5 + trail * (0.25 + 0.75 * grid)) * fade;
                color.rgb += _ScanColor.rgb * intensity;
                return color;
            }
            //#endregion
            ENDHLSL
        }
    }
}
