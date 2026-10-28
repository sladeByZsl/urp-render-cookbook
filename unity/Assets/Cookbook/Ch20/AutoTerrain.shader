// 案例 20.4：按高度/坡度自动混合多层地表（草 → 砂石 → 岩石 → 雪），层间用高度混合
Shader "Cookbook/Ch20/AutoTerrain"
{
    Properties
    {
        [NoScaleOffset] _GrassTex ("Grass (A=Height)", 2D) = "white" {}
        [NoScaleOffset] _SandTex ("Sand (A=Height)", 2D) = "white" {}
        [NoScaleOffset] _RockTex ("Rock (A=Height)", 2D) = "white" {}
        [NoScaleOffset][Normal] _RockNormal ("Rock Normal", 2D) = "bump" {}
        [NoScaleOffset] _SnowTex ("Snow (A=Height)", 2D) = "white" {}
        [NoScaleOffset] _NoiseTex ("Breakup Noise", 2D) = "gray" {}
        _Tiling ("Ground Tiling (1/m)", Float) = 0.35
        _RockTiling ("Rock Tiling (1/m)", Float) = 0.2
        _SandHeight ("Sand Below Height", Float) = -0.6
        _SnowHeight ("Snow Above Height", Float) = 7
        _HeightBand ("Height Transition (m)", Float) = 0.6
        _RockSlope ("Rock Slope (1-N.y)", Range(0, 1)) = 0.3
        _SlopeBand ("Slope Transition", Range(0.001, 0.5)) = 0.08
        _NoiseAmp ("Noise Amount", Float) = 1.5
        _BlendDepth ("Height Blend Depth", Range(0.01, 1)) = 0.15
        [Toggle(_DEBUG_WEIGHTS)] _DebugWeights ("Debug Weights", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        CBUFFER_START(UnityPerMaterial)
            float _Tiling, _RockTiling;
            float _SandHeight, _SnowHeight, _HeightBand;
            half _RockSlope, _SlopeBand, _NoiseAmp, _BlendDepth;
        CBUFFER_END
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }   // 自定义表面混合，没有 GBuffer Pass：Deferred 下也走前向
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma shader_feature_local_fragment _DEBUG_WEIGHTS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Assets/Cookbook/Ch20/TerrainCommon.hlsl"

            // 多张图共用一个采样器：移动端采样器数量有限（常见上限 16 个），地形 Shader 尤其要省
            TEXTURE2D(_GrassTex); SAMPLER(sampler_GrassTex);
            TEXTURE2D(_SandTex);
            TEXTURE2D(_RockTex);
            TEXTURE2D(_RockNormal);
            TEXTURE2D(_SnowTex);
            TEXTURE2D(_NoiseTex); SAMPLER(sampler_NoiseTex);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                half3  normalWS   : TEXCOORD1;
                half   fogFactor  : TEXCOORD2;
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                VertexPositionInputs p = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = p.positionCS;
                o.positionWS = p.positionWS;
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                o.fogFactor = ComputeFogFactor(p.positionCS.z);
                return o;
            }

            //#region rules
            half4 frag(Varyings i) : SV_Target
            {
                half3 n = normalize(i.normalWS);
                float3 pos = i.positionWS;

                // 低频噪声：打破“等高线”一样整齐的分界
                half noise = SAMPLE_TEXTURE2D(_NoiseTex, sampler_NoiseTex, pos.xz * 0.04).r - 0.5;
                half h = pos.y + noise * _NoiseAmp;
                half slope = 1.0 - n.y;                          // 0 = 平地，1 = 垂直崖壁

                // 平缓的层用顶视投影即可；岩石主要出现在陡坡，必须 Triplanar
                float2 uvTop = pos.xz * _Tiling;
                half4 grass = SAMPLE_TEXTURE2D(_GrassTex, sampler_GrassTex, uvTop);
                half4 sand  = SAMPLE_TEXTURE2D(_SandTex,  sampler_GrassTex, uvTop * 1.3);
                half4 snow  = SAMPLE_TEXTURE2D(_SnowTex,  sampler_GrassTex, uvTop * 0.5);
                float3 tw = TriplanarWeights(n, 8);
                TriplanarUV tuv = GetTriplanarUV(pos, n, _RockTiling);
                half4 rock = SampleTriplanar(TEXTURE2D_ARGS(_RockTex, sampler_GrassTex), tuv, tw);
                half3 rockN = TriplanarNormalWS(TEXTURE2D_ARGS(_RockNormal, sampler_GrassTex), tuv, tw, n, 1, 3);

                // 规则 → 遮罩（0..1）
                half sandMask = 1.0 - smoothstep(_SandHeight - _HeightBand, _SandHeight + _HeightBand, h);
                half rockMask = smoothstep(_RockSlope - _SlopeBand, _RockSlope + _SlopeBand, slope + noise * 0.25);
                //#endregion

                //#region stack
                // 按“从下往上铺”的顺序逐层叠：每层都和“已经铺好的结果”做一次高度混合
                half4 c = grass;
                half3 nrm = n;
                half4 layerW = half4(1, 0, 0, 0);               // 记录各层最终占比：草/砂/岩/雪（调试用）

                half t = HeightBlendWeight(c.a, sand.a, sandMask, _BlendDepth);
                c = lerp(c, sand, t);               layerW = half4(layerW.xyz * (1 - t), 0); layerW.y += t;

                t = HeightBlendWeight(c.a, rock.a, rockMask, _BlendDepth);
                c = lerp(c, rock, t);               nrm = normalize(lerp(nrm, rockN, t));
                layerW.xyz *= (1 - t);              layerW.z += t;

                // 雪：高于雪线，并且“细节法线”朝上的地方才积得住——岩石的凹坑与台面先白
                half snowSlope = 1.0 - nrm.y;
                half snowMask = smoothstep(_SnowHeight - _HeightBand, _SnowHeight + _HeightBand, h)
                              * (1.0 - smoothstep(0.35, 0.65, snowSlope));
                t = HeightBlendWeight(c.a, snow.a, snowMask, _BlendDepth);
                c = lerp(c, snow, t);               nrm = normalize(lerp(nrm, n, t * 0.6));
                layerW *= (1 - t);                  layerW.w += t;
                //#endregion

            #if defined(_DEBUG_WEIGHTS)
                half3 dbg = layerW.x * half3(0.2, 0.7, 0.15) + layerW.y * half3(0.95, 0.75, 0.2)
                          + layerW.z * half3(0.75, 0.25, 0.2) + layerW.w * half3(1, 1, 1);
                return half4(dbg * (0.55 + 0.45 * saturate(dot(n, half3(0.3, 0.9, -0.3)))), 1);
            #endif
                half smoothness = dot(layerW, half4(0.12, 0.18, 0.28, 0.5));
                return Ch20ShadePBR(pos, nrm, i.positionCS, c.rgb, 0, smoothness, 1, i.fogFactor);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            HLSLPROGRAM
            #pragma vertex Ch20ShadowVert
            #pragma fragment Ch20EmptyFrag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Assets/Cookbook/Ch20/ShadowDepthPasses.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            HLSLPROGRAM
            #pragma vertex Ch20DepthVert
            #pragma fragment Ch20EmptyFrag
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch20/ShadowDepthPasses.hlsl"
            ENDHLSL
        }
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On
            HLSLPROGRAM
            #pragma vertex Ch20DepthVert
            #pragma fragment Ch20DepthNormalsFrag
            #pragma multi_compile_instancing
            #include "Assets/Cookbook/Ch20/ShadowDepthPasses.hlsl"
            ENDHLSL
        }
    }
}
