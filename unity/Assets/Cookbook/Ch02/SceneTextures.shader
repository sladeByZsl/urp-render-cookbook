// 第 2 章 案例 2.2：Depth Texture 与 Opaque Texture 是怎么被“用掉”的
// 一个极简的水面：
//   - 用 _CameraDepthTexture 求“水面到水底的厚度”，做深浅颜色和岸边白沫；
//   - 用 _CameraOpaqueTexture 取水面背后的画面，加一点扰动做折射。
// 两张纹理分别由 URP Asset 的 Depth Texture / Opaque Texture 开关控制。完整的水在第 19 章。
Shader "Cookbook/Ch02/SceneTextures"
{
    Properties
    {
        _ShallowColor ("浅水颜色（乘在折射画面上）", Color) = (0.75, 0.95, 0.95, 1)
        _DeepColor ("深水颜色", Color) = (0.05, 0.22, 0.32, 1)
        _DepthFade ("多深算“深水”（米）", Float) = 1.2
        _FoamWidth ("岸边白沫宽度（米）", Float) = 0.12
        _Distortion ("折射扰动强度", Float) = 0.02
        _WaveScale ("波纹频率", Float) = 6
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }

        Pass
        {
            Name "Water"
            Tags { "LightMode"="UniversalForward" }
            // 背后的画面我们自己从 Opaque Texture 里取，所以直接覆盖写入，不需要混合
            Blend One Zero
            ZWrite Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _ShallowColor;
                half4 _DeepColor;
                float _DepthFade;
                float _FoamWidth;
                float _Distortion;
                float _WaveScale;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS  : SV_POSITION;
                float3 positionWS  : TEXCOORD0;
                float4 positionNDC : TEXCOORD1;
            };

            Varyings vert(Attributes input)
            {
                Varyings output;
                VertexPositionInputs pos = GetVertexPositionInputs(input.positionOS.xyz);
                output.positionCS  = pos.positionCS;
                output.positionWS  = pos.positionWS;
                output.positionNDC = pos.positionNDC;
                return output;
            }

            //#region frag
            half4 frag(Varyings input) : SV_Target
            {
                float2 screenUV = input.positionNDC.xy / input.positionNDC.w;

                // 1) 深度纹理：水底（不透明物体）离相机多远
                float sceneEye   = LinearEyeDepth(SampleSceneDepth(screenUV), _ZBufferParams);
                float surfaceEye = input.positionNDC.w;          // 透视投影下 clip.w 就是水面自己的观察深度
                float thickness  = max(sceneEye - surfaceEye, 0); // 视线穿过的水的厚度（米）

                // 2) 不透明纹理：水面背后的画面，加一点随世界坐标变化的扰动
                float2 p = input.positionWS.xz * _WaveScale;
                float2 wave = float2(sin(p.x + p.y * 0.7), cos(p.y * 1.3 - p.x * 0.4));
                float2 refrUV = screenUV + wave * _Distortion * saturate(thickness);
                half3 behind = SampleSceneColor(refrUV);

                // 越深越接近深水色；离岸（厚度接近 0）的地方叠一圈白沫
                half t = saturate(thickness / _DepthFade);
                half3 col = lerp(behind * _ShallowColor.rgb, _DeepColor.rgb, t);
                half foam = 1.0 - saturate(thickness / _FoamWidth);
                col = lerp(col, half3(0.95, 0.98, 1.0), foam);
                return half4(col, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
