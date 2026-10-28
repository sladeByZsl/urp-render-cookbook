// 第一步：只有主光、没有阴影、没有环境光的最小 PBR。
// 目的：先单独验证 BRDF（D、V、F、Lambert 与 π 的约定）是否正确，再往上加东西。
Shader "Cookbook/Ch11/Step1_DirectPBR"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1, 1, 1, 1)
        _Metallic ("Metallic", Range(0, 1)) = 0
        _Smoothness ("Smoothness", Range(0, 1)) = 0.5
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

            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                half  _Metallic;
                half  _Smoothness;
            CBUFFER_END
            // MyPBR_BRDF.hlsl 里的 LUT 分支要用到这张贴图的声明（本步不启用）
            TEXTURE2D(_DFGLut);
            #include "Assets/Cookbook/Ch11/MyPBR_BRDF.hlsl"

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings   { float4 positionCS : SV_POSITION; float3 positionWS : TEXCOORD0; float3 normalWS : TEXCOORD1; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.normalWS   = TransformObjectToWorldNormal(v.normalOS);
                return o;
            }

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                float3 N = normalize(i.normalWS);
                float3 V = GetWorldSpaceNormalizeViewDir(i.positionWS);
                Light light = GetMainLight();

                MyMaterial m = MyInitMaterial(_BaseColor.rgb, _Metallic, 1.0 - _Smoothness);
                float3 fd, fs; float NoL;
                MyDirectBRDF(m, N, V, light.direction, fd, fs, NoL);

                // 渲染方程只剩一项：Lo = f(l,v) · E⊥ · NoL，E⊥ = π · light.color
                float3 Lo = (fd + fs) * PI * light.color * NoL;
                return half4(Lo, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
