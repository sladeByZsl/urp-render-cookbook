// 盒体投影（Box Projection）演示：用 URP 的 BoxProjectedCubemapDirection 修正反射方向。（GLSL 版，对应 Ch08/BoxProjection.shader）
// 为了在批处理拍摄中完全可控，探针参数（cubemap、位置、盒体）由材质直接提供；
// 场景里真正的反射探针走的是 GlossyEnvironmentReflection 里同一个函数，原理完全相同。
Shader "Cookbook/Ch08/BoxProjection"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }
        GLSLINCLUDE
        uniform vec4  _ProbePosition;
        uniform vec4  _BoxMin;
        uniform vec4  _BoxMax;
        uniform vec4  _BaseColor;
        uniform float _Reflectivity;
        uniform float _Roughness;
        ENDGLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForwardOnly" }
            GLSLPROGRAM
            #pragma shader_feature_local_fragment _BOX_PROJECTION

            uniform samplerCube _Cube;

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
            // URP ImageBasedLighting.hlsl 里的 BoxProjectedCubemapDirection（网页版公共库没有这个函数，照原样抄在这里）：
            // 把反射射线和探针的 AABB 求交，用“交点相对探针中心的方向”去查 cubemap
            vec3 BoxProjectedCubemapDirection(vec3 reflectionWS, vec3 positionWS, vec4 cubemapPositionWS, vec4 boxMin, vec4 boxMax)
            {
                if (cubemapPositionWS.w > 0.0)
                {
                    vec3 boxMinMax = mix(boxMin.xyz, boxMax.xyz, vec3(greaterThan(reflectionWS, vec3(0.0))));
                    vec3 rbMinMax = (boxMinMax - positionWS) / reflectionWS;
                    float fa = min(min(rbMinMax.x, rbMinMax.y), rbMinMax.z);
                    vec3 worldPos = positionWS - cubemapPositionWS.xyz;
                    return worldPos + reflectionWS * fa;
                }
                return reflectionWS;
            }

            //#region frag
            void main()
            {
                vec3 N = normalize(normalWS);
                vec3 V = GetWorldSpaceNormalizeViewDir(positionWS);
                vec3 R = reflect(-V, N);
            #if defined(_BOX_PROJECTION)
                // 第 4 个分量 w > 0 表示“这个探针启用了盒体投影”，与 URP 的 unity_SpecCube0_ProbePosition 约定一致
                R = BoxProjectedCubemapDirection(R, positionWS, vec4(_ProbePosition.xyz, 1.0), _BoxMin, _BoxMax);
            #endif
                float mip = PerceptualRoughnessToMipmapLevel(_Roughness);
                vec3 refl = textureLod(_Cube, R, mip).rgb;

                // 简化的菲涅尔：掠射角反射更强
                float NoV = saturate(dot(N, V));
                float F = _Reflectivity + (1.0 - _Reflectivity) * Pow4(1.0 - NoV) * 0.5;
                vec3 diffuse = _BaseColor.rgb * SampleSH(N);
                fragColor = vec4(mix(diffuse, refl, F), 1.0);
            }
            //#endregion
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
