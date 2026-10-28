// 单独查看贴图的某个通道（不受光照影响）。
// 目标：屏幕上的像素值 = 贴图文件里存的数值。
//   线性贴图（Mask、法线）：采样值就是存的值，输出前做 SRGBToLinear，抵消相机目标的 sRGB 编码；
//   sRGB 贴图（Albedo）：采样时硬件已解码成线性，直接输出，目标编码回去正好还原。
Shader "Cookbook/Ch13/ChannelView"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        [Enum(R,0,G,1,B,2,A,3,RGB,4)] _Channel ("Channel", Float) = 4
        [Toggle] _LinearData ("Texture Is Linear Data", Float) = 1
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
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _MainTex_ST;
                float  _Channel;
                float  _LinearData;
            CBUFFER_END
            TEXTURE2D(_MainTex); SAMPLER(sampler_MainTex);

            struct Attributes { float4 positionOS : POSITION; float2 uv : TEXCOORD0; };
            struct Varyings   { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };
            Varyings vert(Attributes v) { Varyings o; o.positionCS = TransformObjectToHClip(v.positionOS.xyz); o.uv = TRANSFORM_TEX(v.uv, _MainTex); return o; }

            half4 frag(Varyings i) : SV_Target
            {
                // 注意：采样到的值已经过“导入设置决定的”解码——sRGB 贴图会被转成线性
                half4 t = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv);
                int ch = (int)_Channel;
                half3 c = ch == 4 ? t.rgb : t[min(ch, 3)].xxx;
                return half4(_LinearData > 0.5 ? SRGBToLinear(c) : c, 1);
            }
            ENDHLSL
        }
    }
}
