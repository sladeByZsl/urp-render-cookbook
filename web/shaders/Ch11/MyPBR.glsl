// 第 11 章最终成果：完全手写 BRDF 的 PBR Shader，可直接在项目中使用。（GLSL 版，对应 Ch11/MyPBR.shader）
// 支持：Forward / Forward+、主光与附加光阴影、SH + 反射探针 IBL、DFG（解析或 LUT）、多次散射补偿、
//       法线贴图、Mask Map（R 金属 G AO A 光滑）、自发光、SSAO、Rendering Debugger。
// （HLSL 版另外支持光照贴图、Light Layers、SRP Batcher、GPU Instancing，网页版没有这些功能）
Shader "Cookbook/Ch11/MyPBR"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        // 所有 Pass 共享同一份材质属性声明，保证 SRP Batcher 兼容
        #include "Ch11/MyPBR_Input.glsl"
        ENDGLSL

        //#region pass_forward
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            ZWrite On
            Cull Back

            GLSLPROGRAM
            // ---- 材质关键字（只编译用到的组合）----
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local_fragment _MASKMAP
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _DFG_LUT
            #pragma shader_feature_local_fragment _ALPHATEST_ON

            // ---- URP 管线关键字：_MAIN_LIGHT_SHADOWS、_ADDITIONAL_LIGHTS、_SHADOWS_SOFT 等网页版引擎始终打开 ----
            // ---- 调试：网页版模拟的 Rendering Debugger ----
            #pragma multi_compile_fragment _ DEBUG_DISPLAY

            #include "Ch11/MyPBR_ForwardPass.glsl"
            #include "Ch11/DebugDisplay.glsl"

            #ifdef VERTEX
            void main() { MyPBRVert(); }
            #endif

            #ifdef FRAGMENT
            void main()
            {
            #if defined(DEBUG_DISPLAY)
                // 让 Rendering Debugger 的材质视图 / 材质校验也能作用于 MyPBR：
                // 把我们的表面参数交给调试函数（HLSL 版是翻译成 URP 的 SurfaceData 再交给 CanDebugOverrideOutputColor）
                MySurface s  = MySampleSurface(uv);
                InputData id = MyInitInputData(s.normalTS);
                MyMaterial m = MyInitMaterial(s.albedo, s.metallic, s.perceptualRoughness);
                vec4 debugColor;
                if (CanDebugOverrideOutputColor(s.albedo, s.alpha, m.f0, s.metallic, 1.0 - s.perceptualRoughness,
                                                s.occlusion, s.emission, id.normalWS, debugColor))
                {
                    fragColor = debugColor;
                    return;
                }
            #endif
                fragColor = MyPBRFrag();
            }
            #endif
            ENDGLSL
        }
        //#endregion

        //#region pass_shadow
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            GLSLPROGRAM
            #pragma shader_feature_local _ALPHATEST_ON
            // 方向光与点/聚光的法线偏移公式不同，URP 用 _CASTING_PUNCTUAL_LIGHT_SHADOW 关键字区分（网页版是 uniform）
            #include "Ch11/MyPBR_DepthPasses.glsl"
            #ifdef VERTEX
            void main() { MyShadowVert(); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = MyShadowFrag(); }
            #endif
            ENDGLSL
        }
        //#endregion

        //#region pass_depth
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask R
            Cull Back

            GLSLPROGRAM
            #pragma shader_feature_local _ALPHATEST_ON
            #include "Ch11/MyPBR_DepthPasses.glsl"
            #ifdef VERTEX
            void main() { MyDepthVert(); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = MyDepthFrag(); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On
            Cull Back

            GLSLPROGRAM
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _ALPHATEST_ON
            #include "Ch11/MyPBR_DepthPasses.glsl"
            #ifdef VERTEX
            void main() { MyDepthNormalsVert(); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = MyDepthNormalsFrag(); }
            #endif
            ENDGLSL
        }
        //#endregion

        //#region pass_meta
        Pass
        {
            Name "Meta"
            Tags { "LightMode"="Meta" }
            Cull Off

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _MASKMAP
            #pragma shader_feature_local_fragment _EMISSION
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #include "Ch11/MyPBR_MetaPass.glsl"
            #ifdef VERTEX
            void main() { MyMetaVert(); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = MyMetaFrag(); }
            #endif
            ENDGLSL
        }
        //#endregion
    }
}
