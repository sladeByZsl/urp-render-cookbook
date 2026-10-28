// 案例 18.1~18.3：溶解。噪声 clip + 边缘发光 + 三种溶解形状（噪声 / 方向 / 球形）。（GLSL 版，对应 Ch18/Dissolve.shader）
Shader "Cookbook/Ch18/Dissolve"
{
    SubShader
    {
        // 溶解本质是 Alpha Test：用 AlphaTest 队列，让 Early-Z 友好的不透明物体先画
        Tags { "RenderType"="TransparentCutout" "Queue"="AlphaTest" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Cull [_Cull]

            GLSLPROGRAM
            #pragma shader_feature_local _MODE_NOISE _MODE_DIRECTION _MODE_SPHERE
            #pragma multi_compile_fog

            #include "Ch18/DissolveCore.glsl"
            #include "Ch18/Ch18Common.glsl"

            VARYING vec2  uv;
            VARYING vec3  positionWS;
            VARYING vec3  posOS;        // 对象空间位置（HLSL 版的 positionOS 字段；GLSL 里这个名字已被顶点输入占用）
            VARYING vec3  normalWS;
            VARYING float fogFactor;

            #ifdef VERTEX
            void main()
            {
                VertexPositionInputs p = GetVertexPositionInputs(positionOS.xyz);
                gl_Position = p.positionCS;
                positionWS = p.positionWS;
                posOS = positionOS.xyz;
                normalWS = TransformObjectToWorldNormal(normalOS);
                uv = texcoord0.xy;
                fogFactor = ComputeFogFactor(p.positionCS.z);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            void main()
            {
                float edge;
                DissolveClip(DissolveValue(uv, posOS, positionWS), edge);

                vec3 albedo = texture(_BaseMap, uv * _BaseMap_ST.xy + _BaseMap_ST.zw).rgb * _BaseColor.rgb;
                // 双面渲染时，背面（物体内壁）把法线翻过来，再压暗一点，看起来像“空心的内部”
                vec3 N = normalize(normalWS) * (gl_FrontFacing ? 1.0 : -1.0);
                albedo *= gl_FrontFacing ? 1.0 : 0.35;

                // 前沿附近先“烧焦”变暗，再在最前沿发光
                albedo *= 1.0 - 0.85 * smoothstep(0.0, 0.6, edge);
                vec3 color = SimpleLighting(albedo, positionWS, N, _Smoothness);

                vec3 glow = _EdgeColor.rgb;
                if (_UseRamp > 0.5)
                    glow *= texture(_EdgeRamp, vec2(edge, 0.5)).rgb;
                // edge^2：让发光集中在最前沿，向内快速衰减
                color += glow * edge * edge;

                color = MixFog(color, fogFactor);
                fragColor = vec4(color, 1.0);
            }
            //#endregion
            #endif
            ENDGLSL
        }

        //#region shadow
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On ZTest LEqual ColorMask 0
            Cull [_Cull]

            GLSLPROGRAM
            #pragma shader_feature_local _MODE_NOISE _MODE_DIRECTION _MODE_SPHERE
            #include "Ch18/DissolveCore.glsl"
            // _LightDirection / _LightPosition 由引擎在画阴影前设置（Lighting.glsl 里已声明）

            VARYING vec2 uv;
            VARYING vec3 posOS;
            VARYING vec3 positionWS;

            #ifdef VERTEX
            void main()
            {
                positionWS = TransformObjectToWorld(positionOS.xyz);
                vec3 normalWS = TransformObjectToWorldNormal(normalOS);
                vec3 lightDirWS = _CastingPunctualLightShadow > 0.5 ? normalize(_LightPosition - positionWS) : _LightDirection;
                vec4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirWS));
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE * positionCS.w);
                gl_Position = positionCS;
                uv = texcoord0.xy; posOS = positionOS.xyz;
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                float edge;
                DissolveClip(DissolveValue(uv, posOS, positionWS), edge);
                fragColor = vec4(0.0);
            }
            #endif
            ENDGLSL
        }
        //#endregion

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            Cull [_Cull]

            GLSLPROGRAM
            #pragma shader_feature_local _MODE_NOISE _MODE_DIRECTION _MODE_SPHERE
            #include "Ch18/DissolveCore.glsl"

            VARYING vec2 uv;
            VARYING vec3 posOS;
            VARYING vec3 positionWS;

            #ifdef VERTEX
            void main()
            {
                positionWS = TransformObjectToWorld(positionOS.xyz);
                gl_Position = TransformWorldToHClip(positionWS);
                uv = texcoord0.xy; posOS = positionOS.xyz;
            }
            #endif

            #ifdef FRAGMENT
            void main()
            {
                float edge;
                DissolveClip(DissolveValue(uv, posOS, positionWS), edge);
                fragColor = vec4(gl_FragCoord.z);
            }
            #endif
            ENDGLSL
        }
    }
}
