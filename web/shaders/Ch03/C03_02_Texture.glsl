// 第 2 步：采样一张贴图，支持材质面板上的 Tiling / Offset。
Shader "Cookbook/Ch03/Textured"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            // 顶点输入 texcoord0 是第 0 套 UV
            VARYING vec2 uv;   // 插值器：HLSL 里 TEXCOORDn 只是“通用槽位”的名字，GLSL 直接按变量名对应

            //#region decl
            // GLSL 里纹理和采样器是一个对象 sampler2D，过滤/寻址设置跟着纹理走
            uniform sampler2D _BaseMap;

            uniform vec4 _BaseMap_ST;     // Unity 自动填充：xy = Tiling，zw = Offset
            uniform vec4 _BaseColor;
            //#endregion

            //#region vertfrag
            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                // 等价于 uv * _BaseMap_ST.xy + _BaseMap_ST.zw（HLSL 的 TRANSFORM_TEX）
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                vec4 tex = texture(_BaseMap, uv);
                fragColor = tex * _BaseColor;
            }
            #endif
            //#endregion
            ENDGLSL
        }
    }
}
