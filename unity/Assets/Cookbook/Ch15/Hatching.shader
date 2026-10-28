// 素描排线（Hatching）：按受光强度在 6 级笔触贴图（TAM）之间混合。
// 两张 RGB 贴图共 6 个通道，一次采样拿到 3 级，2 次采样完成全部混合。
Shader "Cookbook/Ch15/Hatching"
{
    Properties
    {
        [NoScaleOffset] _Hatch0 ("Hatch 0 (levels 1-3)", 2D) = "white" {}
        [NoScaleOffset] _Hatch1 ("Hatch 1 (levels 4-6)", 2D) = "white" {}
        _HatchScale ("Hatch Tiling", Float) = 4
        [Toggle] _ScreenSpace ("Screen Space UV", Float) = 0
        _ScreenTileSize ("Screen Tile Size (pixels)", Float) = 160
        _InkColor ("Ink Color", Color) = (0.08, 0.07, 0.1, 1)
        _PaperColor ("Paper Color", Color) = (0.96, 0.94, 0.88, 1)
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _Tint ("Base Color Tint", Range(0, 1)) = 0
        _Ambient ("Ambient Tone", Range(0, 1)) = 0.12
        _Exposure ("Exposure", Range(0.2, 2)) = 1
        _OutlineWidth ("Outline Width", Range(0, 0.05)) = 0.008
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float _HatchScale, _ScreenSpace, _ScreenTileSize;
            half4 _InkColor, _PaperColor, _BaseColor;
            half  _Tint, _Ambient, _Exposure;
            float _OutlineWidth;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex NprVert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #include "Assets/Cookbook/Ch15/NPRCommon.hlsl"

            TEXTURE2D(_Hatch0); SAMPLER(sampler_Hatch0);
            TEXTURE2D(_Hatch1); SAMPLER(sampler_Hatch1);

            //#region hatch
            // intensity：1 = 最亮（纸白），0 = 最暗（第 6 级）
            half Hatch(float2 uv, half intensity)
            {
                half3 h0 = SAMPLE_TEXTURE2D(_Hatch0, sampler_Hatch0, uv).rgb;
                half3 h1 = SAMPLE_TEXTURE2D(_Hatch1, sampler_Hatch1, uv).rgb;

                // 把亮度映射到 0..6：0 = 纸白，k = 第 k 级笔触
                half level = (1.0h - intensity) * 6.0h;
                // 帐篷形权重：离 level 最近的两级各分一部分，总和恒为 1
                half3 w0 = saturate(1.0h - abs(level - half3(1, 2, 3)));
                half3 w1 = saturate(1.0h - abs(level - half3(4, 5, 6)));
                half  wWhite = saturate(1.0h - level);

                return wWhite + dot(h0, w0) + dot(h1, w1);
            }
            //#endregion

            //#region frag
            half4 frag(NprVaryings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                NprLight L = GetNprLight(i.positionWS, N);

                // 只关心“明暗”，不关心光的颜色：先算一个标量亮度
                half light = saturate(L.ndotl) * L.shadow * Luminance(L.color);
                half intensity = saturate((light * (1.0h - _Ambient) + _Ambient) * _Exposure);

                // 两种 UV：物体 UV（笔触贴在表面上）/ 屏幕 UV（笔触固定在画面上，每 _ScreenTileSize 像素重复一次）
                float2 screenUV = i.positionCS.xy / _ScreenTileSize;
                float2 uv = lerp(i.uv * _HatchScale, screenUV, _ScreenSpace);

                half h = Hatch(uv, intensity);
                half3 paper = _PaperColor.rgb * lerp(1.0h, _BaseColor.rgb, _Tint);
                half3 col = lerp(_InkColor.rgb, paper, h);
                return half4(col, 1);
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            struct A { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            float4 vert(A v) : SV_POSITION
            {
                float4 positionCS = TransformObjectToHClip(v.positionOS.xyz);
                float3 normalCS = mul((float3x3)UNITY_MATRIX_VP, TransformObjectToWorldNormal(v.normalOS));
                float2 offset = normalize(normalCS.xy) * _OutlineWidth * positionCS.w;
                offset.x *= _ScreenParams.y / _ScreenParams.x;
                positionCS.xy += offset;
                return positionCS;
            }
            half4 frag() : SV_Target { return _InkColor; }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex NprShadowVert
            #pragma fragment NprNullFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch15/NPRCommon.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex NprDepthVert
            #pragma fragment NprNullFrag
            #include "Assets/Cookbook/Ch15/NPRCommon.hlsl"
            ENDHLSL
        }
    }
}
