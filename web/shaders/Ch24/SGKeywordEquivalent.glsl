// 第 24 章：Blackboard Keyword 生成的代码长什么样（GLSL 版）。
// Graph 里建了两个 Keyword：
//   Enum    “Pattern”，Reference = _PATTERN，Entries = STRIPES / DOTS / CHECKER，Definition = Shader Feature，Scope = Local
//   Boolean “Use Rim”，Reference = _USE_RIM_ON，Definition = Shader Feature，Scope = Local
// Shader Graph 会为它们生成 Properties 里的两行和 Pass 里的两行 #pragma —— 与手写完全一致。
Shader "Cookbook/Ch24/SGKeywordEquivalent"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Name "Universal Forward"
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            //#region pragmas
            #pragma shader_feature_local _PATTERN_STRIPES _PATTERN_DOTS _PATTERN_CHECKER
            #pragma shader_feature_local _ _USE_RIM_ON
            //#endregion

            uniform vec4 _ColorA;
            uniform vec4 _ColorB;
            uniform float _Tiling;

            VARYING vec2 uv0;
            VARYING vec3 normalWS;
            VARYING vec3 positionWS;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs p = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = p.positionCS; positionWS = p.positionWS;
                normalWS = TransformObjectToWorldNormal(normalOS);
                uv0 = texcoord0.xy;
            }
            #endif

            #ifdef FRAGMENT
            //#region keyword
            vec4 frag()
            {
                vec2 uv = uv0 * _Tiling;
                float mask;
                // 一个 Enum Keyword 节点 = 一组 #if/#elif，每个分支对应节点上的一个输入口
            #if defined(_PATTERN_STRIPES)
                mask = step(0.5, fract(uv.x + uv.y));
            #elif defined(_PATTERN_DOTS)
                mask = step(length(fract(uv) - 0.5), 0.3);
            #else // _PATTERN_CHECKER
                vec2 c = floor(uv);
                float s = c.x + c.y;
                mask = s - 2.0 * trunc(s / 2.0);   // HLSL 的 fmod(s, 2)（负数时结果为负，与 GLSL 的 mod 不同）
            #endif
                vec3 albedo = mix(_ColorA.rgb, _ColorB.rgb, mask);

                vec3 n = normalize(normalWS);
                Light l = GetMainLight();
                vec3 color = albedo * (l.color * saturate(dot(n, l.direction)) + SampleSH(n));

                // Boolean Keyword 节点 = 一个 #if，On / Off 两个输入口
            #if defined(_USE_RIM_ON)
                vec3 v = GetWorldSpaceNormalizeViewDir(positionWS);
                color += pow(1.0 - saturate(dot(n, v)), 3.0) * vec3(1.0, 0.9, 0.7) * 1.5;
            #endif
                return vec4(color, 1);
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #define CH23_DEPTH_PASS
            #include "Ch23/Ch23Common.glsl"
            ENDGLSL
        }
    }
}
