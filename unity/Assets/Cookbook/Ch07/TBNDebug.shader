// 把切线空间的三根轴（T/B/N）和法线贴图扰动后的法线显示成颜色，用来检查网格切线是否正确。
Shader "Cookbook/Ch07/TBNDebug"
{
    Properties
    {
        [Enum(Tangent,0,Bitangent,1,Normal,2,MappedNormal,3)] _Mode("Show", Float) = 0
        [NoScaleOffset][Normal] _BumpMap("Normal Map", 2D) = "bump" {}
        _BumpScale("Normal Scale", Range(0, 2)) = 1
        _Tiling("Tiling", Vector) = (1, 1, 0, 0)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float4 _Tiling;
            half _Mode;
            half _BumpScale;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;     // xyz = 切线，w = 副切线的朝向（±1）
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 normalWS   : TEXCOORD1;
                float4 tangentWS  : TEXCOORD2;   // w 保存 sign，副切线在片元里重建
            };

            //#region vert
            Varyings vert(Attributes input)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                o.uv = input.uv * _Tiling.xy + _Tiling.zw;
                // GetVertexNormalInputs 会：法线用逆转置矩阵变换、切线按方向变换、
                // 副切线 = cross(N, T) * tangentOS.w * GetOddNegativeScale()
                VertexNormalInputs n = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                o.normalWS = n.normalWS;
                o.tangentWS = float4(n.tangentWS, input.tangentOS.w * GetOddNegativeScale());
                return o;
            }
            //#endregion

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                // 插值之后长度不再为 1，先归一化（MikkTSpace 的约定是在像素里才归一化）
                float3 N = normalize(i.normalWS);
                float3 T = normalize(i.tangentWS.xyz);
                float3 B = i.tangentWS.w * cross(N, T);
                float3 c;
                if (_Mode < 0.5)      c = T;
                else if (_Mode < 1.5) c = B;
                else if (_Mode < 2.5) c = N;
                else
                {
                    half3 nTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv), _BumpScale);
                    // 行向量 T/B/N 组成的矩阵；mul(向量, 矩阵) = nTS.x*T + nTS.y*B + nTS.z*N
                    c = normalize(TransformTangentToWorld(nTS, half3x3(T, B, N)));
                }
                return half4(c * 0.5 + 0.5, 1);   // [-1,1] 映射到 [0,1] 才能当颜色看
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex Ch07DepthVert
            #pragma fragment Ch07NullFrag
            #include "Assets/Cookbook/Ch07/Ch07Common.hlsl"
            ENDHLSL
        }
    }
}
