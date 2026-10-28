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
            GLSLPROGRAM
            // 网页版只有前向渲染，法线纹理不会是八面体编码，_GBUFFER_NORMALS_OCT 变体不需要
            // _CameraDepthTexture / _CameraNormalsTexture、SampleSceneDepth / SampleSceneNormals 由 Core.glsl 提供
            uniform vec4 _EdgeParams;     // x 强度, y 粗细(像素), z 深度阈值, w 法线阈值
            uniform vec4 _EdgeColor;
            uniform vec4 _EdgeBgColor;    // rgb 背景色, a = edgesOnly

            VARYING vec2 texcoord;
            #ifdef VERTEX
            // Blit.hlsl 的 Vert：用 gl_VertexID 生成盖住全屏的大三角形（_BlitTexture、_BlitTexture_TexelSize 等在 Core.glsl 里声明）
            void main()
            {
                vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
                texcoord = p * _BlitScaleBias.xy + _BlitScaleBias.zw;
                gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
            }
            #endif

            #ifdef FRAGMENT
            // URP 14 的 SampleSceneNormals（DeclareNormalsTexture.hlsl）：点采样、不归一化。
            // 背景处法线纹理是清屏的 (0,0,0)，不归一化才能和 Unity 一样让物体轮廓外侧的一圈也算“法线边”。
            vec3 SampleSceneNormalsRaw(vec2 uv)
            {
                ivec2 size = textureSize(_CameraNormalsTexture, 0);
                return texelFetch(_CameraNormalsTexture, clamp(ivec2(uv * vec2(size)), ivec2(0), size - 1), 0).xyz;
            }

            //#region sobel
            // Sobel 核：Gx = [-1 0 1; -2 0 2; -1 0 1]，Gy 为其转置
            const vec2 kOffsets[8] = vec2[8](
                vec2(-1, -1), vec2(0, -1), vec2(1, -1),
                vec2(-1,  0),              vec2(1,  0),
                vec2(-1,  1), vec2(0,  1), vec2(1,  1));
            const float kGx[8] = float[8](-1.0, 0.0, 1.0, -2.0, 2.0, -1.0, 0.0, 1.0);
            const float kGy[8] = float[8](-1.0, -2.0, -1.0, 0.0, 0.0, 1.0, 2.0, 1.0);

            float EdgeAt(vec2 uv)
            {
                vec2 texel = _EdgeParams.y / _ScreenParams.xy;
                float rawCenter = SampleSceneDepth(uv);
                float centerDepth = LinearEyeDepth(rawCenter, _ZBufferParams);

                vec2 gDepth = vec2(0.0);
                vec3 gNx = vec3(0.0), gNy = vec3(0.0);
                for (int i = 0; i < 8; i++)
                {
                    vec2 suv = uv + kOffsets[i] * texel;
                    float d = LinearEyeDepth(SampleSceneDepth(suv), _ZBufferParams);
                    vec3 n = SampleSceneNormalsRaw(suv);
                    gDepth += vec2(kGx[i], kGy[i]) * d;
                    gNx += kGx[i] * n;
                    gNy += kGy[i] * n;
                }

                // 深度梯度除以中心深度：远处物体深度差天然更大，不归一化的话远景会全是线
                float depthEdge = length(gDepth) / max(centerDepth, 1e-3);

                // 掠射角修正：斜着看一个平面（例如远处地面）时，相邻像素深度变化很快，
                // 相对梯度约与 1/(N·V) 成正比。乘上 N·V 把这部分“假边”压下去
                vec3 normalC = SampleSceneNormalsRaw(uv);
                vec3 positionWS = ComputeWorldSpacePosition(uv, rawCenter, UNITY_MATRIX_I_VP);
                vec3 viewDirWS = normalize(GetCameraPositionWS() - positionWS);
                float ndv = saturate(dot(normalC, viewDirWS));
                depthEdge *= ndv;

                float normalEdge = sqrt(dot(gNx, gNx) + dot(gNy, gNy));
                float e = max(step(_EdgeParams.z, depthEdge), step(_EdgeParams.w, normalEdge));
                return e;
            }
            //#endregion

            vec4 Frag()
            {
                vec2 uv = texcoord;
                vec4 color = texture(_BlitTexture, uv);
                float edge = EdgeAt(uv) * _EdgeParams.x;

                vec3 baseColor = mix(color.rgb, _EdgeBgColor.rgb, _EdgeBgColor.a);
                return vec4(mix(baseColor, _EdgeColor.rgb, edge), color.a);
            }
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }
    }
}
