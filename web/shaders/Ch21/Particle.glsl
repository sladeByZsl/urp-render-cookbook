// 案例 21.5–21.7：通用粒子 Shader——顶点色、混合模式、Custom Vertex Streams 帧间混合、软粒子、近相机淡出、渐变映射
// （GLSL 版，对应 Ch21/Particle.shader）
Shader "Cookbook/Ch21/Particle"
{
    SubShader
    {
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent" "IgnoreProjector"="True" "PreviewType"="Plane" }

        Pass
        {
            Name "ForwardUnlit"
            Tags { "LightMode"="UniversalForward" }
            Blend [_SrcBlend] [_DstBlend]
            ZWrite Off
            Cull Off
            GLSLPROGRAM
            #pragma shader_feature_local _FLIPBOOKBLENDING_ON
            #pragma shader_feature_local _SOFTPARTICLES_ON
            #pragma shader_feature_local _CAMERAFADE_ON
            #pragma shader_feature_local_fragment _RAMP_ON
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            // DeclareDepthTexture.hlsl 的 SampleSceneDepth 在引擎 Core.glsl 里

            uniform vec4 _BaseMap_ST;
            uniform vec4 _BaseColor;
            uniform float _Premultiply, _Modulate;
            uniform float _SoftDistance, _CameraFadeNear, _CameraFadeFar;
            uniform float _RampScale;
            uniform sampler2D _BaseMap;
            uniform sampler2D _RampTex;

            //#region streams
            // 与粒子系统 Renderer › Custom Vertex Streams 的顺序一一对应：
            //   Position(POSITION) · Color(COLOR) · UV(TEXCOORD0.xy) · UV2(TEXCOORD0.zw) · AnimBlend(TEXCOORD1.x)
            // GLSL 版的顶点输入名字固定：positionOS、color、texcoord0（xy = 当前帧 UV，zw = 下一帧 UV）、texcoord1（x = 两帧之间的进度 0..1）
            //#endregion

            VARYING vec4 vColor;
            VARYING vec4 uv;           // xy 当前帧，zw 下一帧
            VARYING vec4 screenData;   // xyw = positionNDC，z = 自身观察空间深度
            VARYING vec2 extra;        // x = 帧混合系数，y = 雾

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs p = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = p.positionCS;
                vColor = color;
                extra = vec2(0.0);
            #if defined(_FLIPBOOKBLENDING_ON)
                uv = vec4(TransformTex(texcoord0.xy, _BaseMap_ST), TransformTex(texcoord0.zw, _BaseMap_ST));
                extra.x = texcoord1.x;
            #else
                uv = TransformTex(texcoord0.xy, _BaseMap_ST).xyxy;
            #endif
                screenData = vec4(p.positionNDC.xy, -p.positionVS.z, p.positionNDC.w);
                extra.y = ComputeFogFactor(p.positionCS.z);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            vec4 frag()
            {
                vec4 tex = texture(_BaseMap, uv.xy);
            #if defined(_FLIPBOOKBLENDING_ON)
                vec4 tex2 = texture(_BaseMap, uv.zw);
                tex = mix(tex, tex2, extra.x);
            #endif

                // 顶点色 = 粒子系统的 Start Color × Color over Lifetime：整个粒子系统的颜色变化都从这里进来
                vec4 c = tex * vColor * _BaseColor;

            #if defined(_RAMP_ON)
                // 渐变映射：用“贴图浓度 × 粒子剩余寿命（顶点色 alpha）”去查火焰渐变，越老越暗红
                float k = saturate(tex.a * vColor.a * _RampScale);
                c.rgb = texture(_RampTex, vec2(k, 0.5)).rgb * _BaseColor.rgb;
                c.a = saturate(k);
            #endif

                float thisZ = screenData.z;
            #if defined(_SOFTPARTICLES_ON)
                // 软粒子：比较场景深度与粒子自身深度，越接近（快要插进物体）越透明
                vec2 suv = screenData.xy / screenData.w;
                float sceneZ = LinearEyeDepth(SampleSceneDepth(suv), _ZBufferParams);
                c.a *= saturate((sceneZ - thisZ) / _SoftDistance);
            #endif
            #if defined(_CAMERAFADE_ON)
                // 近相机淡出：粒子贴脸时会糊满屏幕、产生巨大 Overdraw，提前淡掉
                c.a *= saturate((thisZ - _CameraFadeNear) / max(_CameraFadeFar - _CameraFadeNear, 1e-3));
            #endif

                c.rgb *= mix(1.0, c.a, _Premultiply);   // 预乘：Blend One OneMinusSrcAlpha 时需要
                // 正片叠底（Blend DstColor Zero）没有 alpha 参与：把 alpha 折算进颜色，透明处趋向白色（=不改变背景）
                c.rgb = mix(c.rgb, mix(vec3(1.0), c.rgb, c.a), _Modulate);
                // 雾：Alpha 混合直接 MixFog；叠加模式应往黑色雾化 MixFogColor(c.rgb, 0, fog)，否则雾里越叠越亮
                c.rgb = MixFog(c.rgb, extra.y);
                return c;
            }
            //#endregion
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }
    }
}
