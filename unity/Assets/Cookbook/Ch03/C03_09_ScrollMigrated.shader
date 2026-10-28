// 案例 3.9：把一个 Built-in 管线的“滚动贴图 Unlit”迁移到 URP。
// 对照正文里的 Built-in 原版逐行看：每一处改动都对应对照表里的一行。
Shader "Cookbook/Ch03/ScrollMigrated"
{
    Properties
    {
        // _MainTex → _BaseMap，_Color → _BaseColor：沿用 URP 命名，换 Shader 时材质参数能自动对上
        [MainTexture] _BaseMap ("Texture", 2D) = "white" {}
        [MainColor]   _BaseColor ("Tint", Color) = (1, 1, 1, 1)
        _ScrollSpeed ("Scroll Speed (xy)", Vector) = (0.2, 0, 0, 0)
        // 额外的手动偏移：编辑器里静帧截图或用动画/脚本驱动时用
        _ScrollOffset ("Scroll Offset (xy)", Vector) = (0, 0, 0, 0)
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4  _BaseColor;
            float4 _ScrollSpeed;
            float4 _ScrollOffset;
        CBUFFER_END

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);
        ENDHLSL

        //#region pass
        Pass
        {
            Name "Unlit"
            // Unlit 用 UniversalForwardOnly：切到 Deferred 渲染路径也不会消失（见正文 3.4 节）
            Tags { "LightMode"="UniversalForwardOnly" }

            HLSLPROGRAM                                  // CGPROGRAM → HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog

            struct Attributes                            // appdata → Attributes
            {
                float4 positionOS : POSITION;            // vertex → positionOS
                float2 uv         : TEXCOORD0;
                half4  color      : COLOR;               // fixed4 → half4（URP 不再有 fixed）
            };

            struct Varyings                              // v2f → Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                half4  color      : COLOR;
                float  fogFactor  : TEXCOORD1;           // UNITY_FOG_COORDS(1) → 自己声明
            };

            Varyings vert (Attributes input)
            {
                Varyings output;
                // UnityObjectToClipPos → TransformObjectToHClip
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                // _Time.y 的含义与 Built-in 相同：游戏开始后的秒数
                float2 scroll = _ScrollSpeed.xy * _Time.y + _ScrollOffset.xy;
                output.uv = TRANSFORM_TEX(input.uv, _BaseMap) + scroll;
                output.color = input.color;
                // UNITY_TRANSFER_FOG(o, o.pos) → ComputeFogFactor
                output.fogFactor = ComputeFogFactor(output.positionCS.z);
                return output;
            }

            half4 frag (Varyings input) : SV_Target
            {
                // tex2D(_MainTex, uv) → SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv)
                half4 col = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.uv) * _BaseColor * input.color;
                // UNITY_APPLY_FOG(i.fogCoord, col) → MixFog
                col.rgb = MixFog(col.rgb, input.fogFactor);
                return half4(col.rgb, 1);
            }
            ENDHLSL
        }
        //#endregion

        // Built-in 版本靠 Fallback 借来阴影 Pass；URP 里自己写一个最简的 ShadowCaster
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            // Shadows.hlsl 用到了 CommonMaterial.hlsl 里的 LerpWhiteTo，单独引用时要先包含它
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings   { float4 positionCS : SV_POSITION; };

            Varyings ShadowVert (Attributes input)
            {
                Varyings output;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                float3 normalWS   = TransformObjectToWorldNormal(input.normalOS);
            #if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
                float3 lightDirectionWS = normalize(_LightPosition - positionWS);
            #else
                float3 lightDirectionWS = _LightDirection;
            #endif
                output.positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
            #if UNITY_REVERSED_Z
                output.positionCS.z = min(output.positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                output.positionCS.z = max(output.positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                return output;
            }

            half4 ShadowFrag (Varyings input) : SV_Target { return 0; }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask R

            HLSLPROGRAM
            #pragma vertex DepthVert
            #pragma fragment DepthFrag

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings   { float4 positionCS : SV_POSITION; };

            Varyings DepthVert (Attributes input)
            {
                Varyings output;
                output.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return output;
            }

            half DepthFrag (Varyings input) : SV_Target { return input.positionCS.z; }
            ENDHLSL
        }
    }
}
