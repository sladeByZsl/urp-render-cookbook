// 第 2 章 案例 2.2：Depth Texture 与 Opaque Texture 是怎么被“用掉”的
// 一个极简的水面：
//   - 用 _CameraDepthTexture 求“水面到水底的厚度”，做深浅颜色和岸边白沫；
//   - 用 _CameraOpaqueTexture 取水面背后的画面，加一点扰动做折射。
// 两张纹理分别由 URP Asset 的 Depth Texture / Opaque Texture 开关控制。完整的水在第 19 章。
Shader "Cookbook/Ch02/SceneTextures"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" }

        Pass
        {
            Name "Water"
            Tags { "LightMode"="UniversalForward" }
            // 背后的画面我们自己从 Opaque Texture 里取，所以直接覆盖写入，不需要混合
            Blend One Zero
            ZWrite Off

            GLSLPROGRAM
            uniform vec4  _ShallowColor;
            uniform vec4  _DeepColor;
            uniform float _DepthFade;
            uniform float _FoamWidth;
            uniform float _Distortion;
            uniform float _WaveScale;

            VARYING vec3 vPositionWS;
            VARYING vec4 vPositionNDC;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
                gl_Position  = pos.positionCS;
                vPositionWS  = pos.positionWS;
                vPositionNDC = pos.positionNDC;
            }
            #endif

            //#region frag
            #ifdef FRAGMENT
            void main()
            {
                vec2 screenUV = vPositionNDC.xy / vPositionNDC.w;

                // 1) 深度纹理：水底（不透明物体）离相机多远
                float sceneEye   = LinearEyeDepth(SampleSceneDepth(screenUV), _ZBufferParams);
                float surfaceEye = vPositionNDC.w;                  // 透视投影下 clip.w 就是水面自己的观察深度
                float thickness  = max(sceneEye - surfaceEye, 0.0); // 视线穿过的水的厚度（米）

                // 2) 不透明纹理：水面背后的画面，加一点随世界坐标变化的扰动
                vec2 p = vPositionWS.xz * _WaveScale;
                vec2 wave = vec2(sin(p.x + p.y * 0.7), cos(p.y * 1.3 - p.x * 0.4));
                vec2 refrUV = screenUV + wave * _Distortion * saturate(thickness);
                vec3 behind = SampleSceneColor(refrUV);

                // 越深越接近深水色；离岸（厚度接近 0）的地方叠一圈白沫
                float t = saturate(thickness / _DepthFade);
                vec3 col = mix(behind * _ShallowColor.rgb, _DeepColor.rgb, t);
                float foam = 1.0 - saturate(thickness / _FoamWidth);
                col = mix(col, vec3(0.95, 0.98, 1.0), foam);
                fragColor = vec4(col, 1);
            }
            #endif
            //#endregion
            ENDGLSL
        }
    }
}
