// 把 DFG 查找表画到面片上：横轴 NoV（0→1），纵轴感知粗糙度（下 0 → 上 1）
// R = A（F0 的系数），G = B（F90 的偏置）
Shader "Cookbook/Ch11/DFGLutView"
{
    Properties
    {
        [NoScaleOffset] _DFGLut ("DFG LUT", 2D) = "black" {}
        [Enum(LUT,0,Analytic,1,Diff x4,2)] _Mode ("Mode", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            CBUFFER_START(UnityPerMaterial)
                float _Mode;
            CBUFFER_END
            TEXTURE2D(_DFGLut);
            #include "Assets/Cookbook/Ch11/MyPBR_BRDF.hlsl"

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings   { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };
            Varyings vert(Attributes v) { Varyings o; o.positionCS = TransformObjectToHClip(v.positionOS.xyz); o.uv = v.uv; return o; }

            half4 frag(Varyings i) : SV_Target
            {
                float2 lut = SAMPLE_TEXTURE2D_LOD(_DFGLut, sampler_LinearClamp, i.uv, 0).rg;
                float2 ana = MyEnvDFGApprox(i.uv.x, i.uv.y);
                float2 c = _Mode < 0.5 ? lut : (_Mode < 1.5 ? ana : abs(lut - ana) * 4.0);
                // 目标是 sRGB 的 RT：输出线性值，硬件会做 sRGB 编码，图上看到的是“感知均匀”的亮度
                return half4(c, 0, 1);
            }
            ENDHLSL
        }
    }
}
