// 只看“间接高光”：按粗糙度从预过滤 cubemap 的不同 mip 取环境反射。（GLSL 版，对应 Ch08/EnvReflection.shader）
// 模式 0：URP 的 GlossyEnvironmentReflection（探针、混合、盒体投影全包）；
// 模式 1：手动采样全局环境 cubemap，粗糙度 → mip 用线性映射（对照用）；
// 模式 2：手动采样，使用 URP 的非线性映射 PerceptualRoughnessToMipmapLevel。
Shader "Cookbook/Ch08/EnvReflection"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        GLSLINCLUDE
        uniform vec4  _Tint;
        uniform float _Roughness;
        uniform float _Mode;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            VARYING vec3 positionWS;
            VARYING vec3 normalWS;

            #ifdef VERTEX
            void main()
            {
                positionWS = TransformObjectToWorld(positionOS.xyz);
                gl_Position = TransformWorldToHClip(positionWS);
                normalWS = TransformObjectToWorldNormal(normalOS);
            }
            #endif

            #ifdef FRAGMENT
            // 网页版没有反射探针，全局环境反射就是 unity_SpecCube0；URP 里对应的名字是 _GlossyEnvironmentCubeMap
            #define _GlossyEnvironmentCubeMap unity_SpecCube0
            #define _GlossyEnvironmentCubeMap_HDR unity_SpecCube0_HDR

            //#region manual
            // 手动版：全局环境反射（Lighting 窗口里的 Environment Reflections）由 URP 设置为
            // _GlossyEnvironmentCubeMap，它的 mip 链是按粗糙度预过滤过的
            vec3 SampleEnvManual(vec3 R, float perceptualRoughness, bool urpCurve)
            {
                float mip = urpCurve
                    ? PerceptualRoughnessToMipmapLevel(perceptualRoughness)   // r·(1.7-0.7r)·6
                    : perceptualRoughness * UNITY_SPECCUBE_LOD_STEPS;          // 线性：r·6
                vec4 encoded = textureLod(_GlossyEnvironmentCubeMap, R, mip);
                // HDR 解码：RGBM/dLDR 编码的 cubemap 需要 _HDR 参数还原，浮点格式时它只是乘一个强度
                return DecodeHDREnvironment(encoded, _GlossyEnvironmentCubeMap_HDR);
            }
            //#endregion

            void main()
            {
                vec3 N = normalize(normalWS);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                vec3 R = reflect(-V, N);
                vec3 c;
                if (_Mode < 0.5)
                {
                    c = GlossyEnvironmentReflection(R, positionWS, _Roughness, 1.0);
                }
                else
                {
                    c = SampleEnvManual(R, _Roughness, _Mode > 1.5);
                }
                fragColor = vec4(c * _Tint.rgb, 1.0);
            }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #include "Ch08/Ch08Passes.glsl"
            #ifdef VERTEX
            void main() { gl_Position = Ch08DepthVert(); }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = Ch08NullFrag(); }
            #endif
            ENDGLSL
        }
    }
}
