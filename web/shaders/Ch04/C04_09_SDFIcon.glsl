// 案例 4.9：用 2D SDF 拼一个“定位图钉”图标，并加描边、外发光和投影。（GLSL 版）
Shader "Cookbook/Ch04/SDFIcon"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            #include "Ch04/ProceduralCommon.glsl"

            uniform float _Mode, _StrokeWidth, _GlowFalloff, _ShadowSoftness;
            uniform vec4  _ShadowOffset;
            uniform vec4  _FillColor, _StrokeColor, _GlowColor, _BgColor;

            #ifdef FRAGMENT
            //#region pin
            // 图钉 = 圆（头） ∪ 旋转 45° 的方块（尖） − 小圆（孔）
            // 方块的两条下边恰好与圆相切：尖端到圆心距离 = R·√2
            float PinSDF(vec2 p)
            {
                const float R = 0.30;
                vec2 headCenter = vec2(0.0, 0.15);
                float head = SdCircle(p - headCenter, R);
                float halfDiag = R * 0.70710678;                         // 方块半对角线 = R/√2
                vec2 tipCenter = headCenter - vec2(0.0, halfDiag);       // 方块中心在圆心正下方
                vec2 tp = Rotate2D(p - tipCenter, radians(45.0));
                float tip = SdRoundBox(tp, vec2(halfDiag * 0.70710678), 0.012); // 半边长 = 半对角线/√2，小圆角让尖端不扎手
                float body = OpUnion(head, tip);   // 两者相切，直接取 min 就是光滑的；这里用平滑并集反而会鼓出一个包
                float hole = SdCircle(p - headCenter, 0.12);
                return OpSubtract(body, hole);
            }
            //#endregion

            //#region field
            // 把距离场画出来：外部暖色、内部冷色，等高线间隔 0.05，零等值线为白
            vec3 VisualizeField(float d)
            {
                vec3 col = (d > 0.0) ? vec3(0.90, 0.55, 0.30) : vec3(0.25, 0.55, 0.85);
                col *= 1.0 - exp(-5.0 * abs(d));                   // 离边界越远越亮
                col *= 0.75 + 0.25 * cos(TWO_PI * d / 0.05);       // 等高线
                return mix(col, vec3(1.0), 1.0 - smoothstep(0.0, 0.012, abs(d)));
            }
            //#endregion

            //#region booleans
            vec3 Booleans(vec2 uv)
            {
                // 2×2 网格，每格一种布尔运算
                vec2 cellId = floor(uv * 2.0);
                vec2 p = (fract(uv * 2.0) - 0.5) * 2.0;            // 每格内 [-1,1]
                float a = SdCircle(p - vec2(-0.2, 0.05), 0.45);
                float b = SdBox(Rotate2D(p - vec2(0.28, -0.08), 0.4), vec2(0.32, 0.32));
                int op = int(cellId.x + (1.0 - cellId.y) * 2.0);   // 左上 0 右上 1 左下 2 右下 3
                float d = (op == 0) ? OpUnion(a, b)
                        : (op == 1) ? OpSubtract(a, b)
                        : (op == 2) ? OpIntersect(a, b)
                        :             OpSmoothUnion(a, b, 0.25);
                vec3 col = _BgColor.rgb;
                // 淡淡画出两个原始形状的轮廓
                col = mix(col, vec3(0.45, 0.5, 0.56), 1.0 - smoothstep(0.0, fwidth(a) * 1.5, abs(a)));
                col = mix(col, vec3(0.45, 0.5, 0.56), 1.0 - smoothstep(0.0, fwidth(b) * 1.5, abs(b)));
                col = mix(col, _FillColor.rgb, FillAA(d) * 0.9);
                // 格子分隔线
                vec2 g = abs(fract(uv * 2.0 + 0.5) - 0.5) / fwidth(uv * 2.0);
                return mix(col, vec3(0.9, 0.92, 0.95), 1.0 - saturate(min(g.x, g.y) - 0.5));
            }
            //#endregion

            vec4 frag()
            {
                vec2 p = (uv - 0.5) * 1.1;
                if (_Mode > 0.5 && _Mode < 1.5) return vec4(Booleans(uv), 1.0);
                float d = PinSDF(p);
                if (_Mode < 0.5) return vec4(VisualizeField(d), 1.0);
                if (_Mode < 2.5) return vec4(mix(_BgColor.rgb, _FillColor.rgb, FillAA(d)), 1.0);

                //#region styled
                vec3 col = _BgColor.rgb;
                // 1) 投影：在偏移后的位置再求一次距离，用宽 smoothstep 得到软边
                float ds = PinSDF(p - _ShadowOffset.xy);
                col *= 1.0 - 0.6 * (1.0 - smoothstep(-_ShadowSoftness, _ShadowSoftness, ds));
                // 2) 外发光：只在形状外面，按距离指数衰减
                col += _GlowColor.rgb * exp(-max(d, 0.0) * _GlowFalloff) * 0.35;
                // 3) 填充：内部按距离做一点明暗，越靠近边越暗
                vec3 fill = _FillColor.rgb * mix(0.75, 1.15, saturate(-d * 8.0));
                col = mix(col, fill, FillAA(d));
                // 4) 描边：|d| - 半宽 是“沿边界的一条带子”的 SDF
                float stroke = abs(d) - _StrokeWidth * 0.5;
                col = mix(col, _StrokeColor.rgb, FillAA(stroke));
                //#endregion
                return vec4(col, 1.0);
            }

            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }
    }
}
