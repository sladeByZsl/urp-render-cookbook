// 案例 4.8：域扭曲（Domain Warping）—— 用噪声去扭曲另一个噪声的输入坐标。（GLSL 版）
Shader "Cookbook/Ch04/DomainWarp"
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

            uniform float _Levels, _Scale, _Strength, _Octaves, _Speed;
            uniform vec4  _Offset;
            uniform vec4  _Color1, _Color2, _Color3, _Color4;

            #ifdef FRAGMENT
            float F(vec2 p) { return Fbm(p, int(_Octaves), 2.0, 0.5); }   // 约 [-1,1]

            void main()
            {
                vec2 p = uv * _Scale + _Offset.xy;
                float t = _Time.y * _Speed;
                //#region warp
                // 第 1 层：q 是一个二维“位移场”，两个分量用两个不同偏移的 fBm
                vec2 q = vec2(0.0);
                if (_Levels >= 1.0)
                    q = vec2(F(p + vec2(0.0, 0.0) + t), F(p + vec2(5.2, 1.3) - t));
                // 第 2 层：拿被 q 扭过的坐标再求一次位移场 r
                vec2 r = vec2(0.0);
                if (_Levels >= 2.0)
                    r = vec2(F(p + _Strength * q + vec2(1.7, 9.2)), F(p + _Strength * q + vec2(8.3, 2.8)));
                // 最终：在被扭曲的坐标上采样
                vec2 warped = p + _Strength * ((_Levels >= 2.0) ? r : q);
                float f = F(warped) * 0.5 + 0.5;
                //#endregion

                //#region color
                // 用 f、|q|、r.x 三个量混色：位移场本身也是很好的“着色依据”
                vec3 col = mix(_Color1.rgb, _Color2.rgb, saturate(f * f * 2.2));
                col = mix(col, _Color4.rgb, saturate(length(q) * 0.9));
                col = mix(col, _Color3.rgb, saturate(abs(r.x) * 1.2) * step(1.5, _Levels));
                col *= 0.6 + 0.6 * f;
                //#endregion
                fragColor = vec4(col, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
