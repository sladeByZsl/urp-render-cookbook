// 第 1 章 案例 1.4：透视校正插值 vs 仿射插值
// 同一份 UV，一份用默认插值（透视校正），一份加 noperspective 修饰（屏幕空间线性插值），
// 用 _Affine 选择用哪一份去采样棋盘格。
Shader "Cookbook/Ch01/PerspectiveInterp"
{
    Properties
    {
        [NoScaleOffset] _MainTex ("棋盘格", 2D) = "white" {}
        _Tiling ("重复次数", Float) = 4
        [Toggle] _Affine ("使用仿射（noperspective）插值", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "Interp"
            Tags { "LightMode"="UniversalForward" }
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);

            CBUFFER_START(UnityPerMaterial)
                float _Tiling;
                float _Affine;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
            };

            //#region varyings
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;   // 默认：透视校正插值
                noperspective float2 uvAffine : TEXCOORD1; // 在屏幕空间里线性插值（PS1 时代的效果）
            };
            //#endregion

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = input.uv * _Tiling;
                output.uvAffine = input.uv * _Tiling;
                return output;
            }

            half4 frag(Varyings input) : SV_Target
            {
                float2 uv = _Affine > 0.5 ? input.uvAffine : input.uv;
                return SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, uv);
            }
            ENDHLSL
        }
    }
}
