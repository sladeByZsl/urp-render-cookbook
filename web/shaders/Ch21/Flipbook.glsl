// 案例 21.2：序列帧动画（Flipbook）——按时间算帧号，可选帧间混合；附带图集调试视图（GLSL 版，对应 Ch21/Flipbook.shader）
Shader "Cookbook/Ch21/Flipbook"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" "IgnoreProjector"="True" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off
            GLSLPROGRAM
            #pragma shader_feature_local_fragment _FLIPBOOK_BLEND
            #pragma shader_feature_local_fragment _DEBUG_ATLAS
            #pragma multi_compile_instancing
            #include "Ch21/UVAnim.glsl"

            uniform vec4 _BaseMap_ST;
            uniform vec4 _BaseColor;
            uniform vec4 _Grid;
            uniform float _FPS, _Frame;
            uniform sampler2D _BaseMap;

            VARYING vec2 uv;
            VARYING vec4 vColor;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = texcoord0.xy;
                vColor = color;
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            vec4 frag()
            {
                float frame = _Time.y * _FPS + _Frame;       // 连续的“帧号”，小数部分就是两帧之间的进度

            #if defined(_DEBUG_ATLAS)
                // 调试：整张图集 + 网格线；当前帧描橙框，下一帧描蓝框
                vec4 atlas = texture(_BaseMap, uv);
                vec3 bg = mix(vec3(0.12, 0.16, 0.2), atlas.rgb, atlas.a);
                vec2 cell = uv * _Grid.xy;
                vec2 f = fract(cell);
                float line_ = step(min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)), 0.015);
                float idx = (_Grid.y - 1.0 - floor(cell.y)) * _Grid.x + floor(cell.x);
                float total = _Grid.x * _Grid.y;
                float cur = Ch21Fmod(floor(frame), total), nxt = Ch21Fmod(floor(frame) + 1.0, total);
                float border = step(min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)), 0.05);
                bg = mix(bg, vec3(0.5, 0.55, 0.6), line_);
                bg = mix(bg, vec3(1.0, 0.45, 0.15), border * float(idx == cur));
                bg = mix(bg, vec3(0.25, 0.6, 1.0), border * float(idx == nxt));
                return vec4(bg, 1.0);
            #endif

                vec2 uvA = FlipbookUV(uv, frame, _Grid.xy);
                vec4 c = texture(_BaseMap, uvA);
            #if defined(_FLIPBOOK_BLEND)
                // 帧间混合：再采一张“下一帧”，按小数部分线性插值。代价是多一次采样
                vec2 uvB = FlipbookUV(uv, frame + 1.0, _Grid.xy);
                vec4 cB = texture(_BaseMap, uvB);
                c = mix(c, cB, fract(frame));
            #endif
                c *= _BaseColor * vColor;
                return c;
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }
    }
}
