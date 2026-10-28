// 第 2 章 案例 2.5：LightMode 标签决定“谁来画这个 Pass”
// 一个 Shader 三个 Pass：
//   Pass 1  LightMode = UniversalForward ：URP 的不透明/透明绘制 Pass 会画它（正常着色）
//   Pass 2  不写 LightMode               ：被当作 SRPDefaultUnlit，URP 也会在同一次绘制里画它（这里做外描边）
//   Pass 3  LightMode = CookbookXRay      ：URP 自己不认识，默认谁也不画；用 RenderObjects 这类 Feature 点名才会画（这里做 X 光透视）
Shader "Cookbook/Ch02/LightModeDemo"
{
    Properties
    {
        _BaseColor ("底色", Color) = (0.95, 0.6, 0.25, 1)
        _OutlineColor ("描边颜色", Color) = (0.08, 0.1, 0.12, 1)
        _OutlineWidth ("描边宽度（米）", Float) = 0.03
        _XRayColor ("透视颜色", Color) = (0.2, 0.75, 1.0, 0.6)
    }

    HLSLINCLUDE
    #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

    // 三个 Pass 共用同一份 UnityPerMaterial，SRP Batcher 才能兼容
    CBUFFER_START(UnityPerMaterial)
        half4 _BaseColor;
        half4 _OutlineColor;
        float _OutlineWidth;
        half4 _XRayColor;
    CBUFFER_END

    struct Attributes
    {
        float4 positionOS : POSITION;
        float3 normalOS   : NORMAL;
    };

    struct Varyings
    {
        float4 positionCS : SV_POSITION;
        float3 normalWS   : TEXCOORD0;
    };

    Varyings VertDefault(Attributes input)
    {
        Varyings output;
        output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
        output.normalWS = TransformObjectToWorldNormal(input.normalOS);
        return output;
    }
    ENDHLSL

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        //#region passes
        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex VertDefault
            #pragma fragment Frag
            half4 Frag(Varyings input) : SV_Target
            {
                float3 n = normalize(input.normalWS);
                Light light = GetMainLight();
                half3 diffuse = light.color * saturate(dot(n, light.direction));
                half3 ambient = SampleSH(n);
                return half4(_BaseColor.rgb * (diffuse + ambient), 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "Outline"
            // 没有 LightMode 标签 → URP 视为 "SRPDefaultUnlit"
            Cull Front

            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            Varyings Vert(Attributes input)
            {
                Varyings output;
                // 沿法线把顶点往外推，只画背面，就得到一圈“外壳”描边（第 14 章细讲）
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(input.normalOS);
                output.positionCS = TransformWorldToHClip(positionWS + normalWS * _OutlineWidth);
                output.normalWS = normalWS;
                return output;
            }
            half4 Frag(Varyings input) : SV_Target { return _OutlineColor; }
            ENDHLSL
        }

        Pass
        {
            Name "XRay"
            Tags { "LightMode"="CookbookXRay" }
            // 只在“被挡住”的地方画：深度比已有深度更远才通过
            ZTest Greater
            ZWrite Off
            Blend SrcAlpha OneMinusSrcAlpha

            HLSLPROGRAM
            #pragma vertex VertDefault
            #pragma fragment Frag
            half4 Frag(Varyings input) : SV_Target { return _XRayColor; }
            ENDHLSL
        }
        //#endregion
    }
}
