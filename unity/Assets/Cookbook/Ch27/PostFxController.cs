using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch27
{
    /// 案例 27.4：运行时用脚本驱动后处理 —— 受击反馈与低血量去色。
    /// 挂在一个带 Volume 组件的物体上（建议单独一个高优先级的全局 Volume，专门给游戏逻辑用）。
    [RequireComponent(typeof(Volume))]
    public class PostFxController : MonoBehaviour
    {
        [Range(0, 1)] public float health = 1f;
        public float hitDecay = 3f;               // 受击效果每秒衰减多少
        public Color hitColor = new Color(0.6f, 0f, 0f);

        Volume m_Volume;
        Vignette m_Vignette;
        ChromaticAberration m_CA;
        ColorAdjustments m_Color;
        float m_Hit;

        //#region setup
        void OnEnable()
        {
            m_Volume = GetComponent<Volume>();
            // profile（而不是 sharedProfile）会在第一次访问时克隆一份运行时实例，改它不会污染磁盘上的资源
            var profile = m_Volume.profile;
            m_Vignette = GetOrAdd<Vignette>(profile);
            m_CA = GetOrAdd<ChromaticAberration>(profile);
            m_Color = GetOrAdd<ColorAdjustments>(profile);
        }

        static T GetOrAdd<T>(VolumeProfile profile) where T : VolumeComponent
        {
            if (!profile.TryGet(out T comp)) comp = profile.Add<T>();
            comp.active = true;
            return comp;
        }
        //#endregion

        public void OnHit(float strength = 1f) => m_Hit = Mathf.Clamp01(m_Hit + strength);

        //#region update
        void Update()
        {
            m_Hit = Mathf.Max(0f, m_Hit - hitDecay * Time.deltaTime);

            // Override(x) 同时做两件事：overrideState = true，value = x。
            // 只改 .value 而 overrideState 为 false 时，这个参数不参与混合，改了等于没改。
            m_Vignette.color.Override(hitColor);
            m_Vignette.intensity.Override(Mathf.Lerp(0.2f, 0.55f, m_Hit));
            m_Vignette.smoothness.Override(0.6f);
            m_CA.intensity.Override(m_Hit * 0.8f);

            // 低血量：血量低于 30% 后逐渐去色
            float lowHp = Mathf.InverseLerp(0.3f, 0f, health);
            m_Color.saturation.Override(Mathf.Lerp(0f, -80f, lowHp));
        }
        //#endregion

        //#region read
        /// 读取“混合之后”的最终值（所有 Volume 按权重、优先级叠加的结果）。
        /// 注意 VolumeManager.instance.stack 是默认栈，由当前渲染的相机在每帧更新。
        public static float CurrentBloomIntensity()
        {
            var bloom = VolumeManager.instance.stack.GetComponent<Bloom>();
            return bloom != null && bloom.IsActive() ? bloom.intensity.value : 0f;
        }
        //#endregion

        void OnDisable()
        {
            // 用的是 profile 克隆出来的运行时实例，销毁时一并清理
            if (m_Volume != null && m_Volume.HasInstantiatedProfile()) Destroy(m_Volume.profile);
        }
    }
}
