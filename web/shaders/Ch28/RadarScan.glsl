// 案例 28.2：扫描线 / 雷达波。用重建出的世界坐标算到扫描中心的距离，
// 在“波前”附近画一圈亮边，波前后方拖一条渐隐的尾迹，尾迹里显示世界空间网格。
Shader "Cookbook/Ch28/RadarScan"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off

        Pass
        {
            Name "RadarScan"
            GLSLPROGRAM
            #define USE_VIEW_RAY
            #include "Ch28/ScreenSpaceCommon.glsl"

            uniform vec4 _ScanCenter;
            uniform float _UseTime, _Progress, _Speed, _MaxRadius, _TrailWidth, _EdgeWidth, _GridSize;
            uniform vec4 _ScanColor;

            #ifdef FRAGMENT
            //#region frag
            vec4 Frag()
            {
                vec2 uv = texcoord;
                vec4 color = SamplePointClamp(_BlitTexture, uv);
                float rawDepth = SampleSceneDepth(uv);
                vec3 positionWS = ReconstructPositionWSFromRay(farRayWS, rawDepth);

                // 当前波前半径：运行时用 _Time 循环，拍摄/调试时用 _Progress 定格
                float t = _UseTime > 0.5 ? fract(_Time.y * _Speed) : _Progress;
                float radius = t * _MaxRadius;

                // 水平距离：只看 xz，扫描波像贴着地面向外扩
                float d = distance(positionWS.xz, _ScanCenter.xz);
                float behind = radius - d;                     // >0 表示已被波前扫过

                // 波前亮边：|behind| 很小的一圈
                float edge = 1.0 - smoothstep(0.0, _EdgeWidth, abs(behind));
                // 尾迹：波前后方 _TrailWidth 米内从 1 渐隐到 0
                float trail = (behind > 0.0) ? pow(saturate(1.0 - behind / _TrailWidth), 2.0) : 0.0;

                // 尾迹里的世界网格（xz 平面），fwidth 让线宽恒定为 ~1 像素
                vec2 g = abs(fract(positionWS.xz / _GridSize + 0.5) - 0.5) * _GridSize;
                vec2 gw = fwidth(positionWS.xz);
                float grid = 1.0 - min(smoothstep(gw.x * 0.5, gw.x * 1.5, g.x), smoothstep(gw.y * 0.5, gw.y * 1.5, g.y));

                // 越扩越淡，扫完一圈自然消失
                float fade = 1.0 - smoothstep(0.7, 1.0, t);
                float intensity = (edge * 1.5 + trail * (0.25 + 0.75 * grid)) * fade;
                // 天空没有几何：放在 fwidth 之后再返回（GLSL 的导数要求同一像素块里的控制流一致）
                if (IsSkyDepth(rawDepth)) return color;
                color.rgb += _ScanColor.rgb * intensity;
                return color;
            }
            //#endregion
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }
    }
}
