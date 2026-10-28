// 第 4 步：透明度裁剪（Alpha Clip / Alpha Test）。alpha 低于阈值的像素直接丢弃。
Shader "Cookbook/Ch03/AlphaClip"
{
    SubShader
    {
        // AlphaTest 队列（2450）排在普通不透明物体之后，RenderType 让替换着色/工具识别它
        Tags { "RenderType"="TransparentCutout" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }
            Cull [_Cull]                         // 渲染状态可以引用属性，用方括号

            GLSLPROGRAM
            VARYING vec2 uv;
            VARYING vec4 vColor;

            uniform sampler2D _BaseMap;
            uniform vec4  _BaseMap_ST;
            uniform vec4  _BaseColor;
            uniform float _Cutoff;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                vColor = color;
            }
            #endif

            //#region frag
            #ifdef FRAGMENT
            void main()
            {
                vec4 col = texture(_BaseMap, uv) * _BaseColor * vColor;
                // clip(x)：x < 0 时丢弃当前片元，不写颜色也不写深度。GLSL 里写成 discard
                if (col.a - _Cutoff < 0.0) discard;
                fragColor = vec4(col.rgb, 1);        // 不透明物体输出 alpha=1
            }
            #endif
            //#endregion
            ENDGLSL
        }
    }
}
