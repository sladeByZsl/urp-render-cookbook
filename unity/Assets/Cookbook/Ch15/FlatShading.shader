// 低多边形（Low Poly）flat shading：不改网格，在片元里用 ddx/ddy 求三角形的面法线。
// 演示场景是一块在顶点着色器里用噪声抬高的地形，可以在“平滑法线 / 面法线”之间切换。
Shader "Cookbook/Ch15/FlatShading"
{
    Properties
    {
        _BaseColor ("Base Color (non-terrain)", Color) = (0.9, 0.55, 0.3, 1)
        [Toggle] _Flat ("Flat Shading (ddx/ddy)", Float) = 1
        [Toggle] _Terrain ("Terrain Mode", Float) = 0
        [NoScaleOffset] _HeightTex ("Height Noise", 2D) = "gray" {}
        _HeightScale ("Height", Range(0, 4)) = 1.6
        _NoiseTiling ("Noise Tiling", Float) = 0.08
        _WaterLevel ("Water Level", Float) = -0.6
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            half4 _BaseColor;
            float _Flat, _Terrain, _HeightScale, _NoiseTiling, _WaterLevel;
        CBUFFER_END
        TEXTURE2D(_HeightTex); SAMPLER(sampler_HeightTex);

        // 地形高度：世界 xz 采样噪声。顶点着色器里必须用 LOD 版本采样（没有导数可用）
        float TerrainHeight(float2 xz)
        {
            float h = SAMPLE_TEXTURE2D_LOD(_HeightTex, sampler_HeightTex, xz * _NoiseTiling, 0).r;
            h = (h - 0.45) * _HeightScale * 2.0;
            return max(h, _WaterLevel);     // 低于水位的部分压平成水面
        }

        // 所有 Pass 共用的顶点变形：地形模式下抬高顶点，并用有限差分算出平滑法线
        void Deform(inout float3 positionWS, inout float3 normalWS)
        {
            if (_Terrain < 0.5) return;
            const float e = 0.05;
            float h  = TerrainHeight(positionWS.xz);
            float hx = TerrainHeight(positionWS.xz + float2(e, 0));
            float hz = TerrainHeight(positionWS.xz + float2(0, e));
            positionWS.y += h;
            normalWS = normalize(float3(h - hx, e, h - hz));
        }
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #include "Assets/Cookbook/Ch15/NPRCommon.hlsl"

            NprVaryings vert(NprAttributes v)
            {
                NprVaryings o;
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                Deform(positionWS, normalWS);
                o.positionWS = positionWS;
                o.normalWS = normalWS;
                o.positionCS = TransformWorldToHClip(positionWS);
                o.uv = v.uv; o.color = v.color; o.fogFactor = 0;
                return o;
            }

            //#region facenormal
            float3 FaceNormal(float3 positionWS)
            {
                // ddx/ddy：相邻像素之间世界坐标的差，两者都躺在三角形平面内，叉乘就是面法线。
                // 同一个 2×2 像素块里共享导数，而三角形内部世界坐标是线性的，所以结果是“整面常量”。
                float3 n = normalize(cross(ddy(positionWS), ddx(positionWS)));
                // 屏幕 y 轴朝上还是朝下因平台/是否渲染到 RT 而异，叉乘方向可能反过来；
                // 正面一定朝向相机，所以用视线方向把它翻正，最省心
                float3 V = _WorldSpaceCameraPos - positionWS;
                return dot(n, V) < 0 ? -n : n;
            }
            //#endregion

            half3 TerrainColor(float y, float3 N)
            {
                half3 c = half3(0.10, 0.32, 0.62);                                         // 水
                c = lerp(c, half3(0.80, 0.68, 0.42), step(_WaterLevel + 0.02, y));         // 沙
                c = lerp(c, half3(0.30, 0.55, 0.18), step(_WaterLevel + 0.25, y));         // 草
                c = lerp(c, half3(0.42, 0.37, 0.33), step(0.3, y) * step(N.y, 0.9));      // 陡坡变岩石
                c = lerp(c, half3(0.92, 0.93, 0.96), step(1.3, y));                        // 雪
                // 上面这些常量是按“显示器上看到的颜色”（sRGB）挑的，线性空间工程里要先转成线性值
                return SRGBToLinear(c);
            }

            half4 frag(NprVaryings i) : SV_Target
            {
                float3 N = _Flat > 0.5 ? FaceNormal(i.positionWS) : normalize(i.normalWS);
                NprLight L = GetNprLight(i.positionWS, N);
                half3 albedo = _Terrain > 0.5 ? TerrainColor(i.positionWS.y, N) : _BaseColor.rgb;
                half3 col = albedo * (saturate(L.ndotl) * L.shadow * L.color + SampleSH(N));
                return half4(col, 1);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment NprNullFrag
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch15/NPRCommon.hlsl"
            float4 vert(NprShadowAttributes v) : SV_POSITION
            {
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                Deform(positionWS, normalWS);   // 阴影要和颜色 Pass 用同样的变形
                float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, _LightDirection));
            #if UNITY_REVERSED_Z
                positionCS.z = min(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #else
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE);
            #endif
                return positionCS;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment NprNullFrag
            #include "Assets/Cookbook/Ch15/NPRCommon.hlsl"
            float4 vert(NprShadowAttributes v) : SV_POSITION
            {
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                Deform(positionWS, normalWS);
                return TransformWorldToHClip(positionWS);
            }
            ENDHLSL
        }
    }
}
