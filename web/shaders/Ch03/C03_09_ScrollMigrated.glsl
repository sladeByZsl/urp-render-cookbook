// 案例 3.9：把一个 Built-in 管线的“滚动贴图 Unlit”迁移到 URP。
// 对照正文里的 Built-in 原版逐行看：每一处改动都对应对照表里的一行。
Shader "Cookbook/Ch03/ScrollMigrated"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        // CBUFFER_START(UnityPerMaterial)
        uniform vec4 _BaseMap_ST;
        uniform vec4 _BaseColor;
        uniform vec4 _ScrollSpeed;
        uniform vec4 _ScrollOffset;
        // CBUFFER_END

        uniform sampler2D _BaseMap;
        ENDGLSL

        //#region pass
        Pass
        {
            Name "Unlit"
            // Unlit 用 UniversalForwardOnly：切到 Deferred 渲染路径也不会消失（见正文 3.4 节）
            Tags { "LightMode"="UniversalForwardOnly" }

            GLSLPROGRAM                                  // CGPROGRAM → HLSLPROGRAM（网页版：GLSLPROGRAM）
            #pragma multi_compile_fog

            // appdata → Attributes（网页版：固定名字的顶点输入 positionOS / texcoord0 / color）
            // v2f → Varyings（网页版：逐个 VARYING）
            VARYING vec2 uv;
            VARYING vec4 vColor;                         // fixed4 → half4（URP 不再有 fixed）
            VARYING float fogFactor;                     // UNITY_FOG_COORDS(1) → 自己声明

            #ifdef VERTEX
            void main()
            {
                // UnityObjectToClipPos → TransformObjectToHClip
                gl_Position = TransformObjectToHClip(positionOS.xyz);
                // _Time.y 的含义与 Built-in 相同：游戏开始后的秒数
                vec2 scroll = _ScrollSpeed.xy * _Time.y + _ScrollOffset.xy;
                uv = TransformTex(texcoord0.xy, _BaseMap_ST) + scroll;
                vColor = color;
                // UNITY_TRANSFER_FOG(o, o.pos) → ComputeFogFactor
                fogFactor = ComputeFogFactor(gl_Position.z);
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                // tex2D(_MainTex, uv) → SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv)（网页版：texture）
                vec4 col = texture(_BaseMap, uv) * _BaseColor * vColor;
                // UNITY_APPLY_FOG(i.fogCoord, col) → MixFog
                col.rgb = MixFog(col.rgb, fogFactor);
                fragColor = vec4(col.rgb, 1);
            }
            #endif
            ENDGLSL
        }
        //#endregion

        // Built-in 版本靠 Fallback 借来阴影 Pass；URP 里自己写一个最简的 ShadowCaster
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ColorMask 0

            GLSLPROGRAM
            // _CASTING_PUNCTUAL_LIGHT_SHADOW 在网页版是 uniform _CastingPunctualLightShadow；ApplyShadowBias 等由 Lighting.glsl 提供
            #ifdef VERTEX
            void main()
            {
                vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
                vec3 normalWS   = TransformObjectToWorldNormal(normalOS);
                vec3 lightDirectionWS = _CastingPunctualLightShadow > 0.5
                    ? normalize(_LightPosition - positionWS)
                    : _LightDirection;
                gl_Position = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
            #if UNITY_REVERSED_Z
                gl_Position.z = min(gl_Position.z, UNITY_NEAR_CLIP_VALUE);
            #else
                gl_Position.z = max(gl_Position.z, UNITY_NEAR_CLIP_VALUE);
            #endif
            }
            #endif

            #ifdef FRAGMENT
            void main() { fragColor = vec4(0.0); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask R

            GLSLPROGRAM
            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
            }
            #endif

            #ifdef FRAGMENT
            void main() { fragColor = vec4(gl_FragCoord.z); }
            #endif
            ENDGLSL
        }
    }
}
