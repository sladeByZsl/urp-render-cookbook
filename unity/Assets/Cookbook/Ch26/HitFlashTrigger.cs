// 案例 26.10：用 Volume 权重驱动受击红屏。MonoBehaviour 必须放在同名文件里，才能在 Inspector 中添加。
using UnityEngine;
using UnityEngine.Rendering;

namespace Cookbook.Ch26
{
    //#region trigger
    /// 挂在一个全局 Volume（Is Global 勾选，Profile 里只放 HitFlashVolume 且 intensity=1）上。
    /// 受击时调用 Hit()：Volume 权重瞬间拉到 1 再按曲线衰减到 0。权重为 0 时栈里的 intensity 回到默认值 0，
    /// Feature 的 IsActive() 为假，整个 Pass 不入队，平时没有任何开销。
    [RequireComponent(typeof(Volume))]
    public class HitFlashTrigger : MonoBehaviour
    {
        public float duration = 0.6f;
        public AnimationCurve falloff = AnimationCurve.EaseInOut(0, 1, 1, 0);

        Volume m_Volume;
        float m_Elapsed = float.MaxValue;

        void Awake()
        {
            m_Volume = GetComponent<Volume>();
            m_Volume.weight = 0f;
        }

        public void Hit(float strength = 1f)
        {
            m_Elapsed = 0f;
            m_Volume.weight = strength;
        }

        void Update()
        {
            if (m_Elapsed > duration) { m_Volume.weight = 0f; return; }
            m_Elapsed += Time.deltaTime;
            m_Volume.weight = falloff.Evaluate(Mathf.Clamp01(m_Elapsed / duration));
        }
    }
    //#endregion
}
