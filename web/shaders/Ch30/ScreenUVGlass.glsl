// 30.7 节问题现场一（错误示范）：一块读取 _CameraOpaqueTexture 的“玻璃”。（GLSL 版，对应 Ch30/ScreenUVGlass.shader）
// _FlipBug = 1 时手动把屏幕 UV 的 y 再翻一次——这是把 OpenGL 时代的经验套到 D3D/Metal 上的典型错误，
// 玻璃里看到的画面会上下颠倒。
Shader "Cookbook/Ch30/ScreenUVGlass"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            ZWrite Off
            GLSLPROGRAM
            uniform vec4  _Tint;
            uniform float _FlipBug;

            #ifdef VERTEX
            void main() { gl_Position = TransformObjectToHClip(positionOS.xyz); }
            #endif

            #ifdef FRAGMENT
            //#region uv
            void main()
            {
                // ✓ 正确：用引擎提供的函数求屏幕 UV（WebGL 的 gl_FragCoord 原点在左下角，和纹理 UV 一致，不需要翻转）
                vec2 uv = GetNormalizedScreenSpaceUV(gl_FragCoord);
                // ✗ 错误：自作主张再翻一次
                if (_FlipBug > 0.5) uv.y = 1.0 - uv.y;
                fragColor = vec4(SampleSceneColor(uv) * _Tint.rgb, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
