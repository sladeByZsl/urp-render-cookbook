// 30.7 节问题现场一（错误示范）：一块读取 _CameraOpaqueTexture 的“玻璃”。
// _FlipBug = 1 时手动把屏幕 UV 的 y 再翻一次——这是把 OpenGL 时代的经验套到 D3D/Metal 上的典型错误，
// 玻璃里看到的画面会上下颠倒。
Shader "Cookbook/Ch30/ScreenUVGlass"
{
    Properties
    {
        _Tint ("Tint", Color) = (0.85, 0.95, 1, 1)
        [Toggle] _FlipBug ("Flip Bug", Float) = 0
    }
    SubShader
    {
        Tags { "RenderType"="Transparent" "Queue"="Transparent" "RenderPipeline"="UniversalPipeline" }
        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            ZWrite Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

            CBUFFER_START(UnityPerMaterial)
                half4 _Tint;
                float _FlipBug;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings { float4 positionCS : SV_POSITION; };

            Varyings vert(Attributes input)
            {
                Varyings o;
                o.positionCS = TransformObjectToHClip(input.positionOS.xyz);
                return o;
            }

            //#region uv
            half4 frag(Varyings i) : SV_Target
            {
                // ✓ 正确：URP 的函数内部已处理平台差异与动态分辨率
                float2 uv = GetNormalizedScreenSpaceUV(i.positionCS);
                // ✗ 错误：自作主张再翻一次
                if (_FlipBug > 0.5) uv.y = 1 - uv.y;
                return half4(SampleSceneColor(uv) * _Tint.rgb, 1);
            }
            //#endregion
            ENDHLSL
        }
    }
}
