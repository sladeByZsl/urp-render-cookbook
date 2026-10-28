// 第 1 章 案例 1.5：屏幕 UV 应该在哪里做除法
// 用屏幕 UV 采样一个程序化棋盘格。三种写法：
//   0 正确：顶点里输出未除 w 的 positionNDC，片元里再除（URP 的 positionNDC / 旧的 ComputeScreenPos 就是为此设计）
//   1 错误：顶点里先除 w，再交给默认的透视校正插值
//   2 也正确：顶点里先除 w，但用 noperspective 在屏幕空间线性插值
//   3 最省事：片元里直接用 SV_POSITION 算 GetNormalizedScreenSpaceUV
Shader "Cookbook/Ch01/ScreenUV"
{
    Properties
    {
        [Enum(DivideInFragment,0,DivideInVertex,1,DivideInVertexNoPerspective,2,FromSVPosition,3)] _Mode ("写法", Float) = 0
        _Cells ("竖直方向格数", Float) = 10
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "ScreenUV"
            Tags { "LightMode"="UniversalForward" }
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _Mode;
                float _Cells;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            //#region code
            struct Varyings
            {
                float4 positionCS  : SV_POSITION;
                float4 positionNDC : TEXCOORD0;                  // 齐次屏幕坐标 (x, y, z, w)，xy 在 [0, w]
                float2 uvDivided   : TEXCOORD1;                  // 顶点里已经除过 w
                noperspective float2 uvDividedNP : TEXCOORD2;    // 同上，但按屏幕空间线性插值
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS  = pos.positionCS;
                output.positionNDC = pos.positionNDC;
                output.uvDivided   = pos.positionNDC.xy / pos.positionNDC.w;
                output.uvDividedNP = pos.positionNDC.xy / pos.positionNDC.w;
                return output;
            }

            float Checker(float2 uv)
            {
                float aspect = _ScreenParams.x / _ScreenParams.y;
                float2 cell = floor(uv * float2(_Cells * aspect, _Cells));
                return fmod(abs(cell.x + cell.y), 2.0);
            }

            half4 frag(Varyings input) : SV_Target
            {
                float2 uv;
                int mode = (int)_Mode;
                if (mode == 0)      uv = input.positionNDC.xy / input.positionNDC.w;   // 插值之后再除
                else if (mode == 1) uv = input.uvDivided;
                else if (mode == 2) uv = input.uvDividedNP;
                else                uv = GetNormalizedScreenSpaceUV(input.positionCS);

                float k = Checker(uv);
                half3 col = lerp(half3(0.92, 0.92, 0.94), half3(0.12, 0.42, 0.56), k);
                return half4(col, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
