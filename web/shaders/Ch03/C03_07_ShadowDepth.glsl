// 第 7 步：补上 ShadowCaster 和 DepthOnly 两个 Pass —— 能投射阴影，也能出现在深度图里。
Shader "Cookbook/Ch03/ShadowDepth"
{
    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }

        GLSLINCLUDE
        // CBUFFER_START(UnityPerMaterial)
        uniform vec4  _BaseMap_ST;
        uniform vec4  _BaseColor;
        uniform float _Cutoff;
        // CBUFFER_END

        uniform sampler2D _BaseMap;

        // 三个 Pass 都要做同样的裁剪，抽成函数，保证“看到的形状 = 阴影形状 = 深度形状”
        #ifdef FRAGMENT
        void ClipByAlpha(vec2 uv)
        {
            float a = texture(_BaseMap, uv).a * _BaseColor.a;
            if (a - _Cutoff < 0.0) discard;
        }
        #endif
        ENDGLSL

        // ---------------- 1. 颜色 Pass（与第 6 步相同） ----------------
        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }
            Cull [_Cull]

            GLSLPROGRAM
            #pragma multi_compile_fog

            VARYING vec2 uv;
            VARYING vec4 vColor;
            VARYING float fogFactor;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
                vColor = color;
                fogFactor = ComputeFogFactor(gl_Position.z);
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                vec4 tex = texture(_BaseMap, uv);
                // 裁剪只看 贴图a × 颜色a，与 ClipByAlpha 完全一致；顶点色只影响 rgb
                if (tex.a * _BaseColor.a - _Cutoff < 0.0) discard;
                vec3 rgb = tex.rgb * _BaseColor.rgb * vColor.rgb;
                rgb = MixFog(rgb, fogFactor);
                fragColor = vec4(rgb, 1);
            }
            #endif
            ENDGLSL
        }

        //#region shadow
        // ---------------- 2. 阴影投射 Pass：把物体画进光源的 Shadow Map ----------------
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0          // 只要深度，不写颜色
            Cull [_Cull]

            GLSLPROGRAM
            // 点光/聚光的阴影要用 _LightPosition 逐顶点求光方向，方向光用 _LightDirection。
            // 网页版里 _CASTING_PUNCTUAL_LIGHT_SHADOW 不是关键字，而是 uniform _CastingPunctualLightShadow；
            // _LightDirection / _LightPosition / ApplyShadowBias 都已由 Lighting.glsl 提供（对应 Shadows.hlsl）

            VARYING vec2 uv;

            #ifdef VERTEX
            void main()
            {
                vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
                vec3 normalWS   = TransformObjectToWorldNormal(normalOS);
                vec3 lightDirectionWS = _CastingPunctualLightShadow > 0.5
                    ? normalize(_LightPosition - positionWS)
                    : _LightDirection;
                // 沿光方向和法线方向各推一点，减轻自阴影条纹（Shadow Acne），细节见第 6 章
                positionWS = ApplyShadowBias(positionWS, normalWS, lightDirectionWS);
                gl_Position = TransformWorldToHClip(positionWS);
                // 把超出近平面的投射体压回近平面，避免被裁掉导致阴影缺块
            #if UNITY_REVERSED_Z
                gl_Position.z = min(gl_Position.z, UNITY_NEAR_CLIP_VALUE);
            #else
                gl_Position.z = max(gl_Position.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                ClipByAlpha(uv);   // 镂空的地方不投影
                fragColor = vec4(0.0);
            }
            #endif
            ENDGLSL
        }
        //#endregion

        //#region depth
        // ---------------- 3. 深度 Pass：深度预渲染（Depth Prepass）时把物体写进 _CameraDepthTexture ----------------
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask R          // URP 自带 Shader 的写法；深度写进深度缓冲，颜色通道基本用不到
            Cull [_Cull]

            GLSLPROGRAM
            VARYING vec2 uv;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                ClipByAlpha(uv);
                fragColor = vec4(gl_FragCoord.z);
            }
            #endif
            ENDGLSL
        }
        //#endregion
    }
}
