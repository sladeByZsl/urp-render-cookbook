// 第 22 章配图
using System.Collections.Generic;
using Cookbook.Core;
using UnityEditor;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch22
{
    static class Ch22Shots
    {
        //#region addDecalFeature
        // DecalRendererFeature 及其设置类在 URP 14 里是 internal 的：编辑器里在 Renderer 资源上点 Add Renderer Feature › Decal 即可；
        // 代码里只能用反射创建，再通过 SerializedObject 改它的序列化字段（与 Inspector 改的是同一份数据）。
        // technique: 0 Automatic / 1 DBuffer / 2 ScreenSpace；surfaceData: 0 Albedo / 1 AlbedoNormal / 2 AlbedoNormalMAOS
        static ScriptableRendererFeature AddDecalFeature(Shot s, int technique, int surfaceData = 2, int normalBlend = 1)
        {
            var type = typeof(ScriptableRendererFeature).Assembly.GetType("UnityEngine.Rendering.Universal.DecalRendererFeature");
            var feature = (ScriptableRendererFeature)ScriptableObject.CreateInstance(type);
            feature.name = "Decal";
            var so = new SerializedObject(feature);
            so.FindProperty("m_Settings.technique").enumValueIndex = technique;
            so.FindProperty("m_Settings.dBufferSettings.surfaceData").enumValueIndex = surfaceData;
            so.FindProperty("m_Settings.screenSpaceSettings.normalBlend").enumValueIndex = normalBlend;
            so.ApplyModifiedPropertiesWithoutUndo();
            s.Temp.Add(feature);
            s.Renderer.rendererFeatures.Add(feature);
            s.Renderer.SetDirty();
            return feature;
        }
        //#endregion

        //#region urpDecal
        static Material UrpDecalMat(Shot s, Texture2D baseMap, Texture2D normal = null, bool angleFadeGraph = false)
        {
            // URP 包自带的 Decal Shader Graph（Packages/.../Shaders/Decal.shadergraph），属性：Base_Map / Normal_Map / Normal_Blend
            var m = s.Mat(angleFadeGraph ? "Cookbook/Ch22/DecalAngleFade" : "Shader Graphs/Decal");
            m.SetTexture("Base_Map", baseMap);
            if (normal != null) { m.SetTexture("Normal_Map", normal); m.SetFloat("Normal_Blend", 1f); }
            else m.SetFloat("Normal_Blend", 0f);
            m.enableInstancing = true;    // Decal 系统按材质分批用 GPU Instancing 绘制
            return m;
        }

        static DecalProjector UrpDecal(Material m, Vector3 pos, Vector3 euler, Vector3 size, float opacity = 1f)
        {
            var go = new GameObject("Decal Projector");
            go.transform.SetPositionAndRotation(pos, Quaternion.Euler(euler));
            var d = go.AddComponent<DecalProjector>();
            d.material = m;
            d.size = size;                          // x/y = 贴花宽高，z = 投影深度
            d.pivot = new Vector3(0, 0, size.z * 0.5f);  // 默认：盒子从投影器位置向前延伸
            d.fadeFactor = opacity;
            return d;
        }
        //#endregion

        // ---------- 场景素材 ----------
        static Material Concrete(Shot s, float tile = 6f)
        {
            var m = s.Lit(new Color(0.95f, 0.95f, 0.95f), 0, 0.2f);
            m.SetTexture("_BaseMap", DecalTextures.Concrete);
            m.SetTextureScale("_BaseMap", new Vector2(tile, tile));
            return m;
        }
        static Material Brick(Shot s, float tile = 2f)
        {
            var m = s.Lit(Color.white, 0, 0.2f);
            m.SetTexture("_BaseMap", s.CoreTex("bricks_albedo"));
            m.SetTexture("_BumpMap", s.CoreTex("bricks_normal"));
            m.EnableKeyword("_NORMALMAP");
            m.SetTextureScale("_BaseMap", new Vector2(tile, tile));
            return m;
        }
        static GameObject Box(Shot s, Material m, Vector3 pos, Vector3 size, float yaw = 0)
        {
            var c = s.Cube(m, pos);
            c.transform.localScale = size;
            c.transform.rotation = Quaternion.Euler(0, yaw, 0);
            return c;
        }
        static void Stairs(Shot s, Material m, Vector3 origin, int steps = 3)
        {
            for (int i = 0; i < steps; i++)
                Box(s, m, origin + new Vector3(0, 0.15f + i * 0.15f, i * 0.45f), new Vector3(2.4f, 0.3f + i * 0.3f, 0.45f));
        }

        /// 用 12 根细棍画出盒子的线框（示意投影体）
        static void BoxGizmo(Shot s, Transform t, Color c, float w = 0.015f)
        {
            var m = s.Mat("Universal Render Pipeline/Unlit");
            m.SetColor("_BaseColor", c);
            for (int axis = 0; axis < 3; axis++)
                for (int a = -1; a <= 1; a += 2)
                    for (int b = -1; b <= 1; b += 2)
                    {
                        var local = new Vector3();
                        int i1 = (axis + 1) % 3, i2 = (axis + 2) % 3;
                        local[i1] = a * 0.5f; local[i2] = b * 0.5f;
                        var p = t.TransformPoint(local);
                        var dir = t.TransformVector(Vector3.zero.With(axis, 1f));
                        var stick = s.Cube(m, p);
                        stick.transform.rotation = Quaternion.LookRotation(dir.normalized, Mathf.Abs(Vector3.Dot(dir.normalized, Vector3.up)) > 0.9f ? Vector3.forward : Vector3.up);
                        stick.transform.localScale = new Vector3(w, w, dir.magnitude);
                        stick.GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.Off;
                    }
        }
        static Vector3 With(this Vector3 v, int i, float x) { v[i] = x; return v; }

        // ---------------------------------------------------------------- 22.1
        [BookShot("ch22-urp-decal", W = 960, H = 520)]
        static void UrpDecalShot(Shot s)
        {
            AddDecalFeature(s, 1);
            s.Floor(Concrete(s, 10), 20);
            var stone = Concrete(s, 1.5f);
            Stairs(s, stone, new Vector3(-0.6f, 0, 0.6f));
            var crate = Box(s, s.Lit(new Color(0.55f, 0.42f, 0.28f), 0, 0.3f), new Vector3(1.9f, 0.45f, -0.1f), new Vector3(0.9f, 0.9f, 0.9f), -20);
            // 警示条纹：从正上方投到台阶边缘，覆盖踏面与竖直的踢面
            UrpDecal(UrpDecalMat(s, DecalTextures.Hazard), new Vector3(-0.6f, 1.6f, 0.75f), new Vector3(90, 0, 0), new Vector3(1.8f, 1.0f, 2f));
            // 地面箭头
            UrpDecal(UrpDecalMat(s, DecalTextures.Arrow), new Vector3(-0.4f, 0.5f, -1.0f), new Vector3(90, 0, 0), new Vector3(0.9f, 1.3f, 1f), 0.9f);
            // 箱子侧面的弹孔（带法线），投影器水平朝向箱子
            var holeMat = UrpDecalMat(s, DecalTextures.BulletHole, DecalTextures.BulletHoleNormal);
            var fwd = crate.transform.forward;   // 箱子 -Z 面朝向相机一侧
            var face = crate.transform.position - fwd * 0.45f;
            foreach (var o in new[] { new Vector2(-0.18f, 0.12f), new Vector2(0.15f, -0.1f), new Vector2(0.05f, 0.25f) })
            {
                var p = face + crate.transform.right * o.x + Vector3.up * o.y - fwd * 0.2f;
                UrpDecal(holeMat, p, crate.transform.rotation.eulerAngles, new Vector3(0.28f, 0.28f, 0.4f));
            }
            // 血迹：地面
            UrpDecal(UrpDecalMat(s, DecalTextures.Blood), new Vector3(1.2f, 0.5f, -1.1f), new Vector3(90, 30, 0), new Vector3(1.1f, 1.1f, 1f), 0.95f);
            s.SunDir(48, -35, 1.4f);
            s.LookAt(new Vector3(0.2f, 2.5f, -3.9f), new Vector3(0.3f, 0.35f, 0.2f), 50);
        }

        // ---------------------------------------------------------------- 22.2
        [BookShot("ch22-dbuffer-vs-ss", W = 640, H = 420, Panels = 2)]
        static void DBufferVsSS(Shot s)
        {
            AddDecalFeature(s, s.Panel == 0 ? 1 : 2);
            s.Floor(Concrete(s, 10), 20);
            var wall = Box(s, Brick(s, 1.5f), new Vector3(0, 1.2f, 1.0f), new Vector3(3f, 2.4f, 0.3f));
            var holeMat = UrpDecalMat(s, DecalTextures.BulletHole, DecalTextures.BulletHoleNormal);
            var rnd = new System.Random(3);
            for (int i = 0; i < 7; i++)
            {
                var p = new Vector3(-0.9f + (float)rnd.NextDouble() * 1.8f, 0.7f + (float)rnd.NextDouble() * 1.2f, 0.6f);
                UrpDecal(holeMat, p, Vector3.zero, new Vector3(0.32f, 0.32f, 0.5f));
            }
            UrpDecal(UrpDecalMat(s, DecalTextures.Hazard), new Vector3(0, 0.6f, 0.2f), new Vector3(90, 0, 0), new Vector3(1.8f, 0.6f, 1f));
            s.Point(new Vector3(0.9f, 1.6f, 0.2f), new Color(1f, 0.8f, 0.6f), 1.5f, 3f);
            s.SunDir(35, -60, 1.2f);
            s.LookAt(new Vector3(0.4f, 1.5f, -2.6f), new Vector3(0, 1.0f, 0.8f), 48);
        }

        // ---------------------------------------------------------------- 22.3
        [BookShot("ch22-urp-anglefade", W = 640, H = 420, Panels = 2)]
        static void UrpAngleFade(Shot s)
        {
            AddDecalFeature(s, 1);
            s.Floor(Concrete(s, 10), 20);
            var white = s.Lit(new Color(0.75f, 0.75f, 0.75f), 0, 0.3f);
            Box(s, white, new Vector3(-0.5f, 0.35f, 0.3f), new Vector3(0.8f, 0.7f, 0.8f), 30);
            s.Sphere(white, new Vector3(0.75f, 0.45f, 0.1f), 0.9f);
            var m = UrpDecalMat(s, s.CoreTex("uv_grid"), null, s.Panel == 1);
            var d = UrpDecal(m, new Vector3(0.1f, 1.6f, 0.2f), new Vector3(90, 0, 0), new Vector3(2.6f, 1.6f, 2.0f));
            if (s.Panel == 1) { d.startAngleFade = 40f; d.endAngleFade = 70f; }
            s.SunDir(50, -30, 1.3f);
            s.LookAt(new Vector3(0, 1.7f, -2.6f), new Vector3(0.1f, 0.35f, 0.2f), 45);
        }

        // ---------------------------------------------------------------- 22.4 – 22.7 自写屏幕空间贴花
        static Material SSDMat(Shot s, Texture2D tex, Texture2D normal = null, bool lit = true)
        {
            var m = s.Mat("Cookbook/Ch22/ScreenSpaceDecal");
            m.SetTexture("_BaseMap", tex);
            if (normal != null) { m.SetTexture("_BumpMap", normal); m.EnableKeyword("_NORMALMAP"); }
            if (lit) m.EnableKeyword("_DECAL_LIT"); else m.DisableKeyword("_DECAL_LIT");
            m.enableInstancing = true;
            return m;
        }

        //#region ssdObject
        /// 屏幕空间贴花就是一个挂着贴花材质的单位立方体：位置/旋转/缩放 = 投影盒
        static GameObject SSD(Shot s, Material m, Vector3 pos, Vector3 euler, Vector3 size)
        {
            var go = s.Cube(m, pos);
            go.name = "Screen Space Decal";
            go.transform.rotation = Quaternion.Euler(euler);
            go.transform.localScale = size;
            var r = go.GetComponent<MeshRenderer>();
            r.shadowCastingMode = ShadowCastingMode.Off;   // 投影盒本身不投影、不接收
            r.receiveShadows = false;
            return go;
        }
        //#endregion

        static void SSDScene(Shot s)
        {
            s.Floor(Concrete(s, 10), 20);
            var white = s.Lit(new Color(0.7f, 0.7f, 0.72f), 0, 0.3f);
            Box(s, white, new Vector3(-0.3f, 0.35f, 0.4f), new Vector3(0.7f, 0.7f, 0.7f), 25);
            s.Sphere(white, new Vector3(0.75f, 0.35f, 0.2f), 0.7f);
            s.SunDir(50, -30, 1.3f);
            s.LookAt(new Vector3(0.2f, 1.9f, -2.5f), new Vector3(0.15f, 0.3f, 0.3f), 45);
        }

        [BookShot("ch22-ssd-steps", W = 640, H = 420, Panels = 3)]
        static void SSDSteps(Shot s)
        {
            SSDScene(s);
            var m = SSDMat(s, DecalTextures.Hazard);
            m.SetFloat("_Debug", s.Panel == 0 ? 1 : (s.Panel == 1 ? 2 : 0));
            m.SetFloat("_AngleStart", 89f); m.SetFloat("_AngleEnd", 90f);
            var box = SSD(s, m, new Vector3(0.1f, 0.5f, 0.3f), new Vector3(90, 0, 0), new Vector3(1.6f, 1.2f, 1.2f));
            if (s.Panel < 2) BoxGizmo(s, box.transform, new Color(1f, 0.85f, 0.2f));
        }

        [BookShot("ch22-ssd-anglefade", W = 640, H = 420, Panels = 3)]
        static void SSDAngleFade(Shot s)
        {
            SSDScene(s);
            var m = SSDMat(s, s.CoreTex("uv_grid"));
            if (s.Panel == 0) m.SetFloat("_Debug", 3);
            if (s.Panel == 1) { m.SetFloat("_AngleStart", 89f); m.SetFloat("_AngleEnd", 90f); }
            if (s.Panel == 2) { m.SetFloat("_AngleStart", 40f); m.SetFloat("_AngleEnd", 70f); }
            SSD(s, m, new Vector3(0.1f, 0.5f, 0.3f), new Vector3(90, 0, 0), new Vector3(1.6f, 1.2f, 1.2f));
        }

        [BookShot("ch22-ssd-lit", W = 640, H = 420, Panels = 2)]
        static void SSDLit(Shot s)
        {
            s.Floor(Concrete(s, 10), 20);
            Box(s, s.Lit(new Color(0.6f, 0.6f, 0.62f), 0, 0.3f), new Vector3(-0.6f, 0.6f, 0.6f), new Vector3(0.5f, 1.2f, 0.5f));
            var m = SSDMat(s, DecalTextures.Hazard, null, s.Panel == 1);
            SSD(s, m, new Vector3(0.0f, 0.1f, 0.0f), new Vector3(90, 0, 0), new Vector3(1.4f, 1.4f, 0.6f));
            s.SunDir(32, 135, 1.5f);     // 让柱子的影子斜穿过贴花
            s.LookAt(new Vector3(0.3f, 1.8f, -2.3f), new Vector3(0, 0, 0.1f), 45);
        }

        // ---------------------------------------------------------------- 22.8 – 22.9 网格贴花
        static Material MeshDecalMat(Shot s, Texture2D tex, Texture2D normal = null)
        {
            var m = s.Mat("Cookbook/Ch22/MeshDecal");
            m.SetTexture("_BaseMap", tex);
            if (normal != null) { m.SetTexture("_BumpMap", normal); m.EnableKeyword("_NORMALMAP"); }
            return m;
        }

        [BookShot("ch22-meshdecal-zfight", W = 640, H = 400, Panels = 2)]
        static void MeshDecalZFight(Shot s)
        {
            // 一块倾斜的细分地面（三角形划分与贴花 Quad 不同），贴花 Quad 作为它的子物体放在同一平面上
            var ground = s.Grid(Concrete(s, 10), Vector3.zero, 30f, 60);
            ground.transform.rotation = Quaternion.Euler(-6, 20, 3);
            var m = MeshDecalMat(s, DecalTextures.HazardClean);
            m.SetTextureScale("_BaseMap", new Vector2(2, 6));
            if (s.Panel == 0) { m.SetFloat("_OffsetFactor", 0); m.SetFloat("_OffsetUnits", 0); }
            var q = s.Quad(m, Vector3.zero, 1f);
            q.transform.SetParent(ground.transform, false);
            q.transform.localPosition = new Vector3(0.37f, 0, 6.13f);
            q.transform.localRotation = Quaternion.Euler(90, 0, 0);
            q.transform.localScale = new Vector3(4f, 10f, 1f);
            s.SunDir(50, -30, 1.3f);
            var target = q.transform.position;
            s.LookAt(target + new Vector3(-1.5f, 1.2f, -9f), target, 30);
        }

        [BookShot("ch22-meshdecal-clip", W = 640, H = 440, Panels = 2)]
        static void MeshDecalClip(Shot s)
        {
            s.Floor(Concrete(s, 10), 20);
            var white = s.Lit(new Color(0.75f, 0.74f, 0.72f), 0, 0.35f);
            var sphere = s.Sphere(white, new Vector3(-0.85f, 0.55f, 0.2f), 1.1f);
            var cyl = s.Cylinder(white, new Vector3(0.8f, 0.6f, 0.3f), 1);
            cyl.transform.localScale = new Vector3(0.9f, 0.6f, 0.9f);

            var targets = new List<MeshFilter> { sphere.GetComponent<MeshFilter>(), cyl.GetComponent<MeshFilter>() };
            //#region buildMeshDecal
            // 投影盒：一个空物体的 Transform（也可以直接用 DecalProjector 所在的物体）
            var boxGo = new GameObject("Decal Box");
            boxGo.transform.SetPositionAndRotation(new Vector3(-0.85f, 0.65f, -0.5f), Quaternion.identity);   // 沿 +Z 朝球投影
            boxGo.transform.localScale = new Vector3(0.8f, 0.8f, 1.0f);
            var mesh = DecalMeshBuilder.Build(boxGo.transform, targets, 80f, 0.002f);
            //#endregion
            var hazardMat = MeshDecalMat(s, DecalTextures.Hazard);
            if (s.Panel == 0) hazardMat.SetFloat("_DebugColor", 1);
            s.MeshObj(mesh, hazardMat, Vector3.zero, 1, "Decal Mesh").GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.Off;

            // 圆柱上的一组弹孔
            var holeMat = MeshDecalMat(s, DecalTextures.BulletHole, DecalTextures.BulletHoleNormal);
            if (s.Panel == 0) holeMat.SetFloat("_DebugColor", 1);
            foreach (var p in new[] { new Vector3(0.7f, 0.75f, -0.3f), new Vector3(0.95f, 0.45f, -0.3f), new Vector3(0.62f, 0.35f, -0.3f) })
            {
                var hb = new GameObject("Hole Box");
                hb.transform.SetPositionAndRotation(p, Quaternion.identity);
                hb.transform.localScale = new Vector3(0.3f, 0.3f, 0.6f);
                var hm = DecalMeshBuilder.Build(hb.transform, targets, 80f, 0.002f);
                s.MeshObj(hm, holeMat, Vector3.zero, 1, "Hole Mesh").GetComponent<MeshRenderer>().shadowCastingMode = ShadowCastingMode.Off;
                if (s.Panel == 0) BoxGizmo(s, hb.transform, new Color(1f, 0.85f, 0.2f), 0.008f);
            }
            if (s.Panel == 0) BoxGizmo(s, boxGo.transform, new Color(1f, 0.85f, 0.2f), 0.01f);
            s.SunDir(40, -40, 1.3f);
            s.LookAt(new Vector3(0, 1.3f, -2.9f), new Vector3(0, 0.5f, 0.2f), 42);
        }

        // ---------------------------------------------------------------- 22.10 综合应用
        [BookShot("ch22-apps", W = 960, H = 540)]
        static void Apps(Shot s)
        {
            s.Floor(Concrete(s, 12), 24);
            Box(s, Brick(s, 2.5f), new Vector3(0, 1.5f, 2.0f), new Vector3(6f, 3f, 0.3f));
            var barrel = s.Cylinder(s.Lit(new Color(0.2f, 0.32f, 0.45f), 0.6f, 0.45f), new Vector3(1.9f, 0.55f, 1.2f), 1);
            barrel.transform.localScale = new Vector3(0.7f, 0.55f, 0.7f);

            // 墙上的弹孔：屏幕空间贴花 + 法线
            var hole = SSDMat(s, DecalTextures.BulletHole, DecalTextures.BulletHoleNormal);
            hole.SetFloat("_BumpScale", 1.5f);
            var rnd = new System.Random(9);
            for (int i = 0; i < 9; i++)
            {
                var p = new Vector3(-1.6f + (float)rnd.NextDouble() * 1.6f, 0.9f + (float)rnd.NextDouble() * 1.3f, 1.85f);
                float sz = 0.18f + (float)rnd.NextDouble() * 0.12f;
                SSD(s, hole, p, new Vector3(0, 0, (float)rnd.NextDouble() * 360), new Vector3(sz, sz, 0.3f));
            }
            // 地上一串脚印：同一个材质、很多个投影盒（可 GPU Instancing）
            var foot = SSDMat(s, DecalTextures.Footprint);
            for (int i = 0; i < 8; i++)
            {
                float z = -2.4f + i * 0.42f;
                float x = -0.2f + Mathf.Sin(i * 0.5f) * 0.25f + (i % 2 == 0 ? -0.13f : 0.13f);
                SSD(s, foot, new Vector3(x, 0, z), new Vector3(90, 8f * Mathf.Sin(i * 0.5f), 0), new Vector3(0.26f, 0.44f, 0.3f));
            }
            // 血迹：跨墙角，用角度衰减让它在墙面上自然收住
            var blood = SSDMat(s, DecalTextures.Blood);
            blood.SetFloat("_AngleStart", 55f); blood.SetFloat("_AngleEnd", 85f);
            SSD(s, blood, new Vector3(-1.1f, 0.1f, 1.45f), new Vector3(90, 20, 0), new Vector3(1.6f, 1.6f, 0.8f));
            // 地面喷漆箭头（URP Decal Projector，与自写贴花混用）
            AddDecalFeature(s, 1);
            UrpDecal(UrpDecalMat(s, DecalTextures.Arrow), new Vector3(1.0f, 0.5f, -0.8f), new Vector3(90, -35, 0), new Vector3(0.8f, 1.2f, 1f), 0.85f);
            // 油桶上的网格贴花（警示标签）
            var boxGo = new GameObject("Label Box");
            boxGo.transform.SetPositionAndRotation(new Vector3(1.9f, 0.6f, 0.6f), Quaternion.identity);
            boxGo.transform.localScale = new Vector3(0.5f, 0.35f, 0.8f);
            var label = DecalMeshBuilder.Build(boxGo.transform, new[] { barrel.GetComponent<MeshFilter>() }, 75f, 0.002f);
            s.MeshObj(label, MeshDecalMat(s, DecalTextures.Hazard), Vector3.zero, 1, "Label");

            s.SunDir(42, -25, 1.4f);
            s.LookAt(new Vector3(-0.2f, 1.9f, -3.6f), new Vector3(0.1f, 0.8f, 0.8f), 52);
        }
    }
}
