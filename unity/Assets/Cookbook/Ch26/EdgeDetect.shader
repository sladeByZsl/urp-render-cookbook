// 案例 26.9：Sobel 描边。对线性深度和法线分别求 Sobel 梯度，任一超过阈值即为边。
Shader "Cookbook/Ch26/EdgeDetect"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off
        Pass
        {
            Name "EdgeDetect"
            HLSLPROGRAM
            #pragma vertex Vert
            #pragma fragment Frag
            // 延迟渲染开启“精确 G-Buffer 法线”时，法线纹理是八面体编码，SampleSceneNormals 需要这个关键字来解码
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/Runtime/Utilities/Blit.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareNormalsTexture.hlsl"

            float4 _EdgeParams;     // x 强度, y 粗细(像素), z 深度阈值, w 法线阈值
            float4 _EdgeColor;
            float4 _EdgeBgColor;    // rgb 背景色, a = edgesOnly

            //#region sobel
            // Sobel 核：Gx = [-1 0 1; -2 0 2; -1 0 1]，Gy 为其转置
            static const float2 kOffsets[8] = {
                float2(-1, -1), float2(0, -1), float2(1, -1),
                float2(-1,  0),                float2(1,  0),
                float2(-1,  1), float2(0,  1), float2(1,  1) };
            static const float kGx[8] = { -1, 0, 1, -2, 2, -1, 0, 1 };
            static const float kGy[8] = { -1, -2, -1, 0, 0, 1, 2, 1 };

            half EdgeAt(float2 uv)
            {
                float2 texel = _EdgeParams.y / _ScreenParams.xy;
                float  rawCenter = SampleSceneDepth(uv);
                float  centerDepth = LinearEyeDepth(rawCenter, _ZBufferParams);

                float2 gDepth = 0;
                float3 gNx = 0, gNy = 0;
                [unroll] for (int i = 0; i < 8; i++)
                {
                    float2 suv = uv + kOffsets[i] * texel;
                    float  d = LinearEyeDepth(SampleSceneDepth(suv), _ZBufferParams);
                    float3 n = SampleSceneNormals(suv);
                    gDepth += float2(kGx[i], kGy[i]) * d;
                    gNx += kGx[i] * n;
                    gNy += kGy[i] * n;
                }

                // 深度梯度除以中心深度：远处物体深度差天然更大，不归一化的话远景会全是线
                float depthEdge = length(gDepth) / max(centerDepth, 1e-3);

                // 掠射角修正：斜着看一个平面（例如远处地面）时，相邻像素深度变化很快，
                // 相对梯度约与 1/(N·V) 成正比。乘上 N·V 把这部分“假边”压下去
                float3 normalC = SampleSceneNormals(uv);
                float3 positionWS = ComputeWorldSpacePosition(uv, rawCenter, UNITY_MATRIX_I_VP);
                float3 viewDirWS = normalize(GetCameraPositionWS() - positionWS);
                float ndv = saturate(dot(normalC, viewDirWS));
                depthEdge *= ndv;

                float normalEdge = sqrt(dot(gNx, gNx) + dot(gNy, gNy));
                half e = max(step(_EdgeParams.z, depthEdge), step(_EdgeParams.w, normalEdge));
                return e;
            }
            //#endregion

            half4 Frag(Varyings input) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                float2 uv = input.texcoord;
                half4 color = SAMPLE_TEXTURE2D_X(_BlitTexture, sampler_LinearClamp, uv);
                half edge = EdgeAt(uv) * _EdgeParams.x;

                half3 baseColor = lerp(color.rgb, _EdgeBgColor.rgb, _EdgeBgColor.a);
                return half4(lerp(baseColor, _EdgeColor.rgb, edge), color.a);
            }
            ENDHLSL
        }
    }
}
