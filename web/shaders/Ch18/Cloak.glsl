// 案例 18.8：扭曲隐身（光学迷彩）。采样 _CameraOpaqueTexture，按法线把屏幕 UV 推开一点，
// 物体就像一块“透明的玻璃”把身后的画面弯折了。URP Asset 需开启 Opaque Texture。（GLSL 版，对应 Ch18/Cloak.shader）
Shader "Cookbook/Ch18/Cloak"
{
    SubShader
    {
        // 透明队列：画它的时候，不透明物体和天空已经拷贝进 _CameraOpaqueTexture 了
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "Cloak"
            Tags { "LightMode"="UniversalForward" }
            ZWrite On           // 写深度：隐身物体自己的前后遮挡仍然正确（它不是半透明混合，而是整块替换）
            Blend Off

            GLSLPROGRAM
            #include "Ch18/Ch18Common.glsl"
            // _CameraOpaqueTexture / SampleSceneColor 在 Core.glsl 里（对应 DeclareOpaqueTexture.hlsl）

            uniform sampler2D _NoiseMap;
            uniform float _Distortion;
            uniform vec4  _NoiseMap_ST;
            uniform float _NoiseDistortion;
            uniform vec4  _Tint;
            uniform vec4  _RimColor;
            uniform float _RimPower;
            uniform float _Reveal;
            uniform vec4  _BaseColor;
            uniform float _AutoPlay;
            uniform float _Phase;

            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING vec2 uv;

            #ifdef VERTEX
            void main()
            {
                positionWS = TransformObjectToWorld(positionOS.xyz);
                gl_Position = TransformWorldToHClip(positionWS);
                normalWS = TransformObjectToWorldNormal(normalOS);
                uv = TransformTex(texcoord0.xy, _NoiseMap_ST);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            void main()
            {
                float t = _AutoPlay > 0.5 ? _Time.y : _Phase;
                vec3 N = normalize(normalWS);
                vec3 viewWS = GetWorldSpaceNormalizeViewDir(positionWS);
                vec2 screenUV = GetNormalizedScreenSpaceUV(gl_FragCoord);

                // 法线转到观察空间，取 xy 作为屏幕上的“推开方向”：轮廓处法线几乎平行屏幕，推得最远
                vec3 normalVS = TransformWorldToViewDir(N);
                vec2 offset = normalVS.xy * _Distortion;
                // 再叠一层流动噪声，让隐身体表面有“热浪”一样的抖动
                vec2 n = texture(_NoiseMap, uv + vec2(0.0, t * 0.2)).rg - 0.5;
                offset += n * _NoiseDistortion;
                // 观察空间 x 向右、y 向上，与屏幕 UV 方向一致（WebGL 不翻转 y）
                vec3 behind = SampleSceneColor(screenUV + offset) * _Tint.rgb;

                float rim = FresnelRim(N, viewWS, _RimPower);
                vec3 cloak = behind + _RimColor.rgb * rim;

                // 现形：在隐身和正常着色之间插值（实际项目可以叠一个溶解，见案例 18.1）
                vec3 visible = SimpleLighting(_BaseColor.rgb, positionWS, N, 0.4);
                fragColor = vec4(mix(cloak, visible, _Reveal), 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }
    }
}
