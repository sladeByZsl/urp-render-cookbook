// 案例 19.9：平面反射。用一台“镜像相机”从水面下方往上看，把画面渲染进 RenderTexture，
// 再设成全局纹理 _PlanarReflectionTex，水面 Shader 用屏幕 UV 采样它。
// URP 14 推荐的渲染方式：RenderPipeline.SubmitRenderRequest + UniversalRenderPipeline.SingleCameraRequest
// （UniversalRenderPipeline.RenderSingleCamera 在 14 里已标记为 Obsolete）。
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch19
{
    [ExecuteAlways]
    public class PlanarReflection : MonoBehaviour
    {
        public enum UpdateMode
        {
            /// 在 LateUpdate 里为 Camera.main 提交渲染请求（SubmitRenderRequest，推荐）
            LateUpdate,
            /// 不自动渲染，由外部调用 RenderFor(camera)
            Manual,
        }

        public UpdateMode updateMode = UpdateMode.LateUpdate;
        [Tooltip("反射相机渲染哪些层。水面自己必须排除在外，否则会把自己画进反射里")]
        public LayerMask reflectLayers = ~(1 << 4);          // 4 = 内置的 Water 层
        [Range(0.25f, 1f)] public float resolutionScale = 0.5f;
        [Tooltip("裁剪平面相对水面的偏移，略低于水面可以避免岸边出现缝隙")]
        public float clipPlaneOffset = 0.05f;
        public bool renderShadows = false;

        static readonly int s_TexId = Shader.PropertyToID("_PlanarReflectionTex");
        Camera m_ReflCam;
        RenderTexture m_RT;
        bool m_Rendering;           // 防止重入

        void OnDisable()
        {
            if (m_ReflCam != null) DestroyImmediate(m_ReflCam.gameObject);
            if (m_RT != null) { m_RT.Release(); DestroyImmediate(m_RT); }
            m_ReflCam = null; m_RT = null;
        }

        void LateUpdate()
        {
            if (updateMode == UpdateMode.LateUpdate && Camera.main != null) RenderFor(Camera.main);
        }

        //#region render
        /// 在渲染循环之外调用（LateUpdate、或者主相机 Render 之前）。
        /// 不要在 beginCameraRendering 回调里调用它：回调发生在 SRP 渲染循环内部，再提交请求会报
        /// “Recursive rendering is not supported in SRP”（本书拍摄时实测）。
        public void RenderFor(Camera cam)
        {
            if (m_Rendering) return;
            m_Rendering = true;
            EnsureResources(cam);
            SetupReflectionCamera(cam);

            var request = new UniversalRenderPipeline.SingleCameraRequest { destination = m_RT };
            if (RenderPipeline.SupportsRenderRequest(m_ReflCam, request))
            {
                // 镜像矩阵把左手系变成右手系，三角形绕序反了：临时反转剔除，否则只看得到物体的背面
                GL.invertCulling = true;
                RenderPipeline.SubmitRenderRequest(m_ReflCam, request);
                GL.invertCulling = false;
            }
            Shader.SetGlobalTexture(s_TexId, m_RT);
            m_Rendering = false;
        }
        //#endregion

        void EnsureResources(Camera cam)
        {
            int w = Mathf.Max(1, (int)(cam.pixelWidth * resolutionScale));
            int h = Mathf.Max(1, (int)(cam.pixelHeight * resolutionScale));
            if (m_RT == null || m_RT.width != w || m_RT.height != h)
            {
                if (m_RT != null) { m_RT.Release(); DestroyImmediate(m_RT); }
                var fmt = cam.allowHDR ? RenderTextureFormat.DefaultHDR : RenderTextureFormat.Default;
                m_RT = new RenderTexture(w, h, 24, fmt) { name = "_PlanarReflectionTex", hideFlags = HideFlags.DontSave };
                m_RT.Create();
            }
            if (m_ReflCam == null)
            {
                var go = new GameObject("Planar Reflection Camera") { hideFlags = HideFlags.HideAndDontSave };
                m_ReflCam = go.AddComponent<Camera>();
                m_ReflCam.enabled = false;           // 不参与正常的相机循环，只在我们提交请求时渲染
                var data = go.AddComponent<UniversalAdditionalCameraData>();
                data.renderPostProcessing = false;   // 后处理留给主相机统一做
                data.requiresColorOption = CameraOverrideOption.Off;
                data.requiresDepthOption = CameraOverrideOption.Off;
                data.SetRenderer(0);
            }
            m_ReflCam.GetComponent<UniversalAdditionalCameraData>().renderShadows = renderShadows;
        }

        //#region mirror
        void SetupReflectionCamera(Camera cam)
        {
            m_ReflCam.CopyFrom(cam);                 // 视场角、远近裁剪面、清屏方式等与主相机一致
            m_ReflCam.enabled = false;
            m_ReflCam.targetTexture = null;          // 由渲染请求临时指定
            m_ReflCam.cullingMask = reflectLayers;
            m_ReflCam.cameraType = CameraType.Reflection;
            m_ReflCam.useOcclusionCulling = false;

            Vector3 normal = transform.up;
            Vector3 pos = transform.position;
            Vector4 plane = new Vector4(normal.x, normal.y, normal.z, -Vector3.Dot(normal, pos));
            Matrix4x4 reflection = ReflectionMatrix(plane);

            // 相机位置也镜像过去：_WorldSpaceCameraPos、视线方向等都要基于镜像后的位置
            m_ReflCam.transform.position = reflection.MultiplyPoint(cam.transform.position);
            m_ReflCam.transform.rotation = Quaternion.LookRotation(
                Vector3.Reflect(cam.transform.forward, normal), Vector3.Reflect(cam.transform.up, normal));
            m_ReflCam.worldToCameraMatrix = cam.worldToCameraMatrix * reflection;

            // 斜裁剪（Oblique）投影：把近裁剪面换成水面，水面以下的东西不进反射
            Vector4 clipPlane = CameraSpacePlane(m_ReflCam.worldToCameraMatrix,
                                                 pos - normal * clipPlaneOffset, normal);
            m_ReflCam.projectionMatrix = cam.CalculateObliqueMatrix(clipPlane);
        }

        // 关于平面 (n, d) 的镜像矩阵：p' = p - 2 (n·p + d) n
        static Matrix4x4 ReflectionMatrix(Vector4 p)
        {
            var m = Matrix4x4.identity;
            m.m00 = 1 - 2 * p.x * p.x;  m.m01 = -2 * p.x * p.y;
            m.m02 = -2 * p.x * p.z;     m.m03 = -2 * p.w * p.x;
            m.m10 = -2 * p.y * p.x;     m.m11 = 1 - 2 * p.y * p.y;
            m.m12 = -2 * p.y * p.z;     m.m13 = -2 * p.w * p.y;
            m.m20 = -2 * p.z * p.x;     m.m21 = -2 * p.z * p.y;
            m.m22 = 1 - 2 * p.z * p.z;  m.m23 = -2 * p.w * p.z;
            return m;   // 第四行保持 (0, 0, 0, 1)
        }

        // 把世界空间的平面变换到观察空间（CalculateObliqueMatrix 需要观察空间平面）
        static Vector4 CameraSpacePlane(Matrix4x4 worldToCamera, Vector3 pos, Vector3 normal)
        {
            Vector3 cpos = worldToCamera.MultiplyPoint(pos);
            Vector3 cnormal = worldToCamera.MultiplyVector(normal).normalized;
            return new Vector4(cnormal.x, cnormal.y, cnormal.z, -Vector3.Dot(cpos, cnormal));
        }
        //#endregion
    }
}
