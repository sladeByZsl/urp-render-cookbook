// 第 9 章：在 Gamma 空间做光照 vs 在线性空间做光照。
// 两盏灯：主光（场景里的方向光）+ 一盏由材质参数给出的“虚拟”方向光，方便控制颜色和方向。
// Linear：贴图解码后的线性值 × 线性灯光，最后由管线写入 sRGB 目标时统一编码 —— 正确做法。
// Gamma ：故意把颜色先编码回 sRGB 再做乘加（相当于老式 Gamma 工作流），
//         最后再解码一次，抵消管线的编码，让屏幕上看到的就是“在 Gamma 空间算出来的数”。
Shader "Cookbook/Ch09/GammaVsLinear"
{
    Properties
    {
        [Toggle] _GammaSpace("Lighting In Gamma Space", Float) = 0
        _BaseColor("Albedo", Color) = (0.8, 0.8, 0.8, 1)
        _Light2Dir("Light 2 Direction (to light)", Vector) = (1, 0.3, -0.4, 0)
        _Light2Color("Light 2 Color", Color) = (0.2, 0.45, 1, 1)
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
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _GammaSpace;
                float4 _BaseColor, _Light2Dir, _Light2Color;
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

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                Light l1 = GetMainLight();
                float3 L2 = normalize(_Light2Dir.xyz);

                // 材质颜色、灯光颜色在 Shader 里拿到的都已经是线性值
                float3 albedo = _BaseColor.rgb;
                float3 c1 = l1.color, c2 = _Light2Color.rgb;

                if (_GammaSpace > 0.5)
                {
                    // 错误示范：把它们变回 sRGB 编码值再去做乘法和加法
                    albedo = LinearToSRGB(albedo);
                    c1 = LinearToSRGB(c1);
                    c2 = LinearToSRGB(c2);
                }

                float3 lit = albedo * (c1 * saturate(dot(N, l1.direction)) + c2 * saturate(dot(N, L2)));

                if (_GammaSpace > 0.5)
                    lit = SRGBToLinear(saturate(lit));  // 抵消管线最后的 sRGB 编码

                return half4(lit, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
