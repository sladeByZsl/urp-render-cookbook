// Matcap（材质捕获）：把“一颗已经打好光的球”的照片，按观察空间法线贴到物体上。
// 作为环境光照的对照：它便宜、好调，但光照永远跟着相机走，与场景无关。
Shader "Cookbook/Ch08/Matcap"
{
    Properties
    {
        [NoScaleOffset] _MatCap("MatCap", 2D) = "gray" {}
        _Tint("Tint", Color) = (1, 1, 1, 1)
        [Toggle] _PerspectiveFix("Perspective Fix", Float) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _Tint;
            half _PerspectiveFix;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            TEXTURE2D(_MatCap); SAMPLER(sampler_MatCap);

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings { float4 positionCS : SV_POSITION; float3 normalVS : TEXCOORD0; float3 positionVS : TEXCOORD1; };

            Varyings vert(Attributes input)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(positionWS);
                o.positionVS = TransformWorldToView(positionWS);
                o.normalVS = TransformWorldToViewDir(TransformObjectToWorldNormal(input.normalOS));
                return o;
            }

            //#region matcap
            half4 frag(Varyings i) : SV_Target
            {
                float3 n = normalize(i.normalVS);
                float2 uv;
                if (_PerspectiveFix > 0.5)
                {
                    // 透视修正：用“视线方向”构造一个局部坐标系，再把法线投影进去。
                    // 否则物体在画面边缘时，Matcap 会被明显拉扯（只有正交相机下 n.xy 才是准确的）
                    float3 v = normalize(i.positionVS);          // 观察空间里从相机指向表面
                    float3 r = cross(v, n);
                    uv = float2(-r.y, r.x);
                }
                else
                {
                    uv = n.xy;                                   // 经典写法：直接取观察空间法线的 xy
                }
                uv = uv * 0.5 + 0.5;
                half3 c = SAMPLE_TEXTURE2D(_MatCap, sampler_MatCap, uv).rgb * _Tint.rgb;
                return half4(c, 1);
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex Ch08DepthVert
            #pragma fragment Ch08NullFrag
            #include "Assets/Cookbook/Ch08/Ch08Passes.hlsl"
            ENDHLSL
        }
    }
}
