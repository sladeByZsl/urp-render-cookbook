// 第 6 步：把材质属性放进 UnityPerMaterial 常量缓冲区，让 Shader 兼容 SRP Batcher。
// （GLSL 版）WebGL 没有 CBUFFER，材质属性就是普通 uniform；结构照 HLSL 版保留，方便对照。
Shader "Cookbook/Ch03/SRPBatcher"
{
    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }

        //#region hlslinclude
        // GLSLINCLUDE（对应 HLSLINCLUDE）里的代码会被自动拼到本 SubShader 每个 Pass 的 GLSLPROGRAM 前面。
        // 把 CBUFFER 写在这里，所有 Pass 的 UnityPerMaterial 布局天然一致。
        GLSLINCLUDE
        // CBUFFER_START(UnityPerMaterial)
        uniform vec4  _BaseMap_ST;
        uniform vec4  _BaseColor;
        uniform float _Cutoff;
        // CBUFFER_END

        // 纹理和采样器不是“数值”，不能也不需要放进 CBUFFER
        uniform sampler2D _BaseMap;
        ENDGLSL
        //#endregion

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }
            Cull [_Cull]

            GLSLPROGRAM
            #pragma multi_compile_fog

            VARYING vec2 uv;
            VARYING vec4 vColor;
            VARYING float fogFactor;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                vColor = color;
                fogFactor = ComputeFogFactor(gl_Position.z);
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                vec4 col = texture(_BaseMap, uv) * _BaseColor * vColor;
                if (col.a - _Cutoff < 0.0) discard;
                col.rgb = MixFog(col.rgb, fogFactor);
                fragColor = vec4(col.rgb, 1);
            }
            #endif
            ENDGLSL
        }
    }
}
