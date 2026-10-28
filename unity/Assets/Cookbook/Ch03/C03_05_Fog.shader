// 第 5 步：接入 Lighting 窗口里的雾（Linear / Exponential / Exponential Squared）。
Shader "Cookbook/Ch03/Fog"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map", 2D) = "white" {}
        [MainColor]   _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _Cutoff ("Alpha Cutoff", Range(0, 1)) = 0.5
        [Enum(UnityEngine.Rendering.CullMode)] _Cull ("Cull", Float) = 2
    }

    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }
            Cull [_Cull]

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            //#region pragma
            // 生成 无雾 / FOG_LINEAR / FOG_EXP / FOG_EXP2 四个变体，引擎按 Lighting 设置选用
            #pragma multi_compile_fog
            //#endregion
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                half4  color      : COLOR;
            };

            //#region varyings
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                half4  color      : COLOR;
                float  fogFactor  : TEXCOORD1;  // 每个顶点算一次雾因子，交给插值器
            };
            //#endregion

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            float4 _BaseMap_ST;
            half4  _BaseColor;
            half   _Cutoff;

            //#region vertfrag
            Varyings vert (Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap);
                output.color = input.color;
                // 用裁剪空间 z 换算出“离相机多远”，再按雾模式算出因子
                output.fogFactor = ComputeFogFactor(output.positionCS.z);
                return output;
            }

            half4 frag (Varyings input) : SV_Target
            {
                half4 col = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor * input.color;
                clip(col.a - _Cutoff);
                // 按因子把颜色往 unity_FogColor 方向混；没开雾时这一行什么都不做
                col.rgb = MixFog(col.rgb, input.fogFactor);
                return half4(col.rgb, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
