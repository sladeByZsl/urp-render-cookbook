// 案例 26.8：CRT。所有效果都在一个 Pass 里按“几何 → 采样 → 逐像素调制”的顺序完成。
Shader "Cookbook/Ch26/Crt"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off
        Pass
        {
            Name "CRT"
            GLSLPROGRAM
            uniform vec4 _CrtParams0;   // x 强度, y 弯曲, z 行数, w 扫描线强度
            uniform vec4 _CrtParams1;   // x 栅格强度, y 闪烁

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
            //#region frag
            vec4 Frag()
            {
                vec2 uv0 = texcoord;

                // 1) 弯曲：把 [-1,1] 坐标按到中心距离的平方向外推，模拟鼓起的玻璃屏
                vec2 p = uv0 * 2.0 - 1.0;
                p *= 1.0 + _CrtParams0.y * dot(p, p) * 0.5;
                vec2 uv = p * 0.5 + 0.5;

                // 屏幕外（被弯曲推出去的部分）是黑色边框；用 SDF 圆角矩形做柔和的边
                vec2 q = abs(p) - (1.0 - 0.06);
                float box = length(max(q, 0.0)) - 0.06;
                float inside = 1.0 - smoothstep(-0.005, 0.005, box);

                // 2) 采样：三个通道错开约 1 像素，像电子枪没对准
                vec2 px = vec2(1.0 / _ScreenParams.x, 0.0);
                vec3 c;
                c.r = texture(_BlitTexture, uv + px).r;
                c.g = texture(_BlitTexture, uv).g;
                c.b = texture(_BlitTexture, uv - px).b;

                // 3) 扫描线：每行中间亮、行间暗；用弯曲后的 uv，扫描线也跟着弯
                float row = uv.y * _CrtParams0.z;
                float scan = 0.5 + 0.5 * cos(row * TWO_PI);
                c *= mix(1.0, 0.35 + 0.65 * scan, _CrtParams0.w);

                // 4) 荧光粉栅格：屏幕像素 x 坐标每 3 列一组，分别偏 R、G、B
                int col = int(mod(texcoord.x * _ScreenParams.x, 3.0));
                vec3 mask = col == 0 ? vec3(1, 0.4, 0.4) : (col == 1 ? vec3(0.4, 1, 0.4) : vec3(0.4, 0.4, 1));
                c *= mix(vec3(1.0), mask * 1.6, _CrtParams1.x);

                // 5) 边缘暗角 + 闪烁（_Time 驱动，截图时 _Time≈0）
                float vignette = saturate(1.0 - dot(p, p) * 0.25);
                float flick = 1.0 - _CrtParams1.y * (0.5 + 0.5 * sin(_Time.y * 110.0));
                c *= vignette * flick * inside;

                // 6) 总强度：和原图插值，方便做“开机/切换”过渡
                vec3 original = texture(_BlitTexture, uv0).rgb;
                return vec4(mix(original, c, _CrtParams0.x), 1.0);
            }
            //#endregion
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }
    }
}
