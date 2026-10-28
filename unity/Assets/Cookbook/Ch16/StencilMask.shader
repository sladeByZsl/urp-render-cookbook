// 传送门遮罩：不写颜色、不写深度，只把模板缓冲里自己覆盖的像素改成 Ref。
// 队列比普通不透明物体早（Geometry-10），保证“门里的世界”绘制时模板已经写好。
Shader "Cookbook/Ch16/StencilMask"
{
    Properties
    {
        [IntRange] _StencilRef ("Stencil Ref", Range(0, 255)) = 1
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry-10" }

        Pass
        {
            Name "Mask"
            Tags { "LightMode"="UniversalForwardOnly" }
            //#region state
            ColorMask 0
            ZWrite Off
            Cull Off
            Stencil
            {
                Ref [_StencilRef]
                Comp Always
                Pass Replace      // 通过（含深度测试）就把模板值替换为 Ref
            }
            //#endregion
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            CBUFFER_START(UnityPerMaterial)
                float _StencilRef;
            CBUFFER_END
            float4 vert(float4 positionOS : POSITION) : SV_POSITION { return TransformObjectToHClip(positionOS.xyz); }
            half4 frag() : SV_Target { return 0; }
            ENDHLSL
        }
    }
}
