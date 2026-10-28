// 案例 20.4：按高度/坡度自动混合多层地表（草 → 砂石 → 岩石 → 雪），层间用高度混合（GLSL 版，对应 Ch20/AutoTerrain.shader）
Shader "Cookbook/Ch20/AutoTerrain"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform float _Tiling, _RockTiling;
        uniform float _SandHeight, _SnowHeight, _HeightBand;
        uniform float _RockSlope, _SlopeBand, _NoiseAmp, _BlendDepth;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }   // 自定义表面混合，没有 GBuffer Pass：Deferred 下也走前向
            GLSLPROGRAM
            #pragma shader_feature_local_fragment _DEBUG_WEIGHTS
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Ch20/TerrainCommon.glsl"

            // HLSL 版多张图共用一个采样器（移动端采样器数量有限，常见上限 16 个，地形 Shader 尤其要省）。
            // GLSL 没有“贴图/采样器分离”，每个 sampler2D 自带采样状态，这里照常各声明一个
            uniform sampler2D _GrassTex;
            uniform sampler2D _SandTex;
            uniform sampler2D _RockTex;
            uniform sampler2D _RockNormal;
            uniform sampler2D _SnowTex;
            uniform sampler2D _NoiseTex;

            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING float fogFactor;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs p = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = p.positionCS;
                positionWS = p.positionWS;
                normalWS = TransformObjectToWorldNormal(normalOS);
                fogFactor = ComputeFogFactor(p.positionCS.z);
            }
            #endif

            #ifdef FRAGMENT
            //#region rules
            vec4 frag()
            {
                vec3 n = normalize(normalWS);
                vec3 pos = positionWS;

                // 低频噪声：打破“等高线”一样整齐的分界
                float noise = texture(_NoiseTex, pos.xz * 0.04).r - 0.5;
                float h = pos.y + noise * _NoiseAmp;
                float slope = 1.0 - n.y;                          // 0 = 平地，1 = 垂直崖壁

                // 平缓的层用顶视投影即可；岩石主要出现在陡坡，必须 Triplanar
                vec2 uvTop = pos.xz * _Tiling;
                vec4 grass = texture(_GrassTex, uvTop);
                vec4 sand  = texture(_SandTex,  uvTop * 1.3);
                vec4 snow  = texture(_SnowTex,  uvTop * 0.5);
                vec3 tw = TriplanarWeights(n, 8.0);
                TriplanarUV tuv = GetTriplanarUV(pos, n, _RockTiling);
                vec4 rock = SampleTriplanar(_RockTex, tuv, tw);
                vec3 rockN = TriplanarNormalWS(_RockNormal, tuv, tw, n, 1.0, 3);

                // 规则 → 遮罩（0..1）
                float sandMask = 1.0 - smoothstep(_SandHeight - _HeightBand, _SandHeight + _HeightBand, h);
                float rockMask = smoothstep(_RockSlope - _SlopeBand, _RockSlope + _SlopeBand, slope + noise * 0.25);
                //#endregion

                //#region stack
                // 按“从下往上铺”的顺序逐层叠：每层都和“已经铺好的结果”做一次高度混合
                vec4 c = grass;
                vec3 nrm = n;
                vec4 layerW = vec4(1, 0, 0, 0);               // 记录各层最终占比：草/砂/岩/雪（调试用）

                float t = HeightBlendWeight(c.a, sand.a, sandMask, _BlendDepth);
                c = mix(c, sand, t);                layerW = vec4(layerW.xyz * (1.0 - t), 0.0); layerW.y += t;

                t = HeightBlendWeight(c.a, rock.a, rockMask, _BlendDepth);
                c = mix(c, rock, t);                nrm = normalize(mix(nrm, rockN, t));
                layerW.xyz *= (1.0 - t);            layerW.z += t;

                // 雪：高于雪线，并且“细节法线”朝上的地方才积得住——岩石的凹坑与台面先白
                float snowSlope = 1.0 - nrm.y;
                float snowMask = smoothstep(_SnowHeight - _HeightBand, _SnowHeight + _HeightBand, h)
                               * (1.0 - smoothstep(0.35, 0.65, snowSlope));
                t = HeightBlendWeight(c.a, snow.a, snowMask, _BlendDepth);
                c = mix(c, snow, t);                nrm = normalize(mix(nrm, n, t * 0.6));
                layerW *= (1.0 - t);                layerW.w += t;
                //#endregion

            #if defined(_DEBUG_WEIGHTS)
                vec3 dbg = layerW.x * vec3(0.2, 0.7, 0.15) + layerW.y * vec3(0.95, 0.75, 0.2)
                         + layerW.z * vec3(0.75, 0.25, 0.2) + layerW.w * vec3(1, 1, 1);
                return vec4(dbg * (0.55 + 0.45 * saturate(dot(n, vec3(0.3, 0.9, -0.3)))), 1.0);
            #endif
                float smoothness = dot(layerW, vec4(0.12, 0.18, 0.28, 0.5));
                return Ch20ShadePBR(pos, nrm, gl_FragCoord, c.rgb, 0.0, smoothness, 1.0, fogFactor);
            }
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #define CH20_SHADOW_PASS
            #include "Ch20/ShadowDepthPasses.glsl"
            ENDGLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #pragma multi_compile_instancing
            #define CH20_DEPTH_PASS
            #include "Ch20/ShadowDepthPasses.glsl"
            ENDGLSL
        }
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On
            GLSLPROGRAM
            #pragma multi_compile_instancing
            #define CH20_DEPTHNORMALS_PASS
            #include "Ch20/ShadowDepthPasses.glsl"
            ENDGLSL
        }
    }
}
