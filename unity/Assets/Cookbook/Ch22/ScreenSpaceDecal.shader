// 案例 22.4–22.7：自写屏幕空间贴花——画一个单位立方体，用深度重建世界坐标，投到盒子本地空间做 UV
// 约定与 URP Decal Projector 相同：沿物体 +Z 方向投影，盒子是 [-0.5, 0.5]³
Shader "Cookbook/Ch22/ScreenSpaceDecal"
{
    Properties
    {
        [MainTexture] _BaseMap ("Decal (RGBA)", 2D) = "white" {}
        [MainColor] _BaseColor ("Color", Color) = (1,1,1,1)
        [Toggle(_NORMALMAP)] _UseNormal ("Use Normal Map", Float) = 0
        [NoScaleOffset][Normal] _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Scale", Range(0, 2)) = 1
        _Smoothness ("Smoothness", Range(0, 1)) = 0.3
        [Toggle(_DECAL_LIT)] _Lit ("Lit", Float) = 1
        _AngleStart ("Angle Fade Start (deg)", Range(0, 90)) = 50
        _AngleEnd ("Angle Fade End (deg)", Range(0, 90)) = 75
        _DepthFade ("Box Depth Fade", Range(0.001, 0.5)) = 0.1
        [Enum(UnityEngine.Rendering.BlendMode)] _SrcBlend ("Src Blend", Float) = 5
        [Enum(UnityEngine.Rendering.BlendMode)] _DstBlend ("Dst Blend", Float) = 10
        [Toggle] _Modulate ("Modulate (for Multiply)", Float) = 0
        [Enum(Final,0,Coverage,1,ObjectPos,2,Normal,3)] _Debug ("Debug View", Float) = 0
    }
    SubShader
    {
        // 在不透明物体之后、普通透明物体之前画：此时 _CameraDepthTexture 已经可用
        Tags { "RenderType"="Transparent" "RenderPipeline"="UniversalPipeline" "Queue"="Transparent-100" "IgnoreProjector"="True" "DisableBatching"="True" }

        Pass
        {
            Name "ScreenSpaceDecal"
            Tags { "LightMode"="UniversalForward" }
            //#region state
            Cull Front        // 画盒子的“背面”：相机钻进盒子里也不会丢
            ZTest Greater     // 背面比场景表面“更远”才通过 = 场景表面在盒子里（或盒子前方）
            ZWrite Off
            Blend [_SrcBlend] [_DstBlend]
            //#endregion

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _NORMALMAP
            #pragma shader_feature_local_fragment _DECAL_LIT
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                half4 _BaseColor;
                half _BumpScale, _Smoothness;
                float _AngleStart, _AngleEnd, _DepthFade;
                half _Modulate, _Debug;
            CBUFFER_END
            TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);

            struct Attributes { float4 positionOS : POSITION; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings  { float4 positionCS : SV_POSITION; UNITY_VERTEX_INPUT_INSTANCE_ID };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                if (_Debug > 0.5 && _Debug < 1.5) return half4(1.0, 0.35, 0.1, 0.6);   // 盒子覆盖到的像素

                //#region reconstruct
                // 1) 屏幕 UV → 场景深度 → 世界坐标
                float2 screenUV = GetNormalizedScreenSpaceUV(i.positionCS);
                float rawDepth = SampleSceneDepth(screenUV);
            #if !UNITY_REVERSED_Z
                rawDepth = lerp(UNITY_NEAR_CLIP_VALUE, 1, rawDepth);   // OpenGL 类平台：[0,1] → [-1,1]
            #endif
                float3 positionWS = ComputeWorldSpacePosition(screenUV, rawDepth, UNITY_MATRIX_I_VP);

                // 2) 世界坐标 → 贴花盒子的本地空间；盒子外的像素直接丢掉
                float3 positionOS = TransformWorldToObject(positionWS);
                clip(0.5 - abs(positionOS));
                //#endregion

                if (_Debug > 1.5 && _Debug < 2.5) return half4(positionOS + 0.5, 1);

                //#region normalFade
                // 3) 用屏幕空间导数重建表面法线（平面法线，物体轮廓处会有噪点）
                float3 normalWS = normalize(cross(ddx(positionWS), ddy(positionWS)));
                normalWS *= sign(dot(normalWS, GetWorldSpaceViewDir(positionWS)));   // 统一朝向相机，免去平台 Y 方向差异

                // 4) 角度衰减：表面越“侧”对投影方向，贴花越淡，避免在侧壁上拉出长条
                float3 projDirWS = normalize(TransformObjectToWorldDir(float3(0, 0, 1)));
                float facing = dot(normalWS, -projDirWS);                            // 1 = 正对投影器
                float cosStart = cos(radians(_AngleStart)), cosEnd = cos(radians(_AngleEnd));
                half angleFade = saturate((facing - cosEnd) / max(cosStart - cosEnd, 1e-4));
                // 盒子前后两端也淡出，贴花不会在投影深度的尽头被一刀切断
                half depthFade = saturate((0.5 - abs(positionOS.z)) / _DepthFade);
                //#endregion

                if (_Debug > 2.5) return half4(normalWS * 0.5 + 0.5, 1);

                //#region shade
                float2 boxUV = positionOS.xy + 0.5;              // 盒子本地 xy → 0..1 的贴花 UV
                float2 uv = TRANSFORM_TEX(boxUV, _BaseMap);
                half4 decal = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv) * _BaseColor;
                half alpha = decal.a * angleFade * depthFade;

                half3 color = decal.rgb;
            #if defined(_DECAL_LIT)
                half3 n = normalWS;
                #if defined(_NORMALMAP)
                    // 贴花自己的法线贴图：切线空间就是投影器的 X/Y 轴，“上”是 -投影方向
                    half3 nTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uv), _BumpScale);
                    float3 T = normalize(TransformObjectToWorldDir(float3(1, 0, 0)));
                    float3 B = normalize(TransformObjectToWorldDir(float3(0, 1, 0)));
                    // 把法线贴图的扰动量（xy）叠加到重建的表面法线上（UDN 式混合）
                    n = normalize(n + (T * nTS.x + B * nTS.y) * decal.a);
                #endif
                InputData inputData = (InputData)0;
                inputData.positionWS = positionWS;
                inputData.normalWS = n;
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(positionWS);
                inputData.shadowCoord = TransformWorldToShadowCoord(positionWS);
                inputData.bakedGI = SampleSH(n);
                inputData.normalizedScreenSpaceUV = screenUV;
                inputData.shadowMask = half4(1, 1, 1, 1);
                SurfaceData surface = (SurfaceData)0;
                surface.albedo = decal.rgb;
                surface.smoothness = _Smoothness;
                surface.occlusion = 1;
                surface.alpha = alpha;
                color = UniversalFragmentPBR(inputData, surface).rgb;
            #endif
                // 正片叠底模式：alpha 折算进颜色（透明处 = 白 = 不改变背景）
                color = lerp(color, lerp(1.0, decal.rgb, alpha), _Modulate);
                return half4(color, alpha);
                //#endregion
            }
            ENDHLSL
        }
    }
}
