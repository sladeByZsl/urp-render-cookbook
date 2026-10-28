// 案例 21.8：热扭曲（Heat Distortion）——采样 _CameraOpaqueTexture，按滚动噪声偏移屏幕 UV（GLSL 版，对应 Ch21/HeatDistortion.shader）
Shader "Cookbook/Ch21/HeatDistortion"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" "IgnoreProjector"="True" }

        Pass
        {
            Name "Distortion"
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Off
            GLSLPROGRAM
            #pragma multi_compile_instancing
            // DeclareOpaqueTexture.hlsl 的 SampleSceneColor 在引擎 Core.glsl 里

            uniform float _Strength;
            uniform vec4 _NoiseTiling;
            uniform float _RiseSpeed, _Phase;
            uniform float _ShowOffset;
            uniform sampler2D _NoiseTex;
            uniform sampler2D _MaskTex;

            VARYING vec2 uv;
            VARYING vec4 screenData;   // xyw = positionNDC，z = 观察空间深度
            VARYING vec4 vColor;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs p = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = p.positionCS;
                uv = texcoord0.xy;
                screenData = vec4(p.positionNDC.xy, -p.positionVS.z, p.positionNDC.w);
                vColor = color;
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            vec4 frag()
            {
                float t = _Time.y + _Phase;
                // 两次错位采样单通道噪声，拼成一个二维偏移向量；整体向上滚动，像热空气上升
                vec2 nuv = uv * _NoiseTiling.xy + vec2(0.0, -fract(t * _RiseSpeed));
                float nx = texture(_NoiseTex, nuv).r - 0.5;
                float ny = texture(_NoiseTex, nuv * 1.31 + 0.37).r - 0.5;
                float mask = texture(_MaskTex, uv).a * vColor.a;

                // 屏幕上的偏移量除以深度：同样的“空气扰动”，离得越远在屏幕上越小
                vec2 offset = vec2(nx, ny) * (_Strength * mask) / max(screenData.z * 0.2, 1.0);

                // 调试：把偏移量放大后显示，R/G = 水平/竖直偏移，0.5 灰为不偏移
                if (_ShowOffset > 0.5) return vec4(offset * (1.5 / max(_Strength, 1e-4)) + 0.5, 0.5, 1.0);

                vec2 suv = screenData.xy / screenData.w;
                vec3 scene = SampleSceneColor(suv + offset);
                return vec4(scene, saturate(mask * 3.0));
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }
    }
}
