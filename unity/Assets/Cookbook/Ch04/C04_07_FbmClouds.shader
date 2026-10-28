// 案例 4.7：fBm 云纹 —— 叠加多层噪声，加上覆盖率和软边，就是一片天空。
Shader "Cookbook/Ch04/FbmClouds"
{
    Properties
    {
        [IntRange] _Octaves ("Octaves", Range(1, 10)) = 6
        _Scale ("Scale", Float) = 3
        _Lacunarity ("Lacunarity", Float) = 2
        _Gain ("Gain", Range(0, 1)) = 0.5
        _Cover ("Cloud Cover", Range(0, 1)) = 0.5
        _Softness ("Edge Softness", Range(0.01, 1)) = 0.35
        _Wind ("Wind (xy) units/s", Vector) = (0.05, 0.01, 0, 0)
        _Offset ("Offset (for stills)", Vector) = (0, 0, 0, 0)
        _SkyTop ("Sky Top", Color) = (0.16, 0.38, 0.72, 1)
        _SkyBottom ("Sky Bottom", Color) = (0.55, 0.72, 0.90, 1)
        _CloudLit ("Cloud Lit", Color) = (1, 1, 1, 1)
        _CloudShade ("Cloud Shade", Color) = (0.62, 0.66, 0.74, 1)
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex ProceduralVert
            #pragma fragment frag
            #include "Assets/Cookbook/Ch04/ProceduralCommon.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float  _Octaves, _Scale, _Lacunarity, _Gain, _Cover, _Softness;
                float4 _Wind, _Offset;
                half4  _SkyTop, _SkyBottom, _CloudLit, _CloudShade;
            CBUFFER_END

            half4 frag (Varyings input) : SV_Target
            {
                float2 p = input.uv * _Scale + _Offset.xy + _Wind.xy * _Time.y;
                int oct = (int)_Octaves;
                //#region clouds
                float n = Fbm(p, oct, _Lacunarity, _Gain) * 0.5 + 0.5;          // → [0,1]
                // 覆盖率：把阈值往下推，云就变多；smoothstep 的宽度决定边缘软硬
                float density = smoothstep(1.0 - _Cover, 1.0 - _Cover + _Softness, n);
                // 简单的“自阴影”：朝光源方向（左上）偏移一点再采一次，差值当作明暗
                float n2 = Fbm(p + float2(-0.06, 0.06), oct, _Lacunarity, _Gain) * 0.5 + 0.5;
                float lit = saturate(0.5 + (n - n2) * 6.0);
                //#endregion
                half3 sky = lerp(_SkyBottom.rgb, _SkyTop.rgb, input.uv.y);
                half3 cloud = lerp(_CloudShade.rgb, _CloudLit.rgb, lit);
                return half4(lerp(sky, cloud, density), 1);
            }
            ENDHLSL
        }
    }
}
