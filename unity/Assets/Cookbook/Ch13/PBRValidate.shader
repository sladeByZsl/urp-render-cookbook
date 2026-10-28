// PBR 校验视图：读取 URP Lit 材质的属性（同名），把“超出合理范围”的像素用斜条纹高亮。
//   红：电介质 Albedo 过暗      蓝：电介质 Albedo 过亮
//   黄：金属度处在 0~1 之间的灰区（通常只该出现在过渡边缘）
//   品红：金属的 Albedo（即 F0）过暗
// 用法一：在材质上临时把 Shader 换成它（同名属性与关键字会保留），看完再换回 Lit。
// 用法二：RenderObjects 的 Override Mode = Shader，一键对整个场景生效（见 PBRValidateFeature 的配置代码）。
Shader "Cookbook/Ch13/PBRValidate"
{
    Properties
    {
        [MainTexture] _BaseMap ("Albedo", 2D) = "white" {}
        [MainColor] _BaseColor ("Color", Color) = (1, 1, 1, 1)
        _Metallic ("Metallic", Range(0, 1)) = 0
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
        _MetallicGlossMap ("Metallic (R) Smoothness (A)", 2D) = "white" {}
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Name "Validate"
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _METALLICSPECGLOSSMAP
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4  _BaseColor;
                half   _Metallic;
                half   _Smoothness;
            CBUFFER_END
            TEXTURE2D(_BaseMap);          SAMPLER(sampler_BaseMap);
            TEXTURE2D(_MetallicGlossMap); SAMPLER(sampler_MetallicGlossMap);

            //#region thresholds
            // 阈值用 sRGB 0~1 表示（美术在取色器里看到的数值 / 255）。
            // 全局变量，由 C# 用 Shader.SetGlobalVector 设置；w <= 0 时使用下面的默认值。
            float4 _PBRValidateRange;   // x 电介质最暗  y 电介质最亮  z 金属最暗
            #define DEFAULT_RANGE float3(30.0 / 255.0, 240.0 / 255.0, 180.0 / 255.0)
            #define METAL_GRAY_LOW  0.1
            #define METAL_GRAY_HIGH 0.9
            //#endregion

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv : TEXCOORD0; };
            struct Varyings   { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; float3 normalWS : TEXCOORD1; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                return o;
            }

            //#region validate
            half4 frag(Varyings i) : SV_Target
            {
                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb * _BaseColor.rgb;   // 线性
            #if defined(_METALLICSPECGLOSSMAP)
                half metallic = SAMPLE_TEXTURE2D(_MetallicGlossMap, sampler_MetallicGlossMap, i.uv).r;
            #else
                half metallic = _Metallic;
            #endif

                float3 range = _PBRValidateRange.w > 0 ? _PBRValidateRange.xyz : DEFAULT_RANGE;
                // 回到 sRGB 再比较，和美术在 Photoshop/Substance 里看到的数值一致
                half lumS = LinearToSRGB(Luminance(albedo).xxx).x;
                half maxS = LinearToSRGB(max(albedo.r, max(albedo.g, albedo.b)).xxx).x;

                half3 flag = 0; half bad = 0;
                if (metallic > METAL_GRAY_LOW && metallic < METAL_GRAY_HIGH) { flag = half3(1, 0.85, 0); bad = 1; }   // 黄
                else if (metallic >= METAL_GRAY_HIGH)
                {
                    if (maxS < range.z) { flag = half3(1, 0, 1); bad = 1; }                                          // 品红
                }
                else
                {
                    if (lumS < range.x)      { flag = half3(1, 0.1, 0.1); bad = 1; }                                // 红
                    else if (lumS > range.y) { flag = half3(0.15, 0.35, 1); bad = 1; }                              // 蓝
                }

                // 底图：Albedo 亮度 × 简单的半兰伯特，保留形体，又不让光照干扰“材质值”的判断
                half ndl = dot(normalize(i.normalWS), GetMainLight().direction) * 0.5 + 0.5;
                half3 baseCol = Luminance(albedo).xxx * (0.35 + 0.65 * ndl);

                // 屏幕空间斜条纹：一眼能和“本来就是这个颜色的材质”区分开
                half stripe = frac((i.positionCS.x + i.positionCS.y) / 14.0) < 0.5;
                half3 c = lerp(baseCol, flag, bad * lerp(0.35, 0.9, stripe));
                return half4(c, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
