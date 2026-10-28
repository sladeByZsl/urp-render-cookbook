// 案例 29.3：用 ShaderVariantCollection 在加载界面分帧预热 Shader 变体，避免进游戏后首次用到某变体时卡顿。
using System.Collections;
using UnityEngine;

namespace Cookbook.Ch29
{
    public class ShaderWarmup : MonoBehaviour
    {
        [Tooltip("在 Project Settings › Graphics 里 Save to asset 得到的变体集合")]
        public ShaderVariantCollection[] collections;
        [Tooltip("每帧最多预热多少个变体：太大一帧会卡，太小加载时间变长")]
        public int variantsPerFrame = 8;
        public System.Action onFinished;

        //#region warmup
        IEnumerator Start()
        {
            foreach (var svc in collections)
            {
                if (svc == null) continue;
                // WarmUpProgressively 每次预热指定数量的变体，全部完成时返回 true
                while (!svc.WarmUpProgressively(variantsPerFrame))
                    yield return null;
                Debug.Log($"[ShaderWarmup] {svc.name}: {svc.warmedUpVariantCount}/{svc.variantCount} variants");
            }
            onFinished?.Invoke();
        }
        //#endregion
    }
}
