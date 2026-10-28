// 对照用：最普通的逐物体半透明（简单漫反射 + Alpha 混合，不写深度）。
// 案例 25.2 用它当“玻璃”，案例 25.7 用它展示“逐物体半透明会露出内部结构”的问题。
Shader "Cookbook/Ch25/SimpleTransparent"
{
    Properties
    {
        _BaseColor ("Color", Color) = (0.3, 0.8, 1, 0.45)
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }
        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 normalWS : TEXCOORD0; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                Light light = GetMainLight();
                half ndl = saturate(dot(normalize(i.normalWS), light.direction)) * 0.7 + 0.3;
                return half4(_BaseColor.rgb * light.color * ndl, _BaseColor.a);
            }
            ENDHLSL
        }
    }
}
