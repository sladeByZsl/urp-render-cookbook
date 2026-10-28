// 案例 25.6：读取遮罩 RT，膨胀求外轮廓，再用 Alpha 混合叠到相机颜色上。
// Pass 0：描边 + 填充（混合叠加）；Pass 1：调试用，直接把遮罩显示成灰度（不混合）。
Shader "Cookbook/Ch25/LayerOutline"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off

        GLSLINCLUDE
        // _BlitTexture / _BlitTexture_TexelSize（引擎绑定纹理时自动填写 (1/w, 1/h, w, h)）在 Core.glsl 里已声明
        uniform vec4  _OutlineColor;
        uniform vec4  _FillColor;
        uniform float _OutlineWidth;            // 像素

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

        float Mask(vec2 uv) { return texture(_BlitTexture, uv).r; }
        ENDGLSL

        Pass
        {
            Name "Outline"
            Blend SrcAlpha OneMinusSrcAlpha

            GLSLPROGRAM
            #ifdef FRAGMENT
            //#region frag
            vec4 Frag()
            {
                vec2 uv = texcoord;
                float center = Mask(uv);

                // 膨胀（Dilation）：在半径 = 线宽、线宽/2 的两圈圆周上各取 12 个样本，求最大值
                vec2 r = _BlitTexture_TexelSize.xy * _OutlineWidth;
                float dilated = center;
                for (int k = 0; k < 12; k++)
                {
                    float a = float(k) * (TWO_PI / 12.0);
                    vec2 dir = vec2(cos(a), sin(a));
                    dilated = max(dilated, Mask(uv + dir * r));
                    dilated = max(dilated, Mask(uv + dir * r * 0.5));
                }

                // 膨胀后的区域减去原区域 = 物体外侧一圈
                float outline = saturate(dilated - center);
                vec3 rgb = mix(_FillColor.rgb, _OutlineColor.rgb, outline);
                float alpha = outline * _OutlineColor.a + center * _FillColor.a;
                return vec4(rgb, alpha);
            }
            //#endregion
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DebugMask"
            Blend Off
            GLSLPROGRAM
            #ifdef FRAGMENT
            void main()
            {
                float m = Mask(texcoord);
                fragColor = vec4(mix(vec3(0.03, 0.04, 0.06), vec3(1.0), m), 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
