// 案例 28.1：从深度重建世界坐标的两种方法，并把结果可视化。
// Pass 0：逆 VP 矩阵法，输出 frac(positionWS)；Pass 1：视锥射线法，在原画面上叠加 1 米世界网格；
// Pass 2：两种方法的差值放大显示（用来验证两者一致）。
Shader "Cookbook/Ch28/ReconstructWorldPos"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off

        GLSLINCLUDE
        uniform vec4 _GridColor;
        uniform float _GridWidth;
        uniform float _DiffScale;
        ENDGLSL

        Pass
        {
            Name "InvVP"
            GLSLPROGRAM
            #include "Ch28/ScreenSpaceCommon.glsl"
            #ifdef FRAGMENT
            //#region frag0
            vec4 Frag()
            {
                vec2 uv = texcoord;
                vec4 sceneColor = SamplePointClamp(_BlitTexture, uv);
                float depth = SampleDeviceDepth(uv);
                if (IsSkyDepth(depth)) return sceneColor * 0.35;   // 天空没有几何，压暗区分
                vec3 positionWS = ReconstructPositionWS(uv, depth);
                // +0.5：避开地面 y=0 这种整数坐标，frac 在 0/1 之间来回跳会产生噪点
                return vec4(fract(positionWS + 0.5), 1.0);
            }
            //#endregion
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ViewRay"
            GLSLPROGRAM
            #define USE_VIEW_RAY
            #include "Ch28/ScreenSpaceCommon.glsl"
            #ifdef FRAGMENT
            //#region frag1
            vec4 Frag()
            {
                vec2 uv = texcoord;
                vec4 sceneColor = SamplePointClamp(_BlitTexture, uv);
                float rawDepth = SampleSceneDepth(uv);
                if (IsSkyDepth(rawDepth)) return sceneColor;
                vec3 positionWS = ReconstructPositionWSFromRay(farRayWS, rawDepth);

                // 1 米网格线：用 fwidth 把线宽换算成像素，远近粗细一致
                vec3 dist = abs(fract(positionWS + 0.5) - 0.5);
                vec3 width = fwidth(positionWS) * _GridWidth;
                vec3 lines = 1.0 - smoothstep(width * 0.5, width * 1.5, dist);
                float grid = saturate(max(lines.x, max(lines.y, lines.z)));
                return mix(sceneColor, _GridColor, grid * 0.85);
            }
            //#endregion
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "Diff"
            GLSLPROGRAM
            #define USE_VIEW_RAY
            #include "Ch28/ScreenSpaceCommon.glsl"
            #ifdef FRAGMENT
            void main()
            {
                vec2 uv = texcoord;
                float rawDepth = SampleSceneDepth(uv);
                vec3 a = ReconstructPositionWS(uv, SampleDeviceDepth(uv));
                vec3 b = ReconstructPositionWSFromRay(farRayWS, rawDepth);
                fragColor = vec4(saturate(abs(a - b) * _DiffScale), 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
