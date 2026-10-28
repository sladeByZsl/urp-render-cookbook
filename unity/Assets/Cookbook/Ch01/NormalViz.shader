// 第 1 章 案例 1.2：法线可视化，以及“非均匀缩放下法线该怎么变换”
// _Mode：0 物体空间法线 / 1 世界空间法线 / 2 观察空间法线
//        3 用正确的世界法线做 Lambert / 4 用错误的方式（直接乘模型矩阵）变换法线做 Lambert
//        5 两种法线算出的光照之差（放大 4 倍）
Shader "Cookbook/Ch01/NormalViz"
{
    Properties
    {
        [Enum(ObjectNormal,0,WorldNormal,1,ViewNormal,2,LitCorrect,3,LitWrong,4,Difference,5)] _Mode ("模式", Float) = 1
        _BaseColor ("Lambert 底色", Color) = (0.85, 0.85, 0.85, 1)
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "NormalViz"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _Mode;
                half4 _BaseColor;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS   : SV_POSITION;
                float3 normalOS     : TEXCOORD0;
                float3 normalWS     : TEXCOORD1;
                float3 normalWSWrong: TEXCOORD2;
                float3 normalVS     : TEXCOORD3;
            };

            //#region vert
            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                output.normalOS   = input.normalOS;

                // 正确：乘“模型矩阵的逆转置”。URP 的实现是 mul(normalOS, (float3x3)WorldToObject)，
                // 行向量左乘逆矩阵，等价于列向量左乘逆矩阵的转置（SpaceTransforms.hlsl）
                output.normalWS = TransformObjectToWorldNormal(input.normalOS);

                // 错误：把法线当成普通方向，直接乘模型矩阵。均匀缩放时没问题，非均匀缩放时法线不再垂直于表面
                output.normalWSWrong = TransformObjectToWorldDir(input.normalOS);

                // 观察空间法线：方向只受旋转影响，用 3x3 的观察矩阵即可（相机矩阵不含缩放）
                output.normalVS = TransformWorldToViewDir(output.normalWS);
                return output;
            }
            //#endregion

            half3 Lambert(float3 n)
            {
                Light light = GetMainLight();
                half ndl = saturate(dot(n, light.direction));
                return _BaseColor.rgb * (light.color * ndl + 0.08);
            }

            //#region frag
            half4 frag(Varyings input) : SV_Target
            {
                // 插值后的法线长度会小于 1，必须重新归一化
                float3 nOS = normalize(input.normalOS);
                float3 nWS = normalize(input.normalWS);
                float3 nWrong = normalize(input.normalWSWrong);
                float3 nVS = normalize(input.normalVS);

                int mode = (int)_Mode;
                half3 col;
                if (mode == 0)      col = nOS * 0.5 + 0.5;   // [-1,1] 映射到 [0,1] 才能当颜色看
                else if (mode == 1) col = nWS * 0.5 + 0.5;
                else if (mode == 2) col = nVS * 0.5 + 0.5;
                else if (mode == 3) col = Lambert(nWS);
                else if (mode == 4) col = Lambert(nWrong);
                else                col = abs(Lambert(nWS) - Lambert(nWrong)) * 4.0;
                return half4(col, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
