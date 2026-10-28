// 案例 28.1：从深度重建世界坐标的两种方法，并把结果可视化。
// Pass 0：逆 VP 矩阵法，输出 frac(positionWS)；Pass 1：视锥射线法，在原画面上叠加 1 米世界网格；
// Pass 2：两种方法的差值放大显示（用来验证两者一致）。
Shader "Cookbook/Ch28/ReconstructWorldPos"
{
    Properties
    {
        _GridColor ("Grid Color", Color) = (1, 0.45, 0.1, 1)
        _GridWidth ("Grid Width (px)", Range(0.5, 4)) = 1.2
        _DiffScale ("Diff Scale", Float) = 1000
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZWrite Off ZTest Always Cull Off Blend Off

        HLSLINCLUDE
        #include "Assets/Cookbook/Ch28/ScreenSpaceCommon.hlsl"

        CBUFFER_START(UnityPerMaterial)
            half4 _GridColor;
            float _GridWidth;
            float _DiffScale;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "InvVP"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            //#region frag0
            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                half4 sceneColor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, uv);
                float depth = SampleDeviceDepth(uv);
                if (IsSkyDepth(depth)) return sceneColor * 0.35;   // 天空没有几何，压暗区分
                float3 positionWS = ReconstructPositionWS(uv, depth);
                // +0.5：避开地面 y=0 这种整数坐标，frac 在 0/1 之间来回跳会产生噪点
                return half4(frac(positionWS + 0.5), 1);
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "ViewRay"
            HLSLPROGRAM
            #pragma vertex VertRay
            #pragma fragment Frag
            //#region frag1
            half4 Frag(VaryingsRay input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                half4 sceneColor = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, uv);
                float rawDepth = SampleSceneDepth(uv);
                if (IsSkyDepth(rawDepth)) return sceneColor;
                float3 positionWS = ReconstructPositionWSFromRay(input.farRayWS, rawDepth);

                // 1 米网格线：用 fwidth 把线宽换算成像素，远近粗细一致
                float3 dist = abs(frac(positionWS + 0.5) - 0.5);
                float3 width = fwidth(positionWS) * _GridWidth;
                float3 lines = 1 - smoothstep(width * 0.5, width * 1.5, dist);
                float grid = saturate(max(lines.x, max(lines.y, lines.z)));
                return lerp(sceneColor, _GridColor, grid * 0.85);
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "Diff"
            HLSLPROGRAM
            #pragma vertex VertRay
            #pragma fragment Frag
            half4 Frag(VaryingsRay input) : SV_Target
            {
                float2 uv = input.texcoord;
                float rawDepth = SampleSceneDepth(uv);
                float3 a = ReconstructPositionWS(uv, SampleDeviceDepth(uv));
                float3 b = ReconstructPositionWSFromRay(input.farRayWS, rawDepth);
                return half4(saturate(abs(a - b) * _DiffScale), 1);
            }
            ENDHLSL
        }
    }
}
