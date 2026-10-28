// 案例 25.7：把“幽灵层”RT 半透明地合成回屏幕，并与场景深度比较实现正确遮挡。
Shader "Cookbook/Ch25/GhostComposite"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" }
        ZTest Always ZWrite Off Cull Off
        Blend SrcAlpha OneMinusSrcAlpha

        Pass
        {
            Name "GhostComposite"
            GLSLPROGRAM
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
            // _BlitTexture_TexelSize、_CameraDepthTexture / SampleSceneDepth 由 Core.glsl 提供
            uniform highp sampler2D _GhostDepth;      // 幽灵层自己的深度
            uniform float _Opacity;
            uniform vec4  _Tint;
            uniform vec4  _RimColor;
            uniform float _RimWidth;

            //#region frag
            vec4 Frag()
            {
                vec2 uv = texcoord;
                // sampler_PointClamp：按纹素整数坐标取，不做双线性
                ivec2 pix = ivec2(uv * _BlitTexture_TexelSize.zw);
                vec4 ghost = texelFetch(_BlitTexture, pix, 0);

                // 1) 遮挡：幽灵层深度 与 场景深度 都换成线性深度再比较，与平台的 Reversed-Z 无关
                float ghostEye = LinearEyeDepth(texelFetch(_GhostDepth, pix, 0).r, _ZBufferParams);
                float sceneEye = LinearEyeDepth(SampleSceneDepth(uv), _ZBufferParams);
                float visible = step(ghostEye, sceneEye + 0.01);

                // 2) 轮廓光：覆盖率（alpha）在邻域里的最小值 < 1 说明靠近剪影边缘
                vec2 r = _BlitTexture_TexelSize.xy * _RimWidth;
                float minA = ghost.a;
                minA = min(minA, texture(_BlitTexture, uv + vec2( r.x, 0.0)).a);
                minA = min(minA, texture(_BlitTexture, uv + vec2(-r.x, 0.0)).a);
                minA = min(minA, texture(_BlitTexture, uv + vec2(0.0,  r.y)).a);
                minA = min(minA, texture(_BlitTexture, uv + vec2(0.0, -r.y)).a);
                float rim = ghost.a * (1.0 - minA);

                // 3) 整层统一透明度：内部的穿插面在离屏 RT 里已被深度测试剔除，合成时看不到
                vec3 rgb = ghost.rgb * _Tint.rgb + _RimColor.rgb * rim;
                float alpha = saturate(ghost.a * _Opacity + rim) * visible;
                return vec4(rgb, alpha);
            }
            //#endregion
            void main() { fragColor = Frag(); }
            #endif
            ENDGLSL
        }
    }
}
