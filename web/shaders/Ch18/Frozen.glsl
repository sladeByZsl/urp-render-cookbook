// 案例 18.9：冰冻 / 结晶覆盖。世界空间“自上而下”覆盖一层冰：加厚、冰裂纹、高光滑度、冷色边缘与闪点。
// （GLSL 版，对应 Ch18/Frozen.shader）
Shader "Cookbook/Ch18/Frozen"
{
    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            GLSLPROGRAM
            #include "Ch18/FrozenCore.glsl"
            #include "Ch18/Ch18Common.glsl"

            VARYING vec3 positionWS;
            VARYING vec3 normalWS;
            VARYING vec2 uv;
            VARYING vec3 restWS;   // 加厚之前的位置，用来采样噪声，避免纹理随厚度“游动”

            #ifdef VERTEX
            void main()
            {
                vec3 pWS = TransformObjectToWorld(positionOS.xyz);
                vec3 nWS = TransformObjectToWorldNormal(normalOS);
                restWS = pWS;
                positionWS = ThickenIce(pWS, nWS);
                gl_Position = TransformWorldToHClip(positionWS);
                normalWS = nWS;
                uv = TransformTex(texcoord0.xy, _BaseMap_ST);
            }
            #endif

            #ifdef FRAGMENT
            //#region frag
            void main()
            {
                vec3 N = normalize(normalWS);
                vec3 viewWS = GetWorldSpaceNormalizeViewDir(positionWS);
                float mask = FrostMask(restWS, N);

                vec3 baseAlbedo = texture(_BaseMap, uv).rgb * _BaseColor.rgb;

                // 冰的颜色：噪声在浅色与深色之间变化，Worley 的细胞边界做成白色裂纹
                float n = TriplanarNoise(_IceNoise, restWS, N, _IceNoiseScale * 3.0);
                float cell = TriplanarNoise(_CrackMap, restWS, N, _CrackScale);
                float crack = smoothstep(0.55, 0.8, cell) * _CrackStrength;
                vec3 ice = mix(_IceDeepColor.rgb, _IceColor.rgb, saturate(n * 1.2 + crack));
                // 冰层很薄的地方（遮罩边缘）透出一点底色
                vec3 albedo = mix(baseAlbedo, ice, mask * (0.75 + 0.25 * mask));
                float smooth_ = mix(_Smoothness, 0.9, mask);

                vec3 color = SimpleLighting(albedo, positionWS, N, smooth_);

                // 冷色菲涅尔：冰面边缘泛蓝白，模拟光在冰层里散射后从边缘透出来
                float rim = FresnelRim(N, viewWS, 3.0);
                color += _IceRimColor.rgb * rim * mask;

                // 闪点：极高频哈希，只保留最亮的极少数点；乘上视角相关的项，转动相机时会“闪”
                vec3 sp = floor(restWS * 160.0);
                float sparkle = step(0.997, Hash21(sp.xz + sp.y * 17.0));
                vec3 halfDir = SafeNormalize(GetMainLight().direction + viewWS);
                sparkle *= pow(saturate(dot(N, halfDir)), 8.0);
                color += sparkle * _SparkleStrength * mask * GetMainLight().color;
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
            #include "Ch18/FrozenCore.glsl"
            #ifdef VERTEX
            void main()
            {
                vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
                vec3 normalWS = TransformObjectToWorldNormal(normalOS);
                positionWS = ThickenIce(positionWS, normalWS);
                vec3 lightDirWS = _CastingPunctualLightShadow > 0.5 ? normalize(_LightPosition - positionWS) : _LightDirection;
                vec4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirWS));
                positionCS.z = max(positionCS.z, UNITY_NEAR_CLIP_VALUE * positionCS.w);
                gl_Position = positionCS;
            }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(0.0); }
            #endif
            ENDGLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On ColorMask R
            GLSLPROGRAM
            #include "Ch18/FrozenCore.glsl"
            #ifdef VERTEX
            void main()
            {
                vec3 positionWS = TransformObjectToWorld(positionOS.xyz);
                gl_Position = TransformWorldToHClip(ThickenIce(positionWS, TransformObjectToWorldNormal(normalOS)));
            }
            #endif
            #ifdef FRAGMENT
            void main() { fragColor = vec4(gl_FragCoord.z); }
            #endif
            ENDGLSL
        }
    }
}
