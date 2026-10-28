// 案例 22.4–22.7：自写屏幕空间贴花——画一个单位立方体，用深度重建世界坐标，投到盒子本地空间做 UV（GLSL 版）
// 约定与 URP Decal Projector 相同：沿物体 +Z 方向投影，盒子是 [-0.5, 0.5]³
Shader "Cookbook/Ch22/ScreenSpaceDecal"
{
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

            GLSLPROGRAM
            #pragma shader_feature_local_fragment _NORMALMAP
            #pragma shader_feature_local_fragment _DECAL_LIT

            uniform vec4 _BaseMap_ST;
            uniform vec4 _BaseColor;
            uniform float _BumpScale, _Smoothness;
            uniform float _AngleStart, _AngleEnd, _DepthFade;
            uniform float _Modulate, _Debug;
            uniform sampler2D _BaseMap;
            uniform sampler2D _BumpMap;

            #ifdef VERTEX
            void main()
            {
                gl_Position = TransformObjectToHClip(positionOS.xyz);
            }
            #endif

            #ifdef FRAGMENT
            vec4 frag()
            {
                if (_Debug > 0.5 && _Debug < 1.5) return vec4(1.0, 0.35, 0.1, 0.6);   // 盒子覆盖到的像素

                //#region reconstruct
                // 1) 屏幕 UV → 场景深度 → 世界坐标
                vec2 screenUV = GetNormalizedScreenSpaceUV(gl_FragCoord);
                float rawDepth = SampleSceneDepth(screenUV);
                // HLSL 版在 OpenGL 类平台要先把 [0,1] 深度换成 [-1,1]；GLSL 版的 ComputeWorldSpacePosition 内部已经做了
                vec3 positionWS = ComputeWorldSpacePosition(screenUV, rawDepth, UNITY_MATRIX_I_VP);

                // 2) 世界坐标 → 贴花盒子的本地空间；盒子外的像素直接丢掉
                vec3 positionOS = TransformWorldToObject(positionWS);
                if (any(lessThan(0.5 - abs(positionOS), vec3(0.0)))) discard;
                //#endregion

                if (_Debug > 1.5 && _Debug < 2.5) return vec4(positionOS + 0.5, 1);

                //#region normalFade
                // 3) 用屏幕空间导数重建表面法线（平面法线，物体轮廓处会有噪点）
                vec3 normalWS = normalize(cross(dFdx(positionWS), dFdy(positionWS)));
                normalWS *= sign(dot(normalWS, GetWorldSpaceViewDir(positionWS)));   // 统一朝向相机，免去平台 Y 方向差异

                // 4) 角度衰减：表面越“侧”对投影方向，贴花越淡，避免在侧壁上拉出长条
                vec3 projDirWS = normalize(TransformObjectToWorldDir(vec3(0, 0, 1)));
                float facing = dot(normalWS, -projDirWS);                            // 1 = 正对投影器
                float cosStart = cos(radians(_AngleStart)), cosEnd = cos(radians(_AngleEnd));
                float angleFade = saturate((facing - cosEnd) / max(cosStart - cosEnd, 1e-4));
                // 盒子前后两端也淡出，贴花不会在投影深度的尽头被一刀切断
                float depthFade = saturate((0.5 - abs(positionOS.z)) / _DepthFade);
                //#endregion

                if (_Debug > 2.5) return vec4(normalWS * 0.5 + 0.5, 1);

                //#region shade
                vec2 boxUV = positionOS.xy + 0.5;              // 盒子本地 xy → 0..1 的贴花 UV
                vec2 uv = TransformTex(boxUV, _BaseMap_ST);
                vec4 decal = texture(_BaseMap, uv) * _BaseColor;
                float alpha = decal.a * angleFade * depthFade;

                vec3 color = decal.rgb;
            #if defined(_DECAL_LIT)
                vec3 n = normalWS;
                #if defined(_NORMALMAP)
                    // 贴花自己的法线贴图：切线空间就是投影器的 X/Y 轴，“上”是 -投影方向
                    vec3 nTS = UnpackNormalScale(texture(_BumpMap, uv), _BumpScale);
                    vec3 T = normalize(TransformObjectToWorldDir(vec3(1, 0, 0)));
                    vec3 B = normalize(TransformObjectToWorldDir(vec3(0, 1, 0)));
                    // 把法线贴图的扰动量（xy）叠加到重建的表面法线上（UDN 式混合）
                    n = normalize(n + (T * nTS.x + B * nTS.y) * decal.a);
                #endif
                InputData inputData = InitInputData();
                inputData.positionWS = positionWS;
                inputData.normalWS = n;
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(positionWS);
                inputData.shadowCoord = TransformWorldToShadowCoord(positionWS);
                inputData.bakedGI = SampleSH(n);
                inputData.normalizedScreenSpaceUV = screenUV;
                inputData.shadowMask = vec4(1, 1, 1, 1);
                SurfaceData surface = InitSurfaceData();
                surface.albedo = decal.rgb;
                surface.metallic = 0.0;
                surface.smoothness = _Smoothness;
                surface.occlusion = 1.0;
                surface.alpha = alpha;
                color = UniversalFragmentPBR(inputData, surface).rgb;
            #endif
                // 正片叠底模式：alpha 折算进颜色（透明处 = 白 = 不改变背景）
                color = mix(color, mix(vec3(1.0), decal.rgb, alpha), _Modulate);
                return vec4(color, alpha);
                //#endregion
            }
            void main() { fragColor = frag(); }
            #endif
            ENDGLSL
        }
    }
}
