// 单独查看贴图的某个通道（不受光照影响）。（GLSL 版，对应 Ch13/ChannelView.shader）
// 目标：屏幕上的像素值 = 贴图文件里存的数值。
//   线性贴图（Mask、法线）：采样值就是存的值，输出前做 SRGBToLinear，抵消相机目标的 sRGB 编码；
//   sRGB 贴图（Albedo）：采样时硬件已解码成线性，直接输出，目标编码回去正好还原。
Shader "Cookbook/Ch13/ChannelView"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            uniform vec4  _MainTex_ST;
            uniform float _Channel;
            uniform float _LinearData;
            uniform sampler2D _MainTex;

            VARYING vec2 uv;
            #ifdef VERTEX
            void main() { gl_Position = TransformObjectToHClip(positionOS.xyz); uv = TransformTex(texcoord0.xy, _MainTex_ST); }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                // 注意：采样到的值已经过“导入设置决定的”解码——sRGB 贴图会被转成线性
                vec4 t = texture(_MainTex, uv);
                int ch = int(_Channel);
                vec3 c = ch == 4 ? t.rgb : vec3(t[min(ch, 3)]);
                fragColor = vec4(_LinearData > 0.5 ? SRGBToLinear(c) : c, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
