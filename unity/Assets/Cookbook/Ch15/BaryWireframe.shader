// 重心坐标线框：网格的顶点色里预先烘焙了重心坐标 (1,0,0)/(0,1,0)/(0,0,1)，
// 光栅化插值后，某个分量接近 0 就说明像素靠近对应的边。fwidth 让线宽以“像素”为单位恒定。
Shader "Cookbook/Ch15/BaryWireframe"
{
    Properties
    {
        _BaseColor ("Fill Color", Color) = (0.85, 0.87, 0.9, 1)
        _WireColor ("Wire Color", Color) = (0.1, 0.35, 0.55, 1)
        _WireWidth ("Wire Width (pixels)", Range(0.5, 5)) = 1.5
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor, _WireColor;
            float _WireWidth;
        CBUFFER_END

        //#region wire
        // 返回 0..1 的“线框覆盖度”。bary 来自顶点色插值。
        float WireFactor(float3 bary, float widthPixels)
        {
            float3 d = fwidth(bary);                    // 每个分量在一个像素内的变化量
            float3 a = smoothstep(d * (widthPixels - 0.5), d * (widthPixels + 0.5), bary);
            return 1.0 - min(a.x, min(a.y, a.z));       // 任一分量接近 0 → 在边上
        }
        //#endregion
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

            half4 frag(NprVaryings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                NprLight L = GetNprLight(i.positionWS, N);
                half3 fill = _BaseColor.rgb * (saturate(L.ndotl) * L.shadow * L.color + SampleSH(N));
                float w = WireFactor(i.color.rgb, _WireWidth);
                return half4(lerp(fill, _WireColor.rgb, w), 1);
            }
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
