// 案例 18.10：X 光扫描线。一道水平光带沿世界 Y 扫过物体，光带后方的“拖尾”区域变成 X 光样式：
// 暗色底 + 菲涅尔轮廓 + 世界空间网格线。全部基于世界坐标，多个物体共用一个扫描高度就能连成一片。
// （GLSL 版，对应 Ch18/ScanLine.shader）
Shader "Cookbook/Ch18/ScanLine"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" "RenderPipeline"="UniversalPipeline" }

        GLSLINCLUDE
        uniform vec4  _BaseColor;
        uniform float _Smoothness;
        uniform vec4  _ScanColor;
        uniform float _ScanHeight;
        uniform float _ScanWidth;
        uniform float _TrailLength;
        uniform float _GridDensity;
        uniform vec4  _XRayTint;
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
            //#region grid
            // 世界空间网格线：三个轴各算一次“离最近整格线有多近”，用 fwidth 保持线宽恒定为约 1 像素以上
            float WorldGrid(vec3 p, float density)
            {
                vec3 g = p * density;
                vec3 dist = abs(fract(g - 0.5) - 0.5);          // 到最近整数的距离
                vec3 w = fwidth(g) * 1.2;
                vec3 lines = 1.0 - saturate(dist / max(w, vec3(1e-4)));
                return max(lines.x, max(lines.y, lines.z));
            }
            //#endregion

            //#region frag
            void main()
            {
                vec3 N = normalize(normalWS);
                vec3 viewWS = GetWorldSpaceNormalizeViewDir(positionWS);
                vec3 lit = SimpleLighting(_BaseColor.rgb, positionWS, N, _Smoothness);

                float d = _ScanHeight - positionWS.y;             // > 0：在扫描线下方（已经被扫过）
                float scanLine = exp(-abs(d) / _ScanWidth);       // 前沿亮线，指数衰减
                float trail = (d > 0.0) ? saturate(1.0 - d / max(_TrailLength, 1e-4)) : 0.0;

                // X 光样式：暗底 + 轮廓 + 网格
                float rim = FresnelRim(N, viewWS, 2.0);
                float grid = WorldGrid(positionWS, _GridDensity);
                vec3 xray = _XRayTint.rgb + _ScanColor.rgb * (rim * 0.8 + grid * 0.5);

                // 拖尾越靠近前沿越“X 光”，远处渐渐恢复正常着色
                vec3 color = mix(lit, xray, smoothstep(0.0, 0.35, trail));
                color += _ScanColor.rgb * scanLine * 2.0;
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
