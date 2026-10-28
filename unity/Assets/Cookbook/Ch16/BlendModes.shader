// 混合模式实验台：源/目标因子和混合运算都做成材质属性，同一个 Shader 切出所有常见模式。
// _Output 决定片元输出的形式：直通（rgb, a）/ 预乘（贴图已预乘）/ 乘法就绪（lerp(1, rgb, a)）。
Shader "Cookbook/Ch16/BlendModes"
{
    Properties
    {
        [MainTexture] _BaseMap ("Base Map (alpha = shape)", 2D) = "white" {}
        [MainColor] _BaseColor ("Color", Color) = (1, 0.3, 0.2, 0.75)
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("Src Blend", Float) = 5   // SrcAlpha
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("Dst Blend", Float) = 10  // OneMinusSrcAlpha
        [Enum(UnityEngine.Rendering.BlendOp)] _BlendOp ("Blend Op", Float) = 0       // Add
        [KeywordEnum(Straight, Premultiply, MultiplyReady)] _Output ("Fragment Output", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" "IgnoreProjector"="True" }

        Pass
        {
            Name "Blend"
            Tags { "LightMode"="UniversalForward" }
            //#region state
            BlendOp [_BlendOp]
            Blend [_SrcBlend] [_DstBlend]
            ZWrite Off
            Cull Off
            //#endregion

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _OUTPUT_STRAIGHT _OUTPUT_PREMULTIPLY _OUTPUT_MULTIPLYREADY
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                float _SrcBlend, _DstBlend, _BlendOp;
            CBUFFER_END
            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                half3 rgb = tex.rgb * _BaseColor.rgb;
                half  a   = tex.a * _BaseColor.a;
            #if defined(_OUTPUT_PREMULTIPLY)
                // 预乘：贴图的 rgb 已经乘过 alpha（导出时完成），这里只再乘上材质的不透明度。
                // 于是 rgb 可以“大于” alpha——alpha = 0 而 rgb > 0 的像素就是纯叠加的辉光
                return half4(tex.rgb * _BaseColor.rgb * _BaseColor.a, a);
            #elif defined(_OUTPUT_MULTIPLYREADY)
                return half4(lerp(1.0h, rgb, a), a);  // 乘法类：透明处输出白色（乘 1 不变）
            #else
                return half4(rgb, a);                 // 直通
            #endif
            }
            //#endregion
            ENDHLSL
        }
    }
}
