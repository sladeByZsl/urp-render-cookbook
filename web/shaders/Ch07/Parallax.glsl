// 视差映射对比：None（只有法线贴图）/ Simple（URP 自带的单步偏移）/ Steep / POM，外加可选的视差自阴影。（GLSL 版，对应 Ch07/Parallax.shader）
Shader "Cookbook/Ch07/Parallax"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _BaseMap_ST;
        uniform float _BumpScale;
        uniform float _Parallax;
        uniform float _MinLayers;
        uniform float _MaxLayers;
        uniform float _ShadowSteps;
        uniform float _ShadowSoftness;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            #pragma shader_feature_local _MODE_NONE _MODE_SIMPLE _MODE_STEEP _MODE_POM
            #pragma shader_feature_local _PARALLAX_SHADOW
            #include "Ch07/Ch07Common.glsl"

            uniform sampler2D _BaseMap;
            uniform sampler2D _BumpMap;
            uniform sampler2D _ParallaxMap;

            VARYING vec2 uv0;
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING vec4 tangentWS;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs pos = GetVertexPositionInputs(positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(normalOS, tangentOS);
                gl_Position = pos.positionCS;
                positionWS = pos.positionWS;
                uv0 = TransformTex(texcoord0.xy, _BaseMap_ST);
                normalWS = nrm.normalWS;
                tangentWS = vec4(nrm.tangentWS, tangentOS.w * GetOddNegativeScale());
            }
            #endif

            #ifdef FRAGMENT
            // ======== 以下是 Ch07/Parallax.hlsl 的 GLSL 版 ========
            // （Parallax.shader 与 Parallax.hlsl 换成 .glsl 后同名，所以把这个 include 文件的内容直接放进本文件；
            //   其中用到 dFdx/dFdy，只能放在片元着色器里。另附 URP core 的 ParallaxMapping.hlsl 里用到的两个函数）
            // 视差映射三件套：Steep Parallax、Parallax Occlusion Mapping（POM）、视差自阴影。（GLSL 版，对应 Ch07/Parallax.hlsl）
            // 约定：高度图 1 = 表面最高处（与多边形平面重合），0 = 最深处；depth = 1 - height。
            // viewDirTS / lightDirTS 都是“从表面指向外”的切线空间单位向量（z > 0 表示在表面上方）。
            // 另外附上 URP core 的 ParallaxMapping.hlsl 里用到的两个函数（GLSL 版没有这个库）。

            #define CH07_MAX_STEPS 64   // 循环上限，防止极端掠射角时步数失控

            // 循环里不能用普通的 texture()：隐式求导在动态分支/循环中无定义，
            // 所以先在循环外算好 dFdx/dFdy，循环里用 textureGrad（HLSL 的 SAMPLE_TEXTURE2D_GRAD）。
            #define CH07_DEPTH(uv) (1.0 - textureGrad(heightMap, uv, dx, dy).r)

            // ---- URP ParallaxMapping.hlsl ----
            // 要求传入“插值后未归一化”的 N/T：三根轴用同一个缩放因子，保持与 MikkTSpace 一致
            vec3 GetViewDirectionTangentSpace(vec4 tangentWS, vec3 normalWS, vec3 viewDirWS)
            {
                vec3 unnormalizedNormalWS = normalWS;
                float renormFactor = 1.0 / length(unnormalizedNormalWS);
                float crossSign = (tangentWS.w > 0.0 ? 1.0 : -1.0);
                vec3 bitang = crossSign * cross(normalWS.xyz, tangentWS.xyz);
                vec3 WorldSpaceNormal = renormFactor * normalWS.xyz;
                vec3 WorldSpaceTangent = renormFactor * tangentWS.xyz;
                vec3 WorldSpaceBiTangent = renormFactor * bitang;
                // HLSL：mul(half3x3(T, B, N), viewDirWS) = (T·v, B·v, N·v)
                return viewDirWS * mat3(WorldSpaceTangent, WorldSpaceBiTangent, WorldSpaceNormal);
            }

            vec2 ParallaxOffset1Step(float height, float amplitude, vec3 viewDirTS)
            {
                height = height * amplitude - amplitude / 2.0;
                vec3 v = normalize(viewDirTS);
                v.z += 0.42;
                return height * (v.xy / v.z);
            }

            vec2 ParallaxMapping(sampler2D heightMap, vec3 viewDirTS, float scale, vec2 uv)
            {
                float h = texture(heightMap, uv).g;
                return ParallaxOffset1Step(h, scale, viewDirTS);
            }

            //#region steep
            // 陡峭视差（Steep Parallax）：把 [0,1] 深度切成 numLayers 层，沿视线一层层往里走，
            // 直到“视线深度”第一次超过“高度图深度”。返回命中点 UV；hitDepth 输出命中深度。
            vec2 SteepParallax(sampler2D heightMap, vec2 uv, vec3 viewDirTS,
                               float scale, float minLayers, float maxLayers, out float hitDepth)
            {
                vec2 dx = dFdx(uv), dy = dFdy(uv);
                // 正视时层数少，掠射时层数多：掠射时每层在 UV 上走得更远，需要更细的步长
                float numLayers = mix(maxLayers, minLayers, saturate(viewDirTS.z));
                float layerDepth = 1.0 / numLayers;
                // 视线每深入 1 个单位，UV 偏移 V.xy / V.z * scale（相似三角形）；方向与视线相反
                vec2 deltaUV = viewDirTS.xy / max(viewDirTS.z, 0.05) * scale / numLayers;

                float rayDepth = 0.0;
                float mapDepth = CH07_DEPTH(uv);
                for (int i = 0; i < CH07_MAX_STEPS && rayDepth < mapDepth; i++)
                {
                    uv -= deltaUV;
                    mapDepth = CH07_DEPTH(uv);
                    rayDepth += layerDepth;
                }
                hitDepth = rayDepth;
                return uv;
            }
            //#endregion

            //#region pom
            // 视差遮挡映射（POM）：在 Steep 的基础上，对“穿过表面前后”的两层做一次线性插值，
            // 把台阶状的命中点修正到两层之间，低层数也能得到平滑结果。
            vec2 ParallaxOcclusion(sampler2D heightMap, vec2 uv, vec3 viewDirTS,
                                   float scale, float minLayers, float maxLayers, out float hitDepth)
            {
                vec2 dx = dFdx(uv), dy = dFdy(uv);
                float numLayers = mix(maxLayers, minLayers, saturate(viewDirTS.z));
                float layerDepth = 1.0 / numLayers;
                vec2 deltaUV = viewDirTS.xy / max(viewDirTS.z, 0.05) * scale / numLayers;

                float rayDepth = 0.0;
                float mapDepth = CH07_DEPTH(uv);
                for (int i = 0; i < CH07_MAX_STEPS && rayDepth < mapDepth; i++)
                {
                    uv -= deltaUV;
                    mapDepth = CH07_DEPTH(uv);
                    rayDepth += layerDepth;
                }

                // 穿透后（after）与穿透前（before）两层，各自“视线深度 - 高度图深度”的差
                vec2 prevUV = uv + deltaUV;
                float after  = mapDepth - rayDepth;                              // ≤ 0
                float before = CH07_DEPTH(prevUV) - (rayDepth - layerDepth);     // ≥ 0
                float w = after / (after - before + 1e-5);                       // 两段直线的交点比例
                hitDepth = mix(rayDepth, rayDepth - layerDepth, w);
                return mix(uv, prevUV, w);
            }
            //#endregion

            //#region shadow
            // 视差自阴影：从命中点朝灯光方向往上走，检查途中有没有更高的凸起挡住光。
            // 返回 1 = 不在阴影里，0 = 完全遮挡。用“挡了多少 × 离起点多近”做软化。
            // dx/dy 传入原始 UV 的导数：偏移后的 UV 在台阶边缘不连续，用它求导会选错 mip。
            float ParallaxSelfShadow(sampler2D heightMap, vec2 uv, vec2 dx, vec2 dy,
                                     float hitDepth, vec3 lightDirTS, float scale, float steps, float softness)
            {
                if (lightDirTS.z <= 0.0) return 0.0;       // 灯在表面背面
                if (hitDepth <= 0.001) return 1.0;         // 已经在最高处，没有东西能挡它

                float layerDepth = hitDepth / steps;       // 只需要从命中深度走回表面
                vec2 deltaUV = lightDirTS.xy / max(lightDirTS.z, 0.05) * scale * layerDepth;

                float rayDepth = hitDepth;
                float occlusion = 0.0;
                for (int i = 1; i <= int(steps) && i <= CH07_MAX_STEPS; i++)
                {
                    uv += deltaUV;
                    rayDepth -= layerDepth;
                    float mapDepth = CH07_DEPTH(uv);
                    // mapDepth < rayDepth：这里的表面比光线还高 → 光线被挡
                    float o = (rayDepth - mapDepth) * softness * (1.0 - float(i - 1) / steps);
                    occlusion = max(occlusion, o);
                }
                return 1.0 - saturate(occlusion);
            }
            //#endregion

            // ======== Parallax.hlsl 结束 ========

            //#region frag
            void main()
            {
                vec2 uv = uv0;
                vec2 dx = dFdx(uv), dy = dFdy(uv);
                // 视线转到切线空间。URP 的 GetViewDirectionTangentSpace 要求传入“插值后未归一化”的 N/T，
                // 它内部用同一个缩放因子处理三根轴，保持与 MikkTSpace 一致。
                vec3 viewDirWS = GetWorldSpaceNormalizeViewDir(positionWS);
                vec3 viewDirTS = GetViewDirectionTangentSpace(tangentWS, normalWS, viewDirWS);
                float hitDepth = 0.0;

            #if defined(_MODE_SIMPLE)
                // URP Lit 的做法（ParallaxMapping.hlsl）：采样一次高度，沿视线偏移一步
                uv += ParallaxMapping(_ParallaxMap, viewDirTS, _Parallax, uv);
            #elif defined(_MODE_STEEP)
                uv = SteepParallax(_ParallaxMap, uv, normalize(viewDirTS), _Parallax, _MinLayers, _MaxLayers, hitDepth);
            #elif defined(_MODE_POM)
                uv = ParallaxOcclusion(_ParallaxMap, uv, normalize(viewDirTS), _Parallax, _MinLayers, _MaxLayers, hitDepth);
            #endif

                // 之后所有贴图都用偏移后的 UV 采样，并沿用原始 UV 的导数，避免台阶边缘的 mip 跳变
                vec3 albedo = textureGrad(_BaseMap, uv, dx, dy).rgb;
                vec3 normalTS = UnpackNormalScale(textureGrad(_BumpMap, uv, dx, dy), _BumpScale);
                vec3 bitangent = tangentWS.w * cross(normalWS, tangentWS.xyz);
                mat3 tbn = mat3(tangentWS.xyz, bitangent, normalWS);
                vec3 nWS = NormalizeNormalPerPixel(TransformTangentToWorld(normalTS, tbn));

                float selfShadow = 1.0;
            #if defined(_PARALLAX_SHADOW) && (defined(_MODE_STEEP) || defined(_MODE_POM))
                // 把主光方向也转到切线空间：TBN 是正交基，转置即逆。
                // HLSL 的 mul(tbn, v)（tbn 按行放 T/B/N）= (T·v, B·v, N·v)，GLSL 里写成 v * tbn（tbn 按列放）
                vec3 lightDirTS = normalize(GetMainLight().direction * tbn);
                selfShadow = ParallaxSelfShadow(_ParallaxMap, uv, dx, dy,
                                                hitDepth, lightDirTS, _Parallax, _ShadowSteps, _ShadowSoftness);
            #endif

                vec3 color = Ch07Shade(positionWS, nWS, albedo, 0.45, 0.12, selfShadow);
                fragColor = vec4(color, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #define CH07_SHADOW_PASS
            #include "Ch07/Ch07Common.glsl"
            ENDGLSL
        }
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #define CH07_DEPTH_PASS
            #include "Ch07/Ch07Common.glsl"
            ENDGLSL
        }
    }
}
