// 第 1 章 案例 1.1：坐标空间可视化
// 同一个顶点，在不同空间里坐标不同。这个调试 Shader 把各空间的坐标“涂”在物体表面，
// 用 _Mode 切换：物体空间 / 世界空间 / 观察空间 / NDC / 裁剪空间 w / 屏幕像素坐标。
Shader "Cookbook/Ch01/SpaceViz"
{
    Properties
    {
        [Enum(Object,0,World,1,View,2,NDC,3,ClipW,4,Pixel,5)] _Mode ("显示哪个空间", Float) = 1
        _GridSize ("网格间距（该空间的单位）", Float) = 1
        _DepthScale ("深度着色范围（米）", Float) = 12
        _PixelCell ("像素棋盘格大小（像素）", Float) = 40
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "SpaceViz"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float _Mode;
                float _GridSize;
                float _DepthScale;
                float _PixelCell;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            //#region varyings
            struct Varyings
            {
                float4 positionCS  : SV_POSITION; // 交给光栅化器：裁剪空间坐标（到了片元里会变成像素坐标）
                float3 positionOS  : TEXCOORD0;   // 物体空间
                float3 positionWS  : TEXCOORD1;   // 世界空间
                float3 positionVS  : TEXCOORD2;   // 观察空间（右手系，相机看向 -Z）
                float4 positionHCS : TEXCOORD3;   // 裁剪空间的一份拷贝：SV_POSITION 在片元阶段已被改写，想要原值得自己传
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                // URP 一次性算好各个空间的位置（ShaderVariablesFunctions.hlsl）
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS  = pos.positionCS;
                output.positionOS  = input.positionOS.xyz;
                output.positionWS  = pos.positionWS;
                output.positionVS  = pos.positionVS;
                output.positionHCS = pos.positionCS;
                return output;
            }
            //#endregion

            // 抗锯齿网格线：p 落在 size 的整数倍附近时返回 1。
            // fwidth 给出 p 在相邻像素间的变化量，用它做线宽，线在远处也保持约 1 像素宽。
            // 在某个表面上恒定不变的分量（如地面的 y）fwidth 为 0，要排除，否则整面都会被当成“线上”。
            float GridLine(float3 p, float size)
            {
                float3 q = p / size;
                float3 fw = fwidth(q);
                float3 d = abs(frac(q - 0.5) - 0.5) / max(fw, 1e-5);
                d += step(fw, 1e-6) * 1e6;
                return 1.0 - saturate(min(min(d.x, d.y), d.z) - 0.5);
            }

            float GridLine2(float2 p, float size)
            {
                float2 q = p / size;
                float2 d = abs(frac(q - 0.5) - 0.5) / max(fwidth(q), 1e-5);
                return 1.0 - saturate(min(d.x, d.y) - 0.5);
            }

            //#region frag
            half4 frag(Varyings input) : SV_Target
            {
                float3 col = 0;
                int mode = (int)_Mode;

                if (mode == 0)          // 物体空间：坐标跟着物体走，旋转缩放物体，图案跟着转
                {
                    col = saturate(input.positionOS + 0.5);
                    col = lerp(col, 0.05, GridLine(input.positionOS, 0.25 * _GridSize));
                }
                else if (mode == 1)     // 世界空间：所有物体共用一套坐标，网格线在物体之间连续
                {
                    float3 cell = frac(input.positionWS / _GridSize);
                    col = 0.25 + 0.6 * cell;
                    col = lerp(col, 0.05, GridLine(input.positionWS, _GridSize));
                    // 世界原点处的 X 轴（红）、Z 轴（蓝）
                    float ax = 1.0 - saturate(abs(input.positionWS.z) / (2.0 * fwidth(input.positionWS.z)));
                    float az = 1.0 - saturate(abs(input.positionWS.x) / (2.0 * fwidth(input.positionWS.x)));
                    col = lerp(col, float3(1, 0.1, 0.1), ax);
                    col = lerp(col, float3(0.1, 0.3, 1), az);
                }
                else if (mode == 2)     // 观察空间：x 向右、y 向上，深度 = -z
                {
                    float depth = -input.positionVS.z;
                    col.rg = saturate(input.positionVS.xy * 0.25 + 0.5);
                    col.b  = saturate(depth / _DepthScale);
                    // 等深线：每 1 米一条，它们都与相机的成像平面平行
                    float iso = abs(frac(depth - 0.5) - 0.5) / max(fwidth(depth), 1e-5);
                    col = lerp(col, 1.0, 1.0 - saturate(iso - 0.5));
                }
                else if (mode == 3)     // NDC：透视除法之后，可见范围 x、y 都在 [-1, 1]
                {
                    float2 ndc = input.positionHCS.xy / input.positionHCS.w;
                    ndc.y *= _ProjectionParams.x;      // 渲染到 RT 时投影矩阵被上下翻转过，这里翻回来，让 +y 永远朝上
                    col = float3(saturate(ndc.x), saturate(ndc.y), saturate(-ndc.x) * 0.7 + saturate(-ndc.y) * 0.3);
                    col = lerp(col, 0.0, GridLine2(ndc, 0.25));
                    col = lerp(col, 1.0, GridLine2(ndc, 1.0));   // 中心十字（x=0、y=0）
                }
                else if (mode == 4)     // 裁剪空间的 w：透视投影下它就是观察空间深度
                {
                    float w = input.positionHCS.w;
                    col = saturate(w / _DepthScale).xxx;
                    float iso = abs(frac(w - 0.5) - 0.5) / max(fwidth(w), 1e-5);
                    col = lerp(col, float3(1, 0.45, 0.2), 1.0 - saturate(iso - 0.5));
                }
                else                    // 片元阶段的 SV_POSITION.xy：像素中心坐标（如 100.5, 37.5）
                {
                    float2 cell = floor(input.positionCS.xy / _PixelCell);
                    float k = fmod(cell.x + cell.y, 2.0);
                    col = lerp(float3(0.9, 0.9, 0.92), float3(0.25, 0.45, 0.6), k);
                }
                return half4(col, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
