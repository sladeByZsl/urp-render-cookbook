// 案例 23.3：平面投影阴影（Planar Shadow）。
// 第一个 Pass 正常着色；第二个 Pass（SRPDefaultUnlit）把同一个网格沿主光方向“拍扁”到地面上，
// 输出半透明的阴影色，并用模板测试保证同一个像素只被阴影覆盖一次，避免重叠部分变黑。
Shader "Cookbook/Ch23/PlanarShadow"
{
    Properties
    {
        [MainColor] _BaseColor ("Base Color", Color) = (0.9, 0.6, 0.3, 1)
        _ShadowColor ("Shadow Color", Color) = (0.05, 0.06, 0.1, 0.65)
        _PlaneHeight ("Plane Height (世界空间 y)", Float) = 0
        _ShadowFalloff ("Height Falloff", Range(0, 2)) = 0.35
        [Enum(UnityEngine.Rendering.CompareFunction)] _StencilComp ("Stencil Comp", Float) = 6  // 6 = NotEqual
    }
    SubShader
    {
        // 排在普通不透明物体之后，保证地面已经画好，阴影才能混合到地面颜色上
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry+10" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
            half4 _ShadowColor;
            float _PlaneHeight;
            float _ShadowFalloff;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings { float4 positionCS : SV_POSITION; half3 normalWS : TEXCOORD0; };
            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                return o;
            }
            half4 frag(Varyings i) : SV_Target
            {
                half3 n = normalize(i.normalWS);
                Light l = GetMainLight();
                half3 c = _BaseColor.rgb * (l.color * saturate(dot(n, l.direction)) + SampleSH(n));
                return half4(c, 1);
            }
            ENDHLSL
        }

        //#region planar
        Pass
        {
            Name "PlanarShadow"
            Tags { "LightMode"="SRPDefaultUnlit" }   // URP 会把它和 UniversalForward 一起画

            Stencil
            {
                Ref 1
                Comp [_StencilComp]   // NotEqual：这个像素还没画过阴影才画
                Pass Replace          // 画过就把模板写成 1，后面的阴影三角形再来就被拒绝
            }
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings { float4 positionCS : SV_POSITION; half fade : TEXCOORD0; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                // _MainLightPosition.xyz 对方向光来说是“指向光源”的单位向量 L
                float3 L = normalize(_MainLightPosition.xyz);

                // 求沿 -L 方向走多远能碰到平面 y = h：  P' = P - L * (P.y - h) / L.y
                float height = positionWS.y - _PlaneHeight;
                float3 projected = positionWS - L * (height / max(L.y, 1e-3));
                projected.y = _PlaneHeight + 0.002;   // 抬高 2 毫米，避免与地面 Z-Fighting

                o.positionCS = TransformWorldToHClip(projected);
                // 离地越高的部位投下的阴影越淡，模拟真实阴影随距离变软变淡
                o.fade = saturate(1.0 - height * _ShadowFalloff);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                return half4(_ShadowColor.rgb, _ShadowColor.a * i.fade);
            }
            ENDHLSL
        }
        //#endregion

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex Ch23DepthOnlyVert
            #pragma fragment Ch23NullFrag
            #include "Assets/Cookbook/Ch23/Ch23Common.hlsl"
            ENDHLSL
        }
    }
}
