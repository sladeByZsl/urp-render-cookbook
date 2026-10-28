using UnityEngine;

namespace Cookbook.Ch23
{
    /// 案例 23.4：让一个 Blob 阴影 Quad 跟随目标物体。
    /// 每帧从目标向下打射线找地面，把 Quad 贴到命中点、对齐地面法线，
    /// 并根据离地高度放大、变淡（物体跳得越高，影子越大越虚）。
    [ExecuteAlways]
    public class BlobShadow : MonoBehaviour
    {
        public Transform target;
        [Tooltip("贴地时的阴影直径（米）")] public float baseSize = 1.0f;
        [Tooltip("离地 maxHeight 时直径放大到 baseSize × (1 + growth)")] public float growth = 0.8f;
        public float maxHeight = 3f;
        [Range(0, 1)] public float strength = 0.8f;
        [Tooltip("射线打不到碰撞体时使用的地面高度")] public float fallbackGroundY = 0f;
        public LayerMask groundMask = ~0;

        MaterialPropertyBlock m_Block;
        Renderer m_Renderer;
        static readonly int s_Strength = Shader.PropertyToID("_Strength");

        void LateUpdate() => Apply();

        //#region apply
        public void Apply()
        {
            if (target == null) return;
            if (m_Renderer == null) m_Renderer = GetComponent<Renderer>();

            Vector3 origin = target.position;
            Vector3 groundPos = new Vector3(origin.x, fallbackGroundY, origin.z);
            Vector3 groundNormal = Vector3.up;
            if (Physics.Raycast(origin, Vector3.down, out var hit, maxHeight * 4f, groundMask, QueryTriggerInteraction.Ignore))
            {
                groundPos = hit.point;
                groundNormal = hit.normal;
            }

            float height = Mathf.Max(0f, origin.y - groundPos.y);
            float t = Mathf.Clamp01(height / maxHeight);

            // Quad 默认朝 -Z，旋转到“正面朝上”并贴合地面法线
            transform.SetPositionAndRotation(groundPos + groundNormal * 0.005f,
                Quaternion.FromToRotation(Vector3.back, groundNormal));
            transform.localScale = Vector3.one * baseSize * (1f + growth * t);

            // 用 MaterialPropertyBlock 改每个阴影自己的浓度，不必为每个单位复制材质。
            // 注意：带 MPB 的 Renderer 不再走 SRP Batcher；单位很多时改用 GPU Instancing 或顶点色。
            m_Block ??= new MaterialPropertyBlock();
            m_Renderer.GetPropertyBlock(m_Block);
            m_Block.SetFloat(s_Strength, strength * (1f - t));
            m_Renderer.SetPropertyBlock(m_Block);
        }
        //#endregion
    }
}
