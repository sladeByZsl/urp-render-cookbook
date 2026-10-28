// 案例 29.1 的反例：能编译、能显示，但 SRP Batcher 不兼容。
// 原因：_BaseColor 声明在 CBUFFER 之外，变成了“全局 uniform”，每个材质都要单独 SetPass 上传。
// 在 Inspector 里选中这个 Shader，会看到 SRP Batcher: not compatible 及原因。
Shader "Cookbook/Ch29/BatcherBreaker"
{
    Properties
    {
        [MainColor] _BaseColor ("Color", Color) = (1, 1, 1, 1)
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

            //#region bad
            half4 _BaseColor;     // ✗ 不在 UnityPerMaterial 里
            //#endregion

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings { float4 positionCS : SV_POSITION; };
            Varyings vert(Attributes input) { Varyings o; o.positionCS = TransformObjectToHClip(input.positionOS.xyz); return o; }
            half4 frag(Varyings i) : SV_Target { return _BaseColor; }
            ENDHLSL
        }
    }
}
