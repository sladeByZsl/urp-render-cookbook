// 案例 20.7–20.9：用 Graphics.RenderMeshInstanced 批量绘制草丛，并把“交互体”位置上传成全局数组。
// 不创建任何 GameObject：一万丛草只是一组矩阵，每 1023 个一批提交给 GPU。
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;

namespace Cookbook.Ch20
{
    [ExecuteAlways]
    public class GrassRenderer : MonoBehaviour
    {
        public const int MaxInteractors = 8;
        const int BatchSize = 1023;   // 常量缓冲区里放得下的实例矩阵上限（与 DrawMeshInstanced 相同）

        public Mesh mesh;
        public Material material;
        public bool castShadows = true;
        [Tooltip("会把草压弯的物体，例如角色、滚动的球")]
        public Transform[] interactors;
        public float interactorRadius = 1f;

        readonly List<Matrix4x4[]> m_Batches = new List<Matrix4x4[]>();
        readonly List<MaterialPropertyBlock> m_Props = new List<MaterialPropertyBlock>();
        readonly Vector4[] m_InteractorData = new Vector4[MaxInteractors];
        Bounds m_Bounds;

        static readonly int s_Variation = Shader.PropertyToID("_Variation");
        static readonly int s_Interactors = Shader.PropertyToID("_Ch20Interactors");
        static readonly int s_InteractorCount = Shader.PropertyToID("_Ch20InteractorCount");

        //#region setInstances
        /// 设置所有实例：矩阵 + 每实例一个 0..1 的随机值（Shader 里用来做颜色变化）
        public void SetInstances(IList<Matrix4x4> matrices, IList<float> variation)
        {
            m_Batches.Clear();
            m_Props.Clear();
            var min = Vector3.one * float.MaxValue;
            var max = Vector3.one * float.MinValue;
            for (int start = 0; start < matrices.Count; start += BatchSize)
            {
                int count = Mathf.Min(BatchSize, matrices.Count - start);
                var mats = new Matrix4x4[count];
                var vars = new float[count];
                for (int i = 0; i < count; i++)
                {
                    mats[i] = matrices[start + i];
                    vars[i] = variation[start + i];
                    Vector3 p = mats[i].GetColumn(3);
                    min = Vector3.Min(min, p); max = Vector3.Max(max, p);
                }
                // 每批一个 MaterialPropertyBlock，数组属性会按实例分发到 UNITY_INSTANCING_BUFFER
                var mpb = new MaterialPropertyBlock();
                mpb.SetFloatArray(s_Variation, vars);
                m_Batches.Add(mats);
                m_Props.Add(mpb);
            }
            m_Bounds = new Bounds((min + max) * 0.5f, max - min + Vector3.one * 2f);  // 外扩 1 米，留给草高和弯曲
        }
        //#endregion

        //#region draw
        void OnEnable() { RenderPipelineManager.beginCameraRendering += OnBeginCamera; }
        void OnDisable() { RenderPipelineManager.beginCameraRendering -= OnBeginCamera; }

        // 在每个相机开始渲染时提交：编辑模式、Scene 视图、手动 Camera.Render() 都能画出来。
        // 只在 Play 模式下用的话，放进 Update() 里调用、不指定 camera 也可以。
        void OnBeginCamera(ScriptableRenderContext context, Camera cam)
        {
            if (mesh == null || material == null || m_Batches.Count == 0) return;
            UploadInteractors();
            var rp = new RenderParams(material)
            {
                camera = cam,                          // 只画进当前这个相机
                worldBounds = m_Bounds,                // 整片草地的包围盒，用于视锥剔除
                shadowCastingMode = castShadows ? ShadowCastingMode.On : ShadowCastingMode.Off,
                receiveShadows = true,
                layer = gameObject.layer,
            };
            for (int i = 0; i < m_Batches.Count; i++)
            {
                rp.matProps = m_Props[i];
                Graphics.RenderMeshInstanced(rp, mesh, 0, m_Batches[i]);
            }
        }
        //#endregion

        //#region interactors
        void UploadInteractors()
        {
            int n = 0;
            if (interactors != null)
                foreach (var t in interactors)
                {
                    if (t == null || n >= MaxInteractors) continue;
                    var p = t.position;
                    m_InteractorData[n++] = new Vector4(p.x, p.y, p.z, interactorRadius * t.lossyScale.x);
                }
            // 全局数组：所有用到它的材质都能读到（草、灌木、花……）
            Shader.SetGlobalVectorArray(s_Interactors, m_InteractorData);
            Shader.SetGlobalFloat(s_InteractorCount, n);
        }
        //#endregion

        //#region clumpMesh
        /// 一丛草：blades 片草叶随机分布在半径 radius 的圆盘里。
        /// uv.y = 沿草叶的高度（0 根部，1 叶尖），Shader 用它当弯曲权重；color.r = 每片叶子的随机值
        public static Mesh BuildClump(int blades = 9, float radius = 0.22f, int seed = 1)
        {
            const int seg = 4;
            var rnd = new System.Random(seed);
            float R() => (float)rnd.NextDouble();
            var v = new List<Vector3>(); var n = new List<Vector3>(); var uv = new List<Vector2>();
            var col = new List<Color>(); var idx = new List<int>();
            for (int b = 0; b < blades; b++)
            {
                float a = R() * Mathf.PI * 2, r = Mathf.Sqrt(R()) * radius;
                var root = new Vector3(Mathf.Cos(a) * r, 0, Mathf.Sin(a) * r);
                float yaw = R() * Mathf.PI * 2;
                var side = new Vector3(Mathf.Cos(yaw), 0, Mathf.Sin(yaw));        // 叶片宽度方向
                var face = Vector3.Cross(side, Vector3.up);                         // 叶片朝向
                float h = Mathf.Lerp(0.35f, 0.7f, R()), w = Mathf.Lerp(0.03f, 0.05f, R());
                float lean = Mathf.Lerp(0.05f, 0.3f, R());                          // 叶尖前倾量
                float rand = R();
                int baseIdx = v.Count;
                for (int s = 0; s <= seg; s++)
                {
                    float t = (float)s / seg;
                    var center = root + Vector3.up * (h * t) + face * (lean * t * t);
                    float ww = w * (1 - t * 0.85f);
                    var bend = (Vector3.up - face * (2 * lean * t / h)).normalized;  // 沿叶片的切向
                    var nrm = Vector3.Cross(bend, side).normalized;
                    if (s < seg)
                    {
                        v.Add(center - side * ww); v.Add(center + side * ww);
                        n.Add(nrm); n.Add(nrm);
                        uv.Add(new Vector2(0, t)); uv.Add(new Vector2(1, t));
                        col.Add(new Color(rand, 0, 0, 1)); col.Add(new Color(rand, 0, 0, 1));
                    }
                    else
                    {
                        v.Add(center); n.Add(nrm); uv.Add(new Vector2(0.5f, 1)); col.Add(new Color(rand, 0, 0, 1));
                    }
                }
                for (int s = 0; s < seg - 1; s++)
                {
                    int i0 = baseIdx + s * 2;
                    idx.Add(i0); idx.Add(i0 + 2); idx.Add(i0 + 1);
                    idx.Add(i0 + 1); idx.Add(i0 + 2); idx.Add(i0 + 3);
                }
                int last = baseIdx + (seg - 1) * 2;
                idx.Add(last); idx.Add(last + 2); idx.Add(last + 1);
            }
            var m = new Mesh { name = "GrassClump" };
            m.SetVertices(v); m.SetNormals(n); m.SetUVs(0, uv); m.SetColors(col); m.SetTriangles(idx, 0);
            m.RecalculateBounds();
            return m;
        }
        //#endregion
    }
}
