// 抖动透明（Dither / Screen-door Transparency）：不混合，而是按屏幕位置的阈值图案丢弃一部分像素。
// 物体仍然是不透明队列、写深度、不需要排序；代价是近看能看到网点。阴影 Pass 用同样的抖动。
Shader "Cookbook/Ch16/DitherFade"
{
    Properties
    {
        _BaseColor ("Color", Color) = (0.9, 0.5, 0.25, 1)
        _Fade ("Opacity", Range(0, 1)) = 0.5
        [Toggle] _DitherShadow ("Dither In Shadow Pass", Float) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }

        HLSLINCLUDE
        #include "Assets/Cookbook/Ch16/Ch16Common.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
            half  _Fade;
            float _DitherShadow;
        CBUFFER_END

        //#region bayer
        // 4×4 Bayer 矩阵：16 个阈值均匀分布在 0..1，且相邻像素的阈值尽量“错开”
        float Bayer4x4(uint2 p)
        {
            const float m[16] = {
                 0.0,  8.0,  2.0, 10.0,
                12.0,  4.0, 14.0,  6.0,
                 3.0, 11.0,  1.0,  9.0,
                15.0,  7.0, 13.0,  5.0 };
            p %= 4;
            return (m[p.y * 4 + p.x] + 0.5) / 16.0;
        }

        // opacity 为 0.5 时，正好有一半像素的阈值低于它而被保留
        void DitherClip(float2 pixelPos, half opacity)
        {
            clip(opacity - Bayer4x4((uint2)pixelPos));
        }
        //#endregion
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex Ch16Vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            half4 frag(Varyings i) : SV_Target
            {
                DitherClip(i.positionCS.xy, _Fade);     // SV_POSITION.xy 在片元里就是像素坐标
                return half4(SimpleLighting(_BaseColor.rgb, normalize(i.normalWS), i.positionWS, 0.5h), 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            float4 vert(Attributes v) : SV_POSITION { return Ch16ShadowPositionCS(v.positionOS.xyz, v.normalOS); }
            half4 frag(float4 positionCS : SV_POSITION) : SV_Target
            {
                // 阴影贴图里的“像素”是阴影贴图的纹素，抖动后经过 PCF 软阴影过滤，会得到浅一些的阴影
                if (_DitherShadow > 0.5) DitherClip(positionCS.xy, _Fade);
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            float4 vert(Attributes v) : SV_POSITION { return TransformObjectToHClip(v.positionOS.xyz); }
            half4 frag(float4 positionCS : SV_POSITION) : SV_Target { DitherClip(positionCS.xy, _Fade); return 0; }
            ENDHLSL
        }
    }
}
