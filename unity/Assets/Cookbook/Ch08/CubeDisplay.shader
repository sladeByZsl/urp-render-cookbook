// 调试用：按法线方向采样一张 cubemap 并原样显示（看环境本身，或看预先积分好的辐照度图）。
Shader "Cookbook/Ch08/CubeDisplay"
{
    Properties
    {
        [NoScaleOffset] _Cube("Cubemap", Cube) = "" {}
        _Exposure("Exposure", Float) = 1
        _Albedo("Albedo", Color) = (1, 1, 1, 1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _Albedo;
            half _Exposure;
        CBUFFER_END
        ENDHLSL
        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            TEXTURECUBE(_Cube); SAMPLER(sampler_Cube);
            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 normalWS : TEXCOORD0; };
            Varyings vert(Attributes input)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                o.normalWS = TransformObjectToWorldNormal(input.normalOS);
                return o;
            }
            half4 frag(Varyings i) : SV_Target
            {
                half3 c = SAMPLE_TEXTURECUBE_LOD(_Cube, sampler_Cube, normalize(i.normalWS), 0).rgb;
                return half4(c * _Albedo.rgb * _Exposure, 1);
            }
            ENDHLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex Ch08DepthVert
            #pragma fragment Ch08NullFrag
            #include "Assets/Cookbook/Ch08/Ch08Passes.hlsl"
            ENDHLSL
        }
    }
}
