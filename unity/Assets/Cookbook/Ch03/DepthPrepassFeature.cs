// 演示用 Renderer Feature：声明“我在不透明物体之前就要用深度图”，从而让 URP 走深度预渲染（Depth Prepass）。
// 真实项目里 SSAO（Depth 源）、某些自定义效果都会这样触发 Depth Prepass。
// 这时 _CameraDepthTexture 由各物体的 DepthOnly Pass 画出来——没有 DepthOnly Pass 的物体就不在深度图里。
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch03
{
    public class DepthPrepassFeature : ScriptableRendererFeature
    {
        class RequestDepthPass : ScriptableRenderPass
        {
            public RequestDepthPass()
            {
                renderPassEvent = RenderPassEvent.BeforeRenderingOpaques;
                ConfigureInput(ScriptableRenderPassInput.Depth);
            }
            // 什么都不画，只负责“提需求”
            public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData) { }
        }

        RequestDepthPass m_Pass;

        public override void Create() { m_Pass = new RequestDepthPass(); }

        public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
        {
            renderer.EnqueuePass(m_Pass);
        }
    }
}
