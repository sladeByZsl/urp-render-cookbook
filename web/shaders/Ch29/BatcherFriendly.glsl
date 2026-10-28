// 案例 29.1：一个“对合批友好”的最小 Shader：（GLSL 版，对应 Ch29/BatcherFriendly.shader）
//  · 所有材质属性都在 UnityPerMaterial CBUFFER 里 → SRP Batcher 兼容
//  · 支持 GPU Instancing（multi_compile_instancing），并把颜色做成可逐实例覆盖的属性
//  · 支持 LOD Cross-Fade（与 URP Lit 相同的关键字与函数）
// WebGL 没有 SRP Batcher / CBUFFER；逐实例颜色在网页版里是逐物体 uniform（由引擎按物体设置）。
Shader "Cookbook/Ch29/BatcherFriendly"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            #pragma multi_compile_fragment _ LOD_FADE_CROSSFADE

            //#region cbuffer
            uniform sampler2D _BaseMap;
            // SRP Batcher：每个材质一份常量缓冲，布局在所有变体里必须一致
            uniform vec4 _BaseMap_ST;
            uniform vec4 _BaseColor;

            // GPU Instancing：允许用 MaterialPropertyBlock 逐实例覆盖颜色
            uniform vec4 _InstanceColor;
            //#endregion

            #if defined(LOD_FADE_CROSSFADE)
            uniform vec4 unity_LODFade;   // x = 淡入淡出进度
            // URP LODCrossFade.hlsl 的简化版：按屏幕位置的有序抖动裁剪
            void LODFadeCrossFade(vec4 positionCS)
            {
                vec2 p = mod(floor(positionCS.xy), 4.0);
                float dither = (mod(p.x * 4.0 + p.y * 7.0, 16.0) + 0.5) / 16.0;
                float fade = unity_LODFade.x;
                if ((fade >= 0.0 ? fade - dither : dither + fade) < 0.0) discard;
            }
            #endif

            VARYING vec2 uv;
            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
            #if defined(LOD_FADE_CROSSFADE)
                LODFadeCrossFade(gl_FragCoord);   // 抖动裁剪，两级 LOD 交叉淡入淡出
            #endif
                vec4 tint = _InstanceColor;
                vec3 albedo = texture(_BaseMap, uv).rgb * _BaseColor.rgb;
                albedo *= any(greaterThan(tint.rgb, vec3(0.0))) ? tint.rgb : vec3(1.0);   // 没设置逐实例颜色时为 0，退回材质颜色
                Light light = GetMainLight();
                float ndl = saturate(dot(normalize(normalWS), light.direction));
                vec3 color = albedo * (light.color * ndl + SampleSH(normalize(normalWS)));
                fragColor = vec4(color, 1.0);
            }
            #endif
            ENDGLSL
        }
    }
}
