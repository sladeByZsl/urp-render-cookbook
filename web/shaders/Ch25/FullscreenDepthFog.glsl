// 案例 25.3：Full Screen Pass + Requirements=Depth —— 读取 _CameraDepthTexture 做距离雾。
Shader "Cookbook/Ch25/FullscreenDepthFog"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off

        Pass
        {
            Name "DepthFog"
            GLSLPROGRAM
            // _CameraDepthTexture 与 SampleSceneDepth() 由 Core.glsl 提供（相当于 DeclareDepthTexture.hlsl）
            uniform vec4  _FogColor;
            uniform float _FogStart;
            uniform float _FogDensity;

            VARYING vec2 texcoord;
            #ifdef VERTEX
            // Blit.hlsl 的 Vert：全屏三角形
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
                vec2 uv = texcoord;
                vec4 color = texture(_BlitTexture, uv);

                // 原始深度 → 观察空间线性深度（米）。Reversed-Z 的差异由 _ZBufferParams 处理
                float rawDepth = SampleSceneDepth(uv);
                float eyeDepth = LinearEyeDepth(rawDepth, _ZBufferParams);

                // 指数雾：f = 1 - e^(-density * 距离)
                float dist = max(eyeDepth - _FogStart, 0.0);
                float fog = 1.0 - exp(-_FogDensity * dist);
                color.rgb = mix(color.rgb, _FogColor.rgb, fog);
                return color;
            }
            //#endregion
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }
    }
}
