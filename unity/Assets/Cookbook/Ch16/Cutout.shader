// 镂空材质的三种做法：
//   Alpha Clip：clip() 硬裁剪，边缘锯齿，远处细线会因 mip 平均而消失；
//   Alpha to Coverage（A2C）：把 alpha 转成 MSAA 的覆盖掩码，边缘有 MSAA 级别的过渡（需要开 MSAA）；
//   A2C + 锐化：用 fwidth 把 alpha 重新拉成“一个像素宽的过渡”，既保住细线又不发虚。
Shader "Cookbook/Ch16/Cutout"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor ("Color", Color) = (1, 1, 1, 1)
        _Cutoff ("Alpha Cutoff", Range(0, 1)) = 0.5
        [Enum(Off, 0, On, 1)] _AlphaToMask ("Alpha To Coverage", Float) = 0
        [Toggle] _Sharpen ("Sharpen Alpha (for A2C)", Float) = 0
        [Toggle] _MipScale ("Preserve Coverage Over Mips", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }

        HLSLINCLUDE
        #include "Assets/Cookbook/Ch16/Ch16Common.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            half  _Cutoff;
            float _AlphaToMask, _Sharpen, _MipScale;
            float4 _BaseMap_TexelSize;
        CBUFFER_END
        TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

        //#region alpha
        half CutoutAlpha(float2 uv)
        {
            half a = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv).a * _BaseColor.a;
            if (_MipScale > 0.5)
            {
                // 远处 mip 把细线和透明背景平均成很低的 alpha，裁剪后线条就“断”了。
                // 按 mip 级别把 alpha 放大一些，抵消平均带来的损失（经验做法，系数可调）
                float2 texel = uv * _BaseMap_TexelSize.zw;
                float2 dx = ddx(texel), dy = ddy(texel);
                float mip = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
                a *= 1.0 + mip * 0.3;
            }
            return a;
        }
        //#endregion
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull Off
            AlphaToMask [_AlphaToMask]
            HLSLPROGRAM
            #pragma vertex Ch16Vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH

            //#region frag
            half4 frag(Varyings i, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
            {
                float2 uv = TRANSFORM_TEX(i.uv, _BaseMap);
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv);
                half a = CutoutAlpha(uv);

                if (_AlphaToMask > 0.5)
                {
                    if (_Sharpen > 0.5)
                    {
                        // 以 cutoff 为中心，把 alpha 的过渡压缩到约一个像素宽
                        a = (a - _Cutoff) / max(fwidth(a), 1e-4) + 0.5;
                    }
                    a = saturate(a);
                }
                else
                {
                    clip(a - _Cutoff);    // 经典 Alpha Test
                    a = 1;
                }

                float3 N = normalize(i.normalWS) * IS_FRONT_VFACE(face, 1.0, -1.0);
                half3 col = SimpleLighting(tex.rgb * _BaseColor.rgb, N, i.positionWS, 0.2h);
                return half4(col, a);     // 开启 A2C 时，这个 alpha 决定 MSAA 子样本覆盖了几个
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            struct V2F { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };
            V2F vert(Attributes v)
            {
                V2F o;
                o.positionCS = Ch16ShadowPositionCS(v.positionOS.xyz, v.normalOS);
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                return o;
            }
            // 阴影贴图没有 MSAA，只能用硬裁剪
            half4 frag(V2F i) : SV_Target { clip(CutoutAlpha(i.uv) - _Cutoff); return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R Cull Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            struct V2F { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };
            V2F vert(Attributes v)
            {
                V2F o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                return o;
            }
            half4 frag(V2F i) : SV_Target { clip(CutoutAlpha(i.uv) - _Cutoff); return 0; }
            ENDHLSL
        }
    }
}
