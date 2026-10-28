// 第 8 章配图：球谐、环境光来源、光照贴图（手工烘焙）、环境反射、盒体投影、AO、Matcap。
using System;
using System.Linq;
using Cookbook.Core;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using Object = UnityEngine.Object;

namespace Cookbook.Ch08
{
    static class Shots
    {
        // ---------------- 工具 ----------------
        static Mesh UVSphere(int seg = 96, int rings = 48)
        {
            var v = new Vector3[(seg + 1) * (rings + 1)];
            var n = new Vector3[v.Length];
            for (int r = 0; r <= rings; r++)
                for (int s = 0; s <= seg; s++)
                {
                    float th = Mathf.PI * r / rings, ph = 2 * Mathf.PI * s / seg;
                    var d = new Vector3(Mathf.Sin(th) * Mathf.Cos(ph), Mathf.Cos(th), Mathf.Sin(th) * Mathf.Sin(ph));
                    v[r * (seg + 1) + s] = d * 0.5f; n[r * (seg + 1) + s] = d;
                }
            var idx = new int[seg * rings * 6]; int k = 0;
            for (int r = 0; r < rings; r++)
                for (int s = 0; s < seg; s++)
                {
                    int a = r * (seg + 1) + s, b = a + seg + 1;
                    idx[k++] = a; idx[k++] = a + 1; idx[k++] = b;
                    idx[k++] = b; idx[k++] = a + 1; idx[k++] = b + 1;
                }
            var m = new Mesh { indexFormat = IndexFormat.UInt32, vertices = v, normals = n, triangles = idx };
            m.RecalculateBounds();
            return m;
        }

        static Material GILit(Shot s, Color c, float metallic, float smoothness)
        {
            var m = s.Mat("Cookbook/Ch08/GILit");
            m.SetColor("_BaseColor", c);
            m.SetFloat("_Metallic", metallic);
            m.SetFloat("_Smoothness", smoothness);
            return m;
        }

        // 让本张图使用自定义环境：背景天空盒、环境光 SH、默认反射三者保持一致
        static void UseEnvironment(Shot s, Func<Vector3, Color> env, bool skybox = true, int cubeSize = 128)
        {
            var cube = EnvironmentTools.BakeCubemap(env, cubeSize, 160);
            s.Temp.Add(cube);
            RenderSettings.customReflectionTexture = cube;
            RenderSettings.ambientProbe = EnvironmentTools.ProjectToSH(env);
            if (skybox)
            {
                var sky = new Material(Shader.Find("Skybox/Cubemap"));
                sky.SetTexture("_Tex", cube);
                s.Temp.Add(sky);
                RenderSettings.skybox = sky;
            }
        }

        // 一个强对比的彩色环境：上方暖白、左侧红、右侧蓝、下方偏绿，用来看清各阶 SH 的作用
        static Color Colorful(Vector3 d) => ColorfulBase(d) * 1.8f;

        static Color ColorfulBase(Vector3 d)
        {
            Color c = new Color(0.05f, 0.05f, 0.06f);
            c += new Color(1.2f, 1.1f, 0.9f) * Mathf.Pow(Mathf.Max(0, d.y), 3f);
            c += new Color(1.6f, 0.15f, 0.1f) * Mathf.Pow(Mathf.Max(0, -d.x), 4f);
            c += new Color(0.1f, 0.35f, 1.6f) * Mathf.Pow(Mathf.Max(0, d.x), 4f);
            c += new Color(0.1f, 0.5f, 0.15f) * Mathf.Pow(Mathf.Max(0, -d.y), 2f);
            return c;
        }

        // ---------------- 8.2 球谐基函数 ----------------
        [BookShot("ch08-sh-basis", W = 960, H = 560)]
        static void SHBasis(Shot s)
        {
            s.Background(new Color(0.95f, 0.96f, 0.97f));
            s.Sun.intensity = 0;
            var mesh = UVSphere();
            for (int l = 0; l <= 2; l++)
                for (int m = -l; m <= l; m++)
                {
                    var mat = s.Mat("Cookbook/Ch08/SHBasis");
                    mat.SetFloat("_L", l); mat.SetFloat("_M", m);
                    mat.SetFloat("_Mode", 1); mat.SetFloat("_Scale", 1.9f);
                    var go = s.MeshObj(Object.Instantiate(mesh), mat, new Vector3(m * 2.45f, (2 - l) * 2.35f, 0), 1f, $"Y{l}{m}");
                    go.transform.rotation = Quaternion.Euler(-20, 30, 0);
                }
            Object.DestroyImmediate(mesh);
            s.Cam.orthographic = true;
            s.Cam.orthographicSize = 3.75f;
            s.Cam.transform.position = new Vector3(0, 2.3f, -10);
            s.Cam.transform.rotation = Quaternion.identity;
        }

        // ---------------- 8.2 各阶 SH 的贡献 ----------------
        [BookShot("ch08-sh-bands", W = 640, H = 480, Panels = 3)]
        static void SHBands(Shot s)
        {
            UseEnvironment(s, Colorful, false);
            s.Background(new Color(0.12f, 0.12f, 0.13f));
            s.Sun.intensity = 0;
            var m = s.Mat("Cookbook/Ch08/AmbientSH");
            m.SetColor("_BaseColor", new Color(0.85f, 0.85f, 0.85f));
            m.SetFloat("_Bands", s.Panel);
            s.Sphere(m, new Vector3(-0.8f, 0.75f, 0), 1.15f);
            s.Knot(m, new Vector3(0.75f, 0.75f, 0), 0.62f);
            s.LookAt(new Vector3(0, 1.0f, -4.4f), new Vector3(0, 0.75f, 0), 32);
        }

        // ---------------- 8.2 SH 近似 vs 真实辐照度 ----------------
        [BookShot("ch08-sh-vs-irradiance", W = 640, H = 480, Panels = 3)]
        static void SHvsIrradiance(Shot s)
        {
            Func<Vector3, Color> env = EnvironmentTools.Studio;
            s.Background(new Color(0.12f, 0.12f, 0.13f));
            s.Sun.intensity = 0;
            Material m;
            if (s.Panel == 0)
            {
                var cube = EnvironmentTools.BakeCubemap(env, 128, 8); s.Temp.Add(cube);
                m = s.Mat("Cookbook/Ch08/CubeDisplay"); m.SetTexture("_Cube", cube); m.SetFloat("_Exposure", 0.5f);
            }
            else if (s.Panel == 1)
            {
                var irr = EnvironmentTools.BakeIrradiance(env, 32, 1024); s.Temp.Add(irr);
                m = s.Mat("Cookbook/Ch08/CubeDisplay"); m.SetTexture("_Cube", irr); m.SetColor("_Albedo", new Color(0.85f, 0.85f, 0.85f));
            }
            else
            {
                RenderSettings.ambientProbe = EnvironmentTools.ProjectToSH(env, 8192);
                m = s.Mat("Cookbook/Ch08/AmbientSH"); m.SetColor("_BaseColor", new Color(0.85f, 0.85f, 0.85f)); m.SetFloat("_Bands", 2);
            }
            s.Sphere(m, new Vector3(-0.8f, 0.75f, 0), 1.15f);
            s.Knot(m, new Vector3(0.75f, 0.75f, 0), 0.62f);
            s.LookAt(new Vector3(0, 1.0f, -4.4f), new Vector3(0, 0.75f, 0), 32);
        }

        // ---------------- 8.1 环境光三种来源 ----------------
        [BookShot("ch08-ambient-sources", W = 640, H = 480, Panels = 3)]
        static void AmbientSources(Shot s)
        {
            if (s.Panel == 0)
            {
                var sh = new SphericalHarmonicsL2();
                sh.AddAmbientLight(new Color(0.42f, 0.42f, 0.45f));        // Color：常数，只有 L0
                RenderSettings.ambientProbe = sh;
            }
            else if (s.Panel == 1)
            {
                RenderSettings.ambientProbe = EnvironmentTools.ProjectToSH(EnvironmentTools.Gradient(
                    new Color(0.25f, 0.45f, 1.1f), new Color(0.75f, 0.6f, 0.45f), new Color(0.45f, 0.25f, 0.1f)));
            }
            // Panel 2：拍摄环境默认的 Skybox 模式（程序化天空投影成 SH）
            s.Floor();
            s.SunDir(50, -30, 0.9f);
            s.Sphere(GILit(s, new Color(0.9f, 0.9f, 0.9f), 0, 0.3f), new Vector3(-0.85f, 0.55f, 0), 1.1f);
            s.Knot(GILit(s, new Color(0.9f, 0.9f, 0.9f), 0, 0.3f), new Vector3(0.75f, 0.8f, 0.2f), 0.7f);
            s.LookAt(new Vector3(0, 1.5f, -4.0f), new Vector3(0, 0.6f, 0), 34);
        }

        // ---------------- 8.3 手工烘焙光照贴图 ----------------
        [BookShot("ch08-manual-lightmap", W = 640, H = 480, Panels = 3)]
        static void ManualLightmap(Shot s)
        {
            var spheres = new[] { new Vector4(-0.6f, 0.5f, 0.2f, 0.5f), new Vector4(0.75f, 0.35f, -0.3f, 0.35f) };
            var baked = ManualLightmapBaker.BakeFloor(128, 6f, spheres, EnvironmentTools.ClearSky, 256);
            // 三格都用同一片天空投影出的 SH，唯一的区别就是“有没有遮蔽”
            RenderSettings.ambientProbe = EnvironmentTools.ProjectToSH(EnvironmentTools.ClearSky);
            s.Temp.Add(baked);
            var m = s.Mat("Cookbook/Ch08/ManualLightmap");
            m.SetTexture("_BakedGI", baked);
            m.SetFloat("_Mode", s.Panel == 0 ? 0 : s.Panel == 1 ? 2 : 1);
            // Quad 复制一份，把 uv 复制到 uv2，当作光照贴图 UV
            var tmp = GameObject.CreatePrimitive(PrimitiveType.Quad);
            var mesh = Object.Instantiate(tmp.GetComponent<MeshFilter>().sharedMesh);
            Object.DestroyImmediate(tmp);
            mesh.uv2 = mesh.uv;
            var floor = s.MeshObj(mesh, m, Vector3.zero, 6f, "Floor");
            floor.transform.rotation = Quaternion.Euler(90, 0, 0);
            foreach (var sp in spheres) s.Sphere(GILit(s, new Color(0.8f, 0.8f, 0.8f), 0, 0.3f), (Vector3)sp, sp.w * 2);
            s.SunDir(55, -30, 0.5f);
            s.Background(new Color(0.16f, 0.17f, 0.19f));
            s.LookAt(new Vector3(0.2f, 3.0f, -3.0f), new Vector3(0.05f, 0.1f, 0.1f), 40);
        }

        // ---------------- 8.5 粗糙度 → mip ----------------
        [BookShot("ch08-roughness-mip", W = 960, H = 400)]
        static void RoughnessMip(Shot s)
        {
            UseEnvironment(s, EnvironmentTools.Studio, false);
            s.Background(new Color(0.1f, 0.1f, 0.11f));
            for (int row = 0; row < 2; row++)
                for (int i = 0; i < 6; i++)
                {
                    var m = s.Mat("Cookbook/Ch08/EnvReflection");
                    m.SetFloat("_Roughness", i / 5f);
                    m.SetFloat("_Mode", row == 0 ? 2 : 1);
                    s.Sphere(m, new Vector3((i - 2.5f) * 1.12f, row == 0 ? 1.15f : 0f, 0), 1f);
                }
            s.Cam.orthographic = true;
            s.Cam.orthographicSize = 1.45f;
            s.Cam.transform.position = new Vector3(0, 0.575f, -10);
            s.Cam.transform.rotation = Quaternion.identity;
        }

        // ---------------- 8.5 自定义环境反射 cubemap ----------------
        [BookShot("ch08-custom-cubemap", W = 640, H = 480, Panels = 3)]
        static void CustomCubemap(Shot s)
        {
            if (s.Panel == 1) { UseEnvironment(s, EnvironmentTools.Studio); s.SunDir(50, -30, 0.0f); }
            if (s.Panel == 2)
            {
                UseEnvironment(s, EnvironmentTools.Sunset);
                s.Sun.transform.rotation = Quaternion.LookRotation(-new Vector3(0.75f, 0.08f, 0.65f).normalized);
                s.Sun.color = new Color(1f, 0.6f, 0.3f); s.Sun.intensity = 1.2f;
            }
            s.Knot(GILit(s, new Color(0.95f, 0.95f, 0.95f), 1, 0.95f), new Vector3(0, 0.95f, 0.3f), 0.8f);
            s.Sphere(GILit(s, new Color(0.95f, 0.75f, 0.45f), 1, 0.55f), new Vector3(-1.15f, 0.45f, -0.4f), 0.9f);
            s.Sphere(GILit(s, new Color(0.7f, 0.08f, 0.06f), 0, 0.85f), new Vector3(1.15f, 0.45f, -0.4f), 0.9f);
            var ground = s.Quad(GILit(s, new Color(0.25f, 0.25f, 0.26f), 0, 0.6f), Vector3.zero);
            ground.transform.rotation = Quaternion.Euler(90, 0, 0); ground.transform.localScale = new Vector3(5, 5, 1);
            s.LookAt(new Vector3(0, 1.6f, -4.2f), new Vector3(0, 0.6f, 0), 36);
        }

        // ---------------- 8.6 盒体投影 ----------------
        [BookShot("ch08-box-projection", W = 640, H = 480, Panels = 2)]
        static void BoxProjection(Shot s)
        {
            var probePos = new Vector3(0, 1.5f, 0);
            var cube = EnvironmentTools.BakeCubemap(d => BoxProjectionDemo.RoomRadiance(probePos, d), 256, 24);
            s.Temp.Add(cube);
            var wall = s.Mat("Cookbook/Ch08/RoomWall");
            // 四面墙 + 天花板，法线朝房间内
            void Face(Vector3 pos, Vector3 euler, Vector2 size)
            {
                var q = s.Quad(wall, pos); q.transform.rotation = Quaternion.Euler(euler); q.transform.localScale = new Vector3(size.x, size.y, 1);
            }
            Face(new Vector3(3, 1.5f, 0), new Vector3(0, 90, 0), new Vector2(6, 3));
            Face(new Vector3(-3, 1.5f, 0), new Vector3(0, -90, 0), new Vector2(6, 3));
            Face(new Vector3(0, 1.5f, 3), new Vector3(0, 0, 0), new Vector2(6, 3));
            Face(new Vector3(0, 1.5f, -3), new Vector3(0, 180, 0), new Vector2(6, 3));
            Face(new Vector3(0, 3, 0), new Vector3(-90, 0, 0), new Vector2(6, 6));

            Material Refl(float reflectivity, Color baseColor, float rough)
            {
                var m = s.Mat("Cookbook/Ch08/BoxProjection");
                m.SetTexture("_Cube", cube);
                m.SetVector("_ProbePosition", probePos);
                m.SetVector("_BoxMin", BoxProjectionDemo.BoxMin);
                m.SetVector("_BoxMax", BoxProjectionDemo.BoxMax);
                m.SetFloat("_Reflectivity", reflectivity);
                m.SetColor("_BaseColor", baseColor);
                m.SetFloat("_Roughness", rough);
                if (s.Panel == 1) m.EnableKeyword("_BOX_PROJECTION"); else m.DisableKeyword("_BOX_PROJECTION");
                m.SetFloat("_UseBox", s.Panel);
                return m;
            }
            var floor = s.Quad(Refl(0.55f, new Color(0.08f, 0.08f, 0.09f), 0.04f), Vector3.zero);
            floor.transform.rotation = Quaternion.Euler(90, 0, 0); floor.transform.localScale = new Vector3(6, 6, 1);
            s.Sphere(Refl(1f, Color.black, 0.02f), new Vector3(1.4f, 0.55f, 1.2f), 1.1f);
            s.Sun.intensity = 0;
            s.LookAt(new Vector3(-2.3f, 1.55f, -2.5f), new Vector3(0.6f, 0.75f, 1.2f), 62);
        }

        // ---------------- 8.7 AO ----------------
        static void AddSSAO(Shot s)
        {
            // URP 14 的 ScreenSpaceAmbientOcclusion 是 internal 类，配图里用反射创建（项目里直接在 Renderer 上添加即可）
            var t = typeof(UniversalRendererData).Assembly.GetType("UnityEngine.Rendering.Universal.ScreenSpaceAmbientOcclusion");
            var f = (ScriptableRendererFeature)ScriptableObject.CreateInstance(t);
            f.name = "SSAO";
            s.Temp.Add(f);
            // 默认半径 0.035 米是给“室内小物件”尺度的；本图物体在 1 米量级，把半径调大
            var settingsField = t.GetField("m_Settings", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance);
            var settings = settingsField.GetValue(f);
            settings.GetType().GetField("Radius", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance).SetValue(settings, 0.25f);
            settings.GetType().GetField("Intensity", System.Reflection.BindingFlags.NonPublic | System.Reflection.BindingFlags.Instance).SetValue(settings, 1.2f);
            s.Renderer.rendererFeatures.Add(f);
            s.Renderer.SetDirty();
        }

        [BookShot("ch08-ao", W = 640, H = 480, Panels = 3)]
        static void AO(Shot s)
        {
            Material Wall()
            {
                var m = GILit(s, Color.white, 0, 0.3f);
                m.SetTexture("_BaseMap", s.CoreTex("bricks_albedo"));
                m.SetTextureScale("_BaseMap", new Vector2(2.5f, 1.8f));
                m.SetTexture("_BumpMap", s.CoreTex("bricks_normal")); m.EnableKeyword("_NORMALMAP");
                m.SetTexture("_OcclusionMap", s.CoreTex("bricks_mask"));
                if (s.Panel >= 1) m.EnableKeyword("_OCCLUSIONMAP");
                return m;
            }
            if (s.Panel == 2) AddSSAO(s);
            s.Floor();
            var w = s.Quad(Wall(), new Vector3(0, 1.25f, 0.6f)); w.transform.localScale = new Vector3(3.5f, 2.5f, 1);
            var box = GILit(s, new Color(0.8f, 0.78f, 0.74f), 0, 0.2f);
            s.Cube(box, new Vector3(-0.6f, 0.35f, 0.25f), 0.7f).transform.rotation = Quaternion.Euler(0, 20, 0);
            s.Sphere(box, new Vector3(0.55f, 0.4f, 0.1f), 0.8f);
            // 主光调暗，让环境光（AO 只作用于它）成为主角
            s.SunDir(35, 50, 0.3f);
            s.LookAt(new Vector3(-0.15f, 1.0f, -1.7f), new Vector3(0, 0.6f, 0.4f), 40);
        }

        // ---------------- 8.8 Matcap 对照 ----------------
        static Texture2D MakeMatcap(Shot s)
        {
            const int N = 256;
            var tex = new Texture2D(N, N, TextureFormat.RGBA32, false) { wrapMode = TextureWrapMode.Clamp, name = "Matcap" };
            var px = new Color[N * N];
            Vector3 key = new Vector3(-0.5f, 0.65f, 0.6f).normalized;   // 观察空间：左上前方的主光
            for (int y = 0; y < N; y++)
                for (int x = 0; x < N; x++)
                {
                    float u = (x + 0.5f) / N * 2 - 1, v = (y + 0.5f) / N * 2 - 1;
                    float rr = Mathf.Min(1f, u * u + v * v);
                    var n = new Vector3(u, v, Mathf.Sqrt(1 - rr));
                    float diff = Mathf.Max(0, Vector3.Dot(n, key));
                    var h = (key + Vector3.forward).normalized;   // 观察方向 = +z（指向相机）
                    float spec = Mathf.Pow(Mathf.Max(0, Vector3.Dot(n, h)), 60f);
                    float rim = Mathf.Pow(1 - n.z, 3f);
                    Color c = new Color(0.12f, 0.1f, 0.1f) + new Color(0.78f, 0.45f, 0.3f) * diff + Color.white * spec * 0.9f + new Color(0.3f, 0.55f, 0.9f) * rim * 0.8f;
                    c.a = 1;
                    px[y * N + x] = c;
                }
            tex.SetPixels(px); tex.Apply();
            s.Temp.Add(tex);
            return tex;
        }

        [BookShot("ch08-matcap", W = 640, H = 480, Panels = 3)]
        static void Matcap(Shot s)
        {
            Material m;
            if (s.Panel < 2)
            {
                m = s.Mat("Cookbook/Ch08/Matcap");
                m.SetTexture("_MatCap", MakeMatcap(s));
            }
            else m = GILit(s, new Color(0.85f, 0.5f, 0.35f), 0, 0.75f);
            s.Floor();
            s.Knot(m, new Vector3(0, 0.95f, 0), 0.85f);
            s.SunDir(40, -60, 1.2f);
            // 第 1 格：正面；第 2、3 格：相机绕到另一侧
            if (s.Panel == 0) s.LookAt(new Vector3(0, 1.6f, -3.6f), new Vector3(0, 0.9f, 0), 36);
            else s.LookAt(new Vector3(3.1f, 1.6f, 1.8f), new Vector3(0, 0.9f, 0), 36);
        }

        // ---------------- 8.9 GILit vs URP Lit ----------------
        [BookShot("ch08-gilit-vs-lit", W = 960, H = 300, Panels = 2)]
        static void GILitVsLit(Shot s)
        {
            float[] metal = { 0, 0, 0, 1, 1 };
            float[] smooth = { 0.2f, 0.6f, 0.9f, 0.5f, 0.9f };
            Color[] col = { new Color(0.8f, 0.2f, 0.15f), new Color(0.2f, 0.5f, 0.8f), new Color(0.9f, 0.9f, 0.9f), new Color(0.95f, 0.7f, 0.4f), new Color(0.9f, 0.9f, 0.92f) };
            s.Floor();
            s.SphereRow(5, i => s.Panel == 0 ? s.Lit(col[i], metal[i], smooth[i]) : GILit(s, col[i], metal[i], smooth[i]), 0.5f, 0, 1.15f, 1f);
            s.LookAt(new Vector3(0, 1.3f, -4.6f), new Vector3(0, 0.45f, 0), 30);
        }

        // ---------------- 8.9 拆分 GI 各分量 ----------------
        [BookShot("ch08-gi-split", W = 480, H = 420, Panels = 4)]
        static void GISplit(Shot s)
        {
            int[] views = { 3, 1, 2, 0 };   // 直接光 / 间接漫反射 / 间接高光 / 合成
            s.Floor(GILitFloor(s, views[s.Panel]));
            var a = GILit(s, new Color(0.9f, 0.55f, 0.3f), 0, 0.7f); a.SetFloat("_DebugView", views[s.Panel]);
            var b = GILit(s, new Color(0.95f, 0.95f, 0.97f), 1, 0.85f); b.SetFloat("_DebugView", views[s.Panel]);
            s.Knot(a, new Vector3(-0.45f, 0.9f, 0.2f), 0.7f);
            s.Sphere(b, new Vector3(0.75f, 0.45f, -0.3f), 0.9f);
            s.SunDir(45, -35, 1.3f);
            s.LookAt(new Vector3(0, 1.5f, -3.6f), new Vector3(0.1f, 0.6f, 0), 36);
        }

        static Material GILitFloor(Shot s, int view)
        {
            var m = GILit(s, new Color(0.7f, 0.7f, 0.7f), 0, 0.15f);
            m.SetTexture("_BaseMap", s.CoreTex("checker"));
            m.SetTextureScale("_BaseMap", new Vector2(7.5f, 7.5f));
            m.SetFloat("_DebugView", view);
            return m;
        }
    }
}
