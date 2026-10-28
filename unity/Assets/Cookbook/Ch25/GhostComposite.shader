// 案例 25.7：把“幽灵层”RT 半透明地合成回屏幕，并与场景深度比较实现正确遮挡。
Shader "Cookbook/Ch25/GhostComposite"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            Name "GhostComposite"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            float4 _BlitTexture_TexelSize;
            TEXTURE2D_X_FLOAT(_GhostDepth);      // 幽灵层自己的深度
            float  _Opacity;
            float4 _Tint;
            float4 _RimColor;
            float  _RimWidth;

            //#region frag
            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                half4 ghost = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_PointClamp, uv);

                // 1) 遮挡：幽灵层深度 与 场景深度 都换成线性深度再比较，与平台的 Reversed-Z 无关
                float ghostEye = LinearEyeDepth(SAMPLE_TEXTURE2D_X(_GhostDepth, sampler_PointClamp, uv).r, _ZBufferParams);
                float sceneEye = LinearEyeDepth(SampleSceneDepth(uv), _ZBufferParams);
                half visible = step(ghostEye, sceneEye + 0.01);

                // 2) 轮廓光：覆盖率（alpha）在邻域里的最小值 < 1 说明靠近剪影边缘
                float2 r = _BlitTexture_TexelSize.xy * _RimWidth;
                half minA = ghost.a;
                minA = min(minA, SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2( r.x, 0)).a);
                minA = min(minA, SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(-r.x, 0)).a);
                minA = min(minA, SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(0,  r.y)).a);
                minA = min(minA, SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv + float2(0, -r.y)).a);
                half rim = ghost.a * (1.0 - minA);

                // 3) 整层统一透明度：内部的穿插面在离屏 RT 里已被深度测试剔除，合成时看不到
                half3 rgb = ghost.rgb * _Tint.rgb + _RimColor.rgb * rim;
                half alpha = saturate(ghost.a * _Opacity + rim) * visible;
                return half4(rgb, alpha);
            }
            //#endregion
            ENDHLSL
        }
    }
}
