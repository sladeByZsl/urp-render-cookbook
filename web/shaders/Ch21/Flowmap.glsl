// 案例 21.3：Flowmap——用一张“流向图”驱动贴图沿任意方向流动，双相位消除跳变（GLSL 版，对应 Ch21/Flowmap.shader）
Shader "Cookbook/Ch21/Flowmap"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForwardOnly" }   // 自定义表面混合，没有 GBuffer Pass：Deferred 下也走前向
            GLSLPROGRAM
            #pragma multi_compile_instancing
            #include "Ch21/UVAnim.glsl"

            uniform vec4 _BaseMap_ST;
            uniform float _FlowStrength;
            uniform float _Speed, _Phase;
            uniform float _Mode, _UseRamp, _Intensity;
            uniform sampler2D _BaseMap;
            uniform sampler2D _FlowMap;
            uniform sampler2D _RampTex;

            VARYING vec2 uv;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = texcoord0.xy;
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            vec4 frag()
            {
                vec4 flowTex = texture(_FlowMap, uv);
                if (_Mode < 0.5) return vec4(flowTex.rg, 0.0, 1.0);          // 直接显示流向图

                // RG 存的是 0..1，映射回 -1..1 的方向向量（0.5 灰 = 静止）
                vec2 flow = (flowTex.rg * 2.0 - 1.0) * _FlowStrength;
                float t = (_Time.y + _Phase) * _Speed;
                vec2 uvB = TransformTex(uv, _BaseMap_ST);

                vec4 c;
                if (_Mode < 1.5)
                {
                    // 单相位：UV 沿流向越漂越远，到 fract 归零时整张图“啪”地跳回原位
                    c = texture(_BaseMap, uvB - flow * fract(t));
                }
                else
                {
                    FlowSample fs = FlowUV(uvB, flow, t);
                    vec4 c0 = texture(_BaseMap, fs.uv0);
                    vec4 c1 = texture(_BaseMap, fs.uv1);
                    c = c0 * fs.w0 + c1 * (1.0 - fs.w0);
                }

                if (_UseRamp > 0.5)
                {
                    float k = smoothstep(0.2, 0.9, c.r);
                    c.rgb = texture(_RampTex, vec2(k, 0.5)).rgb * (k * k * _Intensity);
                }
                return vec4(c.rgb, 1.0);
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }
    }
}
