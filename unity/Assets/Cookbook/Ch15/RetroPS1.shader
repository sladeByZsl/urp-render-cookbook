// 复古像素风（PS1 风格）：顶点吸附到低分辨率网格、仿射纹理映射（不做透视校正）、
// 逐顶点光照、点采样，以及“抖动 + 色深量化”。每一项都能单独开关，方便对比。
Shader "Cookbook/Ch15/RetroPS1"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        [MainColor] _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _VirtualRes ("Virtual Resolution (xy)", Vector) = (320, 240, 0, 0)
        [Toggle] _VertexSnap ("Vertex Snap", Float) = 1
        [Toggle] _Affine ("Affine Texture Mapping", Float) = 1
        [Toggle] _PointSample ("Point Sampling", Float) = 1
        [Toggle] _Quantize ("Dither + Quantize", Float) = 1
        _ColorBits ("Color Bits per Channel", Range(2, 8)) = 5
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            float4 _VirtualRes;
            float  _VertexSnap, _Affine, _PointSample, _Quantize, _ColorBits;
        CBUFFER_END

        //#region snap
        // 把顶点吸附到 _VirtualRes 分辨率的像素格上。
        // 先除 w 得到 NDC，取整后再乘回 w，保持深度与透视不变，只让 xy 跳格。
        float4 SnapToPixelGrid(float4 positionCS, float2 res)
        {
            float2 halfRes = res * 0.5;
            float2 ndc = positionCS.xy / positionCS.w;
            ndc = floor(ndc * halfRes + 0.5) / halfRes;
            positionCS.xy = ndc * positionCS.w;
            return positionCS;
        }
        //#endregion
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;   // 正常的（透视校正的）UV
                float3 uvAffine   : TEXCOORD1;   // (uv * w, w)，用来抵消透视校正
                half3  lighting   : TEXCOORD2;   // 逐顶点光照（Gouraud）
            };


            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float4 positionCS = TransformWorldToHClip(positionWS);
                if (_VertexSnap > 0.5) positionCS = SnapToPixelGrid(positionCS, _VirtualRes.xy);
                o.positionCS = positionCS;

                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                //#region affine-vert
                // 透视校正插值对属性 A 实际做的是：插值 A/w 和 1/w 再相除。
                // 传入 A·w 和 w，两者都被“校正”后相除，w 抵消，剩下的就是屏幕空间线性插值的 A。
                o.uvAffine = float3(o.uv * positionCS.w, positionCS.w);
                //#endregion

                // 逐顶点 Lambert + 环境光：当年的硬件只在顶点上算光
                float3 N = TransformObjectToWorldNormal(v.normalOS);
                Light L = GetMainLight();
                o.lighting = saturate(dot(N, L.direction)) * L.color + SampleSH(N);
                return o;
            }

            //#region quantize
            static const float kBayer4[16] = {
                 0,  8,  2, 10,
                12,  4, 14,  6,
                 3, 11,  1,  9,
                15,  7, 13,  5 };

            // 先加一个有序抖动偏移，再截断到 bits 位：渐变变成规则的网点而不是色带
            half3 DitherQuantize(half3 c, float2 pixel, float bits)
            {
                uint2 p = (uint2)pixel % 4;
                float threshold = (kBayer4[p.y * 4 + p.x] + 0.5) / 16.0 - 0.5;   // -0.5..0.5
                float levels = exp2(bits) - 1.0;
                return floor(saturate(c) * levels + 0.5 + threshold) / levels;
            }
            //#endregion

            half4 frag(Varyings i) : SV_Target
            {
                float2 uv = lerp(i.uv, i.uvAffine.xy / i.uvAffine.z, _Affine);
                half4 texLinear = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv);
                half4 texPoint  = SAMPLE_TEXTURE2D(_BaseMap, sampler_PointRepeat, uv);
                half4 tex = lerp(texLinear, texPoint, _PointSample);

                half3 col = tex.rgb * _BaseColor.rgb * i.lighting;
                if (_Quantize > 0.5)
                {
                    // 抖动图案也按“虚拟分辨率”放大，模拟低分辨率帧缓冲上的抖动
                    float2 virtualPixel = floor(i.positionCS.xy * _VirtualRes.xy / _ScreenParams.xy);
                    // 在 sRGB（显示）空间量化，色阶才均匀
                    col = SRGBToLinear(DitherQuantize(LinearToSRGB(col), virtualPixel, _ColorBits));
                }
                return half4(col, 1);
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
            // 深度也要按同样方式吸附，否则深度图与颜色错位
            float4 vert(float4 positionOS : POSITION) : SV_POSITION
            {
                float4 positionCS = TransformObjectToHClip(positionOS.xyz);
                if (_VertexSnap > 0.5) positionCS = SnapToPixelGrid(positionCS, _VirtualRes.xy);
                return positionCS;
            }
            half4 frag() : SV_Target { return 0; }
            ENDHLSL
        }
    }
}
