// 案例 25.1：最小的全屏效果——反色 / 去色 / 染色。
// 顶点着色器对应 core 包 Blit.hlsl 里的 Vert（全屏三角形），输入纹理名固定为 _BlitTexture。
Shader "Cookbook/Ch25/Tint"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        // 全屏 Pass 的标配：不测深度、不写深度、不剔除
        ZTest Always ZWrite Off Cull Off

        Pass
        {
            Name "Tint"

            GLSLPROGRAM
            // _BlitTexture、_BlitScaleBias 由引擎（Core.glsl）提供，相当于 Blit.hlsl
            VARYING vec2 texcoord;
            #ifdef VERTEX
            // Blit.hlsl 的 Vert：用 gl_VertexID 生成一个盖住全屏的大三角形
            void main()
            {
                vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
                texcoord = p * _BlitScaleBias.xy + _BlitScaleBias.zw;
                gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
            }
            #endif

            #ifdef FRAGMENT
            // 这些参数由 C# 每帧写入材质，不放 Properties 块
            uniform vec4  _TintColor;    // 乘色
            uniform float _Invert;       // 0..1 反色程度
            uniform float _Desaturate;   // 0..1 去色程度

            //#region frag
            vec4 Frag()
            {
                vec2 uv = texcoord;
                vec4 color = texture(_BlitTexture, uv);

                // 1) 去色：用 Rec.709 亮度权重（相机颜色缓冲是线性空间）
                float luma = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));
                color.rgb = mix(color.rgb, vec3(luma), _Desaturate);

                // 2) 反色：在 sRGB（感知）空间里做 1-x 才像“底片”，在线性空间直接反会整体发白
                vec3 srgb = LinearToSRGB(saturate(color.rgb));
                vec3 inverted = SRGBToLinear(1.0 - srgb);
                color.rgb = mix(color.rgb, inverted, _Invert);

                // 3) 染色
                color.rgb *= _TintColor.rgb;
                return color;
            }
            //#endregion
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }
    }
}
