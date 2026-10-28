// 案例 21.4：极坐标漩涡传送门——角度 + 半径当 UV，扭转、旋转、向内吸入；顺带处理 atan2 接缝
Shader "Cookbook/Ch21/Portal"
{
    Properties
    {
        [NoScaleOffset] _NoiseTex ("Noise", 2D) = "gray" {}
        [HDR] _ColorInner ("Inner Color", Color) = (0.25, 0.9, 1.8, 1)
        [HDR] _ColorOuter ("Outer Color", Color) = (1.3, 0.25, 1.8, 1)
        _Arms ("Arms (integer)", Float) = 3
        _Twist ("Twist", Float) = 1.2
        _Spin ("Spin Speed", Float) = 0.15
        _Inward ("Inward Speed", Float) = 0.4
        _RadialTiling ("Radial Tiling", Float) = 1.5
        _Contrast ("Contrast", Range(0.5, 6)) = 2.5
        _Phase ("Phase (for stills)", Float) = 0
        [Toggle] _FixSeam ("Fix atan2 Seam", Float) = 1
        [Enum(Final,0,PolarUV,1,SwirlUV,2,Noise,3)] _Debug ("Debug View", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" "IgnoreProjector"="True" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }
            Blend One One          // 叠加发光：越叠越亮，不需要排序
            ZWrite Off
            Cull Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Assets/Cookbook/Ch21/UVAnim.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _ColorInner, _ColorOuter;
                float _Arms, _Twist, _Spin, _Inward, _RadialTiling;
                half _Contrast;
                float _Phase;
                half _FixSeam, _Debug;
            CBUFFER_END
            TEXTURE2D(_NoiseTex); SAMPLER(sampler_NoiseTex);

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings  { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = v.uv;
                return o;
            }

            //#region swirl
            float2 SwirlUV(float2 polar, float t, float spin)
            {
                // x：角度 × 臂数（必须是整数才能首尾相接）+ 半径 × 扭转（越往里转得越多）+ 时间旋转
                // y：半径 × 平铺 − 时间（图案不断向中心流）
                return float2(polar.x * _Arms + polar.y * _Twist + t * spin,
                              polar.y * _RadialTiling - t * _Inward);
            }

            // 带接缝修正的采样：atan2 在 ±π 处从 1 跳回 0，硬件按 2×2 像素块求导会得到巨大的 ddx，
            // 于是选中最低一级 mip，在接缝上画出一条线。修正：另算一份“接缝挪到对面”的角度，取较小的导数
            half SampleSwirl(float2 polar, float t, float spin)
            {
                float2 uv = SwirlUV(polar, t, spin);
                float2 dx = ddx(uv), dy = ddy(uv);
                if (_FixSeam > 0.5)
                {
                    float2 uvAlt = SwirlUV(float2(frac(polar.x + 0.5), polar.y), t, spin);
                    float2 dxAlt = ddx(uvAlt), dyAlt = ddy(uvAlt);
                    dx.x = abs(dx.x) < abs(dxAlt.x) ? dx.x : dxAlt.x;
                    dy.x = abs(dy.x) < abs(dyAlt.x) ? dy.x : dyAlt.x;
                }
                return SAMPLE_TEXTURE2D_GRAD(_NoiseTex, sampler_NoiseTex, uv, dx, dy).r;
            }
            //#endregion

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                float2 polar = ToPolar(i.uv, float2(0.5, 0.5));
                float t = _Time.y + _Phase;

                if (_Debug > 0.5 && _Debug < 1.5) return half4(polar.x, polar.y, 0, 1);
                if (_Debug > 1.5 && _Debug < 2.5) return half4(frac(SwirlUV(polar, t, _Spin)), 0, 1);
                // 只看一层漩涡噪声并二值化：接缝处取到最低级 mip（≈ 平均灰），在黑白图案里显出一道灰线
                if (_Debug > 3.5) { float2 u = SwirlUV(polar, t, _Spin); float d = max(length(ddx(u)), length(ddy(u))); return half4(saturate(log2(d * 512.0) / 10.0).xxx, 1); }
                if (_Debug > 2.5) return half4(smoothstep(0.5, 0.7, SampleSwirl(polar, t, _Spin)).xxx, 1);

                // 两层速度不同的漩涡相乘，图案更“活”
                half n1 = SampleSwirl(polar, t, _Spin);
                half n2 = SampleSwirl(polar * float2(1, 0.7), t * 1.3, -_Spin * 0.6);
                half swirl = pow(saturate(n1 * n2 * 2.0), _Contrast);

                half r = polar.y;
                half disc = smoothstep(1.0, 0.8, r);                     // 外缘淡出
                half rim  = exp(-pow((r - 0.86) * 9.0, 2.0));            // 外圈一道亮环
                half core = exp(-r * r * 18.0);                          // 中心光核
                half3 col = lerp(_ColorInner.rgb, _ColorOuter.rgb, saturate(r * 1.2));
                half3 result = col * (swirl * disc + rim * 0.8) + _ColorInner.rgb * core;
                return half4(result, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
