// 案例 29.1：用 MaterialPropertyBlock 给每个物体不同颜色（配合 BatcherFriendly.shader 的 _InstanceColor）。
// 注意：带 MaterialPropertyBlock 的 Renderer 会退出 SRP Batcher；
// 只有材质勾选了 Enable GPU Instancing、Shader 支持 Instancing 时，它们才能被实例化成一个 Draw Call。
using UnityEngine;

namespace Cookbook.Ch29
{
    [ExecuteAlways]
    public class PerInstanceTint : MonoBehaviour
    {
        public Color tint = Color.white;
        static MaterialPropertyBlock s_Block;
        static readonly int s_InstanceColor = Shader.PropertyToID("_InstanceColor");

        void OnEnable() { Apply(); }
        void OnValidate() { Apply(); }

        //#region apply
        void Apply()
        {
            var r = GetComponent<Renderer>();
            if (r == null) return;
            s_Block ??= new MaterialPropertyBlock();
            r.GetPropertyBlock(s_Block);
            s_Block.SetColor(s_InstanceColor, tint);
            r.SetPropertyBlock(s_Block);
        }
        //#endregion
    }
}
