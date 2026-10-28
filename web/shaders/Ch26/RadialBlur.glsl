// 案例 26.5：径向模糊——沿“像素 → 中心”的方向多次采样求平均。
Shader "Cookbook/Ch26/RadialBlur"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off
        Pass
        {
            Name "RadialBlur"
            GLSLPROGRAM
            uniform vec4  _RadialParams;   // xy 中心, z 强度, w 采样数
            uniform float _ClearRadius;

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
            float InterleavedGradientNoise(vec2 pixel)
            {
                return fract(52.9829189 * fract(dot(pixel, vec2(0.06711056, 0.00583715))));
            }

            //#region frag
            vec4 Frag()
            {
                vec2 uv = texcoord;
                vec2 center = _RadialParams.xy;
                vec2 dir = uv - center;                         // 指向外侧，长度 = 到中心的距离

                // 中心一圈保持清晰：按宽高比修正成正圆后再算距离
                float aspect = _ScreenParams.x / _ScreenParams.y;
                float dist = length(dir * vec2(aspect, 1.0));
                float amount = _RadialParams.z * smoothstep(_ClearRadius, _ClearRadius + 0.25, dist);

                int count = int(_RadialParams.w);
                // 每个像素的起点加一点抖动，把“分层的重影”变成细噪点
                float jitter = InterleavedGradientNoise(uv * _ScreenParams.xy);
                vec3 sum = vec3(0.0);
                for (int i = 0; i < count; i++)
                {
                    float t = (float(i) + jitter) / float(count);   // 0..1
                    vec2 s = uv - dir * amount * 0.3 * t;           // 向中心方向收缩
                    sum += texture(_BlitTexture, s).rgb;
                }
                return vec4(sum / float(count), 1.0);
            }
            //#endregion
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }
    }
}
