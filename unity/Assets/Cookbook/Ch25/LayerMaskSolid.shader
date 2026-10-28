// 案例 25.5：DrawRenderers 的 Override Material——把物体画成纯白剪影，写进遮罩 RT。
Shader "Cookbook/Ch25/LayerMaskSolid"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Name "Mask"
            ZWrite Off      // 绝不改动相机深度；深度比较方式由 C# 的 RenderStateBlock 决定
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings { float4 positionCS : SV_POSITION; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                return o;
            }

            half4 frag(Varyings i) : SV_Target { return 1.0; }
            ENDHLSL
        }
    }
}
