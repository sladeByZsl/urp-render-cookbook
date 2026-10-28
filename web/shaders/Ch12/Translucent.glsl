// 薄片透射：树叶、耳朵、纸灯笼一类“光能从背面透过来”的薄物体。
// 透射项用 Barré-Brisebois & Bouchard (GDC 2011) 的快速近似，厚度来自程序化叶脉。
// （GLSL 版，对应 Ch12/Translucent.shader）
Shader "Cookbook/Ch12/Translucent"
{
    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }

        GLSLINCLUDE
        uniform vec4  _BaseColor, _VeinColor, _TransColor;
        uniform float _Transmission, _UseThickness, _Distortion, _TransPower, _TransScale, _TransAmbient, _Smoothness;

        //#region leaf
        // 程序化叶片：UV 的 y 从叶柄(0)到叶尖(1)。返回 x=是否在叶内(符号距离)，y=叶脉强度(0~1)
        vec2 LeafShape(vec2 uv)
        {
            float x = uv.x - 0.5, y = uv.y;
            float halfWidth = 0.44 * pow(saturate(sin(PI * y)), 0.75) * (1.0 - 0.35 * y);
            float inside = halfWidth - abs(x);
            float mid = 1.0 - smoothstep(0.004, 0.018, abs(x));                       // 主脉
            float f = fract((y - abs(x) * 0.9) * 7.0);                                // 斜向重复的侧脉
            float side = 1.0 - smoothstep(0.03, 0.09, min(f, 1.0 - f));
            side *= smoothstep(0.02, 0.06, abs(x)) * smoothstep(0.0, 0.1, inside);    // 侧脉，离边缘淡出
            return vec2(inside, saturate(max(mid, side * 0.65)));
        }
        //#endregion
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            Cull Off   // 叶片双面可见

            GLSLPROGRAM
            #include "Ch12/Ch12Common.glsl"

            #ifdef VERTEX
            void main() { Ch12Vert(); }
            #endif

            #ifdef FRAGMENT
            struct MaterialCtx
            {
                vec3 N, V;
                vec3 albedo;
                float thickness;   // 0 = 极薄，1 = 不透光
                float a;
            };

            //#region shade
            vec3 ShadeOneLight(MaterialCtx m, Light light)
            {
                vec3 L = light.direction;
                float NoL = saturate(dot(m.N, L));
                vec3 front = (m.albedo * ADV_INV_PI + AdvSpecularGGX(m.N, m.V, L, m.a, 0.04)) * PI * NoL;

                // 透射：把光方向沿法线“扭”一点（模拟光在叶片内部的散射偏折），
                // 再看视线与 -L' 的接近程度——正对着光源看时最亮
                vec3 Lt = normalize(L + m.N * _Distortion);
                float VoLt = pow(saturate(dot(m.V, -Lt)), _TransPower) * _TransScale;
                vec3 trans = (VoLt + _TransAmbient) * (1.0 - m.thickness) * _TransColor.rgb * m.albedo * _Transmission;

                // 透射光走的是“叶片背面”的阴影：正面阴影图对它没有意义，这里只用距离衰减
                return front * light.color * (light.distanceAttenuation * light.shadowAttenuation)
                     + trans * light.color * light.distanceAttenuation;
            }
            //#endregion

            #include "Ch12/LightLoop.glsl"

            void main()
            {
                vec2 leaf = LeafShape(uv);
                if (leaf.x < 0.0) discard;

                vec3 T, B, N; Ch12BuildFrame(T, B, N);
                N = gl_FrontFacing ? N : -N;   // 背面要翻转法线，否则背面的光照是反的
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                vec2 screenUV = GetNormalizedScreenSpaceUV(gl_FragCoord);

                MaterialCtx m;
                m.N = N; m.V = V;
                m.albedo = mix(_BaseColor.rgb, _VeinColor.rgb, leaf.y * 0.6);
                m.thickness = _UseThickness > 0.5 ? leaf.y * 0.85 : 0.0;
                float pr = 1.0 - _Smoothness;
                m.a = max(pr * pr, 0.002);

                vec3 color = AccumulateDirectLighting(m, positionWS, screenUV);
                color += SampleSH(N) * m.albedo;

                color = MixFog(color, fogFactor);
                fragColor = vec4(color, 1.0);
            }
            #endif
            ENDGLSL
        }

        //#region shadowpass
        // 叶片形状是程序化裁剪的，URP 自带的 ShadowCaster 不知道，所以自己写一个带 clip 的
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Off
            GLSLPROGRAM
            VARYING vec2 uv;
            #ifdef VERTEX
            void main()
            {
                vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
                vec3 normalWS = TransformObjectToWorldNormal(normalOS);
                // _CASTING_PUNCTUAL_LIGHT_SHADOW 在 GLSL 版里是个 uniform
                vec3 L = _CastingPunctualLightShadow > 0.5 ? normalize(_LightPosition - positionWS) : _LightDirection;
                vec4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, L));
                // WebGL 深度不反转（UNITY_REVERSED_Z = 0），走 max 分支
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE * positionCS.w);
                uv = texcoord0.xy;
                gl_Position = positionCS;
            }
            #endif
            #ifdef FRAGMENT
            void main() { if (LeafShape(uv).x < 0.0) discard; fragColor = vec4(0.0); }
            #endif
            ENDGLSL
        }
        //#endregion
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R Cull Off
            GLSLPROGRAM
            VARYING vec2 uv;
            #ifdef VERTEX
            void main() { gl_Position = TransformObjectToHClip(positionOS.xyz); uv = texcoord0.xy; }
            #endif
            #ifdef FRAGMENT
            void main() { if (LeafShape(uv).x < 0.0) discard; fragColor = vec4(gl_FragCoord.z); }
            #endif
            ENDGLSL
        }
    }
}
