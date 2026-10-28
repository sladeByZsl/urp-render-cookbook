// 案例 18.10：X 光扫描线。一道水平光带沿世界 Y 扫过物体，光带后方的“拖尾”区域变成 X 光样式：
// 暗色底 + 菲涅尔轮廓 + 世界空间网格线。全部基于世界坐标，多个物体共用一个扫描高度就能连成一片。
Shader "Cookbook/Ch18/ScanLine"
{
    Properties
    {
        [MainColor] _BaseColor ("Base Color", Color) = (0.7,0.7,0.7,1)
        _Smoothness ("Smoothness", Range(0,1)) = 0.4
        [HDR] _ScanColor ("Scan Color", Color) = (0.3,1.6,1.2,1)
        _ScanHeight ("Scan Height (World Y)", Float) = 1
        _ScanWidth ("Scan Line Width (m)", Range(0.005,0.3)) = 0.03
        _TrailLength ("Trail Length (m)", Range(0,3)) = 0.8
        _GridDensity ("Grid Lines per Meter", Float) = 10
        _XRayTint ("X-Ray Base", Color) = (0.02,0.06,0.08,1)
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" "RenderPipeline"="UniversalPipeline" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
            half  _Smoothness;
            half4 _ScanColor;
            float _ScanHeight;
            half  _ScanWidth;
            half  _TrailLength;
            float _GridDensity;
            half4 _XRayTint;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile _ _FORWARD_PLUS
            #include "Assets/Cookbook/Ch18/Ch18Common.hlsl"

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; };
            struct Varyings  { float4 positionCS : SV_POSITION; float3 positionWS : TEXCOORD0; half3 normalWS : TEXCOORD1; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                return o;
            }

            //#region grid
            // 世界空间网格线：三个轴各算一次“离最近整格线有多近”，用 fwidth 保持线宽恒定为约 1 像素以上
            half WorldGrid(float3 p, float density)
            {
                float3 g = p * density;
                float3 dist = abs(frac(g - 0.5) - 0.5);          // 到最近整数的距离
                float3 w = fwidth(g) * 1.2;
                float3 lines = 1.0 - saturate(dist / max(w, 1e-4));
                return max(lines.x, max(lines.y, lines.z));
            }
            //#endregion

            //#region frag
            half4 frag(Varyings i) : SV_Target
            {
                half3 normalWS = normalize(i.normalWS);
                half3 viewWS = GetWorldSpaceNormalizeViewDir(i.positionWS);
                half3 lit = SimpleLighting(_BaseColor.rgb, i.positionWS, normalWS, _Smoothness);

                float d = _ScanHeight - i.positionWS.y;           // > 0：在扫描线下方（已经被扫过）
                half scanLine = exp(-abs(d) / _ScanWidth);        // 前沿亮线，指数衰减
                half trail = (d > 0.0) ? saturate(1.0 - d / max(_TrailLength, 1e-4)) : 0.0h;

                // X 光样式：暗底 + 轮廓 + 网格
                half rim = FresnelRim(normalWS, viewWS, 2.0h);
                half grid = WorldGrid(i.positionWS, _GridDensity);
                half3 xray = _XRayTint.rgb + _ScanColor.rgb * (rim * 0.8h + grid * 0.5h);

                // 拖尾越靠近前沿越“X 光”，远处渐渐恢复正常着色
                half3 color = lerp(lit, xray, smoothstep(0.0h, 0.35h, trail));
                color += _ScanColor.rgb * scanLine * 2.0h;
                return half4(color, 1);
            }
            //#endregion
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex ShadowVert
            #pragma fragment ShadowFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch18/Ch18ShadowPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex DepthVert
            #pragma fragment DepthFrag
            #include "Assets/Cookbook/Ch18/Ch18ShadowPass.hlsl"
            ENDHLSL
        }
    }
}
