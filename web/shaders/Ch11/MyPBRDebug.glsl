// MyPBR 的调试视图：把 BRDF 的每一项、光照的每一部分单独输出，用来验证实现和写书配图。（GLSL 版，对应 Ch11/MyPBRDebug.shader）
// 与 MyPBR 共用全部 GLSL，只换了片元函数。_View 用 uniform 分支（不产生变体），调试用足够了。
Shader "Cookbook/Ch11/MyPBRDebug"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        #include "Ch11/MyPBR_Input.glsl"
        uniform float _View;   // 调试专用，故意放在 CBUFFER 外（这个 Shader 不追求 SRP Batcher 兼容）
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            GLSLPROGRAM
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local_fragment _MASKMAP
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _DFG_LUT
            #include "Ch11/MyPBR_ForwardPass.glsl"

            #ifdef VERTEX
            void main() { MyPBRVert(); }
            #endif

            #ifdef FRAGMENT
            //#region debug_frag
            vec4 DebugFrag()
            {
                MySurface s  = MySampleSurface(uv);
                InputData id = MyInitInputData(s.normalTS);
                MyMaterial m = MyInitMaterial(s.albedo, s.metallic, s.perceptualRoughness);
                int view = int(_View);

                // 1~3：只看主光方向上的单项，便于和第 9 章的公式图对照
                if (view >= 1 && view <= 3)
                {
                    Light L = GetMainLight();
                    vec3 N = id.normalWS, V = id.viewDirectionWS, H = SafeNormalize(L.direction + V);
                    float NoV = abs(dot(N, V)) + 1e-5, NoL = saturate(dot(N, L.direction));
                    float NoH = saturate(dot(N, H)), LoH = saturate(dot(L.direction, H));
                    float lit = NoL > 0.0 ? 1.0 : 0.0;
                    if (view == 1)   // 归一化的 D：除以峰值 1/(π α²)，范围 0~1
                        return vec4(MyD_GGX(NoH, m.a2) * PI * m.a2 * lit);
                    if (view == 2)   // G2 = V * 4 NoL NoV，范围 0~1
                        return vec4(MyV_SmithGGXCorrelated(NoV, NoL, m.a2) * 4.0 * NoL * NoV);
                    return vec4(MyF_Schlick(m.f0, 1.0, LoH) * lit, 1.0);
                }

                MyLightingTerms t = MyComputeLighting(s, m, id);
                vec3 c;
                switch (view)
                {
                    case 4:  c = t.directSpecular; break;
                    case 5:  c = t.directDiffuse; break;
                    case 6:  c = t.indirectDiffuse; break;
                    case 7:  c = t.indirectSpecular; break;
                    case 8:  c = t.directDiffuse + t.directSpecular; break;
                    case 9:  c = t.indirectDiffuse + t.indirectSpecular; break;
                    case 10: c = MySamplePrefilteredEnv(reflect(-id.viewDirectionWS, id.normalWS), m.perceptualRoughness,
                                                        id.positionWS, id.normalizedScreenSpaceUV); break;
                    case 11:
                    {
                        float NoV = saturate(dot(id.normalWS, id.viewDirectionWS));
                        vec2 dfg = MyEnvDFG(NoV, m.perceptualRoughness);
                        c = m.f0 * dfg.x + dfg.y; break;
                    }
                    default: c = t.directDiffuse + t.directSpecular + t.indirectDiffuse + t.indirectSpecular + t.emission; break;
                }
                return vec4(c, 1.0);
            }
            //#endregion

            void main() { fragColor = DebugFrag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            GLSLPROGRAM
            #include "Ch11/MyPBR_DepthPasses.glsl"
            #ifdef VERTEX
            void main() { MyShadowVert(); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = MyShadowFrag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #include "Ch11/MyPBR_DepthPasses.glsl"
            #ifdef VERTEX
            void main() { MyDepthVert(); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = MyDepthFrag(); }
            #endif
            ENDGLSL
        }
    }
}
