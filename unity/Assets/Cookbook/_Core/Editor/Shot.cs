// 书中配图的“摄影棚”：每个 [BookShot] 方法在一个全新的空场景里搭景，然后渲染成图片。
// 作者只需要写搭景代码，灯光、相机、天空、环境光、URP Asset 都有默认值。
using System;
using System.Collections.Generic;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using Object = UnityEngine.Object;

namespace Cookbook.Core
{
    [AttributeUsage(AttributeTargets.Method)]
    public class BookShotAttribute : Attribute
    {
        public readonly string Id;
        public int W = 960, H = 540, Panels = 1;
        /// true：相机渲染到 RGBAHalf 浮点目标（真正的 HDR，Bloom/Tonemapping 才能拿到 >1 的值），再转成 sRGB 存图
        public bool Hdr;
        public BookShotAttribute(string id) { Id = id; }
    }

    public class Shot
    {
        public int Panel;                       // 多联图时当前是第几格（0 开始）
        public Camera Cam;
        public Light Sun;
        public UniversalRenderPipelineAsset Asset;
        public UniversalRendererData Renderer;
        public UniversalAdditionalCameraData CamData;
        internal readonly List<Object> Temp = new List<Object>();

        // ---------- 材质 ----------
        public Material Mat(string shaderName)
        {
            var sh = Shader.Find(shaderName);
            if (sh == null) throw new Exception("Shader not found: " + shaderName);
            var m = new Material(sh) { name = shaderName };
            Temp.Add(m);
            return m;
        }

        /// URP 自带 Lit 材质，用来做对照或陪衬
        public Material Lit(Color c, float metallic = 0f, float smoothness = 0.5f)
        {
            var m = Mat("Universal Render Pipeline/Lit");
            m.SetColor("_BaseColor", c);
            m.SetFloat("_Metallic", metallic);
            m.SetFloat("_Smoothness", smoothness);
            return m;
        }

        /// 配套贴图：CoreTex("bricks_albedo") -> Assets/Cookbook/_Core/Textures/bricks_albedo.png
        public Texture2D CoreTex(string name) => Tex("Assets/Cookbook/_Core/Textures/" + name + ".png");

        public Texture2D Tex(string assetPath)
        {
            var t = AssetDatabase.LoadAssetAtPath<Texture2D>(assetPath);
            if (t == null) throw new Exception("Texture not found: " + assetPath);
            return t;
        }

        // ---------- 物体 ----------
        public GameObject Prim(PrimitiveType type, Material m, Vector3 pos, float scale = 1f)
        {
            var go = GameObject.CreatePrimitive(type);
            go.transform.position = pos;
            go.transform.localScale = Vector3.one * scale;
            if (m != null) go.GetComponent<MeshRenderer>().sharedMaterial = m;
            Object.DestroyImmediate(go.GetComponent<Collider>());
            return go;
        }
        public GameObject Sphere(Material m, Vector3 pos, float scale = 1f) => Prim(PrimitiveType.Sphere, m, pos, scale);
        public GameObject Cube(Material m, Vector3 pos, float scale = 1f) => Prim(PrimitiveType.Cube, m, pos, scale);
        public GameObject Capsule(Material m, Vector3 pos, float scale = 1f) => Prim(PrimitiveType.Capsule, m, pos, scale);
        public GameObject Cylinder(Material m, Vector3 pos, float scale = 1f) => Prim(PrimitiveType.Cylinder, m, pos, scale);
        public GameObject Quad(Material m, Vector3 pos, float scale = 1f) => Prim(PrimitiveType.Quad, m, pos, scale);

        /// 地面：size×size 米的平面，默认浅灰棋盘格 Lit（每格 1 米）
        public GameObject Floor(Material m = null, float size = 60f, float y = 0f)
        {
            if (m == null)
            {
                m = Lit(new Color(0.75f, 0.75f, 0.75f), 0, 0.15f);
                m.SetTexture("_BaseMap", CoreTex("checker"));
                m.SetTextureScale("_BaseMap", new Vector2(size / 8f, size / 8f));
            }
            var go = Prim(PrimitiveType.Plane, m, new Vector3(0, y, 0));
            go.transform.localScale = new Vector3(size / 10f, 1, size / 10f);
            go.name = "Floor";
            return go;
        }

        public GameObject MeshObj(Mesh mesh, Material m, Vector3 pos, float scale = 1f, string name = "Mesh")
        {
            var go = new GameObject(name);
            go.transform.position = pos;
            go.transform.localScale = Vector3.one * scale;
            go.AddComponent<MeshFilter>().sharedMesh = mesh;
            go.AddComponent<MeshRenderer>().sharedMaterial = m;
            Temp.Add(mesh);
            return go;
        }
        public GameObject Torus(Material m, Vector3 pos, float R = 0.7f, float r = 0.28f) => MeshObj(Meshes.Torus(R, r), m, pos, 1, "Torus");
        public GameObject Knot(Material m, Vector3 pos, float scale = 1f) => MeshObj(Meshes.TorusKnot(), m, pos, scale, "Knot");
        /// 细分平面（顶点动画、水面用），中心在 pos，边长 size，每边 n 段
        public GameObject Grid(Material m, Vector3 pos, float size = 4f, int n = 128) => MeshObj(Meshes.Grid(size, n), m, pos, 1, "Grid");

        /// 一排小球：count 个，从 x0 起每隔 step 一个，matFor(i) 给出第 i 个的材质
        public void SphereRow(int count, Func<int, Material> matFor, float y = 0.5f, float z = 0f, float step = 1.1f, float scale = 1f)
        {
            float x0 = -(count - 1) * step * 0.5f;
            for (int i = 0; i < count; i++) Sphere(matFor(i), new Vector3(x0 + i * step, y, z), scale);
        }

        // ---------- 灯光 ----------
        public Light Point(Vector3 pos, Color c, float intensity = 2f, float range = 6f)
        {
            var go = new GameObject("Point");
            go.transform.position = pos;
            var l = go.AddComponent<Light>();
            l.type = LightType.Point; l.color = c; l.intensity = intensity; l.range = range;
            return l;
        }
        public Light Spot(Vector3 pos, Vector3 target, Color c, float intensity = 4f, float range = 10f, float angle = 40f)
        {
            var go = new GameObject("Spot");
            go.transform.position = pos;
            go.transform.LookAt(target);
            var l = go.AddComponent<Light>();
            l.type = LightType.Spot; l.color = c; l.intensity = intensity; l.range = range; l.spotAngle = angle;
            return l;
        }
        public void SunDir(float pitch, float yaw, float intensity = 1.3f) { Sun.transform.rotation = Quaternion.Euler(pitch, yaw, 0); Sun.intensity = intensity; }

        // ---------- 相机与背景 ----------
        public void LookAt(Vector3 pos, Vector3 target, float fov = 35f)
        {
            Cam.transform.position = pos; Cam.transform.LookAt(target); Cam.fieldOfView = fov;
        }
        public void Background(Color c)
        {
            Cam.clearFlags = CameraClearFlags.SolidColor; Cam.backgroundColor = c;
        }

        // ---------- URP ----------
        /// 打开相机后处理并返回全局 Volume 的 Profile，用 profile.Add<Bloom>() 添加效果
        public VolumeProfile Post()
        {
            CamData.renderPostProcessing = true;
            var go = new GameObject("Global Volume");
            var v = go.AddComponent<Volume>();
            v.isGlobal = true;
            var p = ScriptableObject.CreateInstance<VolumeProfile>();
            Temp.Add(p);
            v.sharedProfile = p;
            return p;
        }

        /// 往本张图专用的 Renderer 里加一个 Renderer Feature
        public T Feature<T>() where T : ScriptableRendererFeature
        {
            var f = ScriptableObject.CreateInstance<T>();
            f.name = typeof(T).Name;
            Temp.Add(f);
            Renderer.rendererFeatures.Add(f);
            Renderer.SetDirty();
            return f;
        }

        /// 设置 URP Asset 上没有公开 setter 的字段（例如 m_SoftShadowsSupported）
        public void AssetProp(string field, bool value)
        {
            var so = new SerializedObject(Asset);
            so.FindProperty(field).boolValue = value;
            so.ApplyModifiedPropertiesWithoutUndo();
        }
        public void AssetProp(string field, int value)
        {
            var so = new SerializedObject(Asset);
            var p = so.FindProperty(field);
            p.intValue = value;
            so.ApplyModifiedPropertiesWithoutUndo();
        }
    }
}
