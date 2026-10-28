// 案例 26.1：第一个自定义 Volume 组件——饱和度 / 对比度。
using System;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch26
{
    //#region volume
    // VolumeComponentMenuForRenderPipeline：出现在 Volume 的 Add Override 菜单里，并且只对 URP 显示
    [Serializable, VolumeComponentMenuForRenderPipeline("Cookbook/Saturation", typeof(UniversalRenderPipeline))]
    public sealed class SaturationVolume : VolumeComponent, IPostProcessComponent
    {
        // 默认值要等于“无效果”的值：没有任何 Volume 覆盖时，栈里拿到的就是默认值
        [Tooltip("0 = 灰度，1 = 原图，>1 = 更鲜艳")]
        public ClampedFloatParameter saturation = new ClampedFloatParameter(1f, 0f, 2f);

        [Tooltip("围绕中灰 0.18（线性）缩放的对比度")]
        public ClampedFloatParameter contrast = new ClampedFloatParameter(1f, 0f, 2f);

        // 由 Feature 调用：没有效果时整个 Pass 都不入队，零开销
        public bool IsActive() => saturation.value != 1f || contrast.value != 1f;

        // 接口要求实现；URP 14 源码里并没有调用它，返回 false 即可
        public bool IsTileCompatible() => false;
    }
    //#endregion
}
