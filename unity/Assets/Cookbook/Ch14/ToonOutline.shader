// 背面外扩描边（Back-face Outline / Inverted Hull）。
// 第二个 Pass 只画背面，并把顶点沿法线推出去，露出来的一圈就是轮廓线。
Shader "Cookbook/Ch14/ToonOutline"
{
    Properties
    {
        [MainColor] _BaseColor ("Base Color", Color) = (0.95, 0.75, 0.35, 1)
        _ShadeColor ("Shade Color", Color) = (0.7, 0.42, 0.3, 1)
        [Header(Outline)]
        _OutlineColor ("Outline Color", Color) = (0.12, 0.08, 0.1, 1)
        [KeywordEnum(Object, Clip)] _OutlineSpace ("Extrude Space", Float) = 1
        _OutlineWidth ("Width (px, Clip mode)", Range(0, 10)) = 3
        _OutlineWidthOS ("Width (object units, Object mode)", Range(0, 0.1)) = 0.02
        [KeywordEnum(Mesh, Tangent, VertexColor)] _OutlineNormal ("Extrude Normal Source", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor, _ShadeColor, _OutlineColor;
            half  _OutlineWidth, _OutlineWidthOS;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ToonForward"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex ToonVert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch14/ToonCommon.hlsl"
            half4 frag(ToonVaryings i) : SV_Target
            {
                half3 N = normalize(i.normalWS);
                Light light = GetMainLight();
                half band = ToonBand(dot(N, light.direction) * 0.5 + 0.5, 0.5, 0.02);
                half3 color = lerp(_ShadeColor.rgb, _BaseColor.rgb, band) * light.color;
                color += SampleSH(half3(0, 0, 0)) * _BaseColor.rgb * 0.3;
                return half4(MixFog(color, i.fogFactor), 1);
            }
            ENDHLSL
        }

        //#region outlinepass
        Pass
        {
            Name "Outline"
            // URP 的不透明队列会画 UniversalForward 和 SRPDefaultUnlit 两种 LightMode，
            // 所以第二个 Pass 用 SRPDefaultUnlit 就能自动被画到，不需要 Renderer Feature
            Tags { "LightMode"="SRPDefaultUnlit" }
            Cull Front      // 只画背面
            ZWrite On

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local_vertex _OUTLINESPACE_OBJECT _OUTLINESPACE_CLIP
            #pragma shader_feature_local_vertex _OUTLINENORMAL_MESH _OUTLINENORMAL_TANGENT _OUTLINENORMAL_VERTEXCOLOR
            #pragma multi_compile_fog
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch14/ToonCommon.hlsl"

            struct OutlineVaryings
            {
                float4 positionCS : SV_POSITION;
                float  fogFactor  : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            // 取“用来外扩的法线”：原始法线 / 烘焙在切线里的平滑法线 / 烘焙在顶点色里的切线空间平滑法线
            float3 GetOutlineNormalOS(ToonAttributes v)
            {
            #if defined(_OUTLINENORMAL_TANGENT)
                return v.tangentOS.xyz;                               // 物体空间平滑法线
            #elif defined(_OUTLINENORMAL_VERTEXCOLOR)
                float3 nTS = v.color.rgb * 2.0 - 1.0;                  // 切线空间平滑法线
                float3 bitangentOS = cross(v.normalOS, v.tangentOS.xyz) * v.tangentOS.w;
                return normalize(nTS.x * v.tangentOS.xyz + nTS.y * bitangentOS + nTS.z * v.normalOS);
            #else
                return v.normalOS;
            #endif
            }

            OutlineVaryings vert(ToonAttributes v)
            {
                OutlineVaryings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                float3 n = GetOutlineNormalOS(v);
            #if defined(_OUTLINESPACE_OBJECT)
                o.positionCS = OutlinePositionCS_ObjectSpace(v.positionOS.xyz, n, _OutlineWidthOS);
            #else
                o.positionCS = OutlinePositionCS(v.positionOS.xyz, n, _OutlineWidth);
            #endif
                o.fogFactor = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(OutlineVaryings i) : SV_Target
            {
                return half4(MixFog(_OutlineColor.rgb, i.fogFactor), 1);
            }
            ENDHLSL
        }
        //#endregion

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0 Cull Back
            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            // URP 自带的阴影 Pass 只在 _ALPHATEST_ON 时才读 _BaseMap，其余部分与材质无关，直接复用
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R Cull Back
            HLSLPROGRAM
            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthOnlyPass.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On Cull Back
            HLSLPROGRAM
            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment
            #pragma multi_compile_instancing
            #include "Packages/com.unity.render-pipelines.universal/Shaders/DepthNormalsPass.hlsl"
            ENDHLSL
        }
    }
}
