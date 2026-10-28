// 第 1 章配图：坐标空间、法线、深度、插值
using Cookbook.Core;
using UnityEngine;
using UnityEngine.Rendering.Universal;

namespace Cookbook.Ch01
{
    static class Ch01Shots
    {
        // 三个形状各异、带旋转和非均匀缩放的物体 + 地面，全部用同一个调试材质
        static void SpaceScene(Shot s, Material m)
        {
            s.Floor(m);
            var cube = s.Cube(m, new Vector3(-1.55f, 0.5f, 0.5f));
            cube.transform.rotation = Quaternion.Euler(0, 35, 0);
            s.Sphere(m, new Vector3(0, 0.6f, 0), 1.2f);
            var cyl = s.Cylinder(m, new Vector3(1.55f, 0.75f, 0.4f));
            cyl.transform.localScale = new Vector3(0.8f, 0.75f, 0.8f);
            cyl.transform.rotation = Quaternion.Euler(0, 0, -15);
            s.LookAt(new Vector3(0.3f, 2.3f, -5.2f), new Vector3(0, 0.5f, 0.6f), 40);
        }

        [BookShot("ch01-spaces", W = 640, H = 420, Panels = 3)]
        static void Spaces(Shot s)
        {
            var m = s.Mat("Cookbook/Ch01/SpaceViz");
            m.SetFloat("_Mode", s.Panel);          // 0 物体 / 1 世界 / 2 观察
            m.SetFloat("_GridSize", s.Panel == 0 ? 1f : 0.5f);
            m.SetFloat("_DepthScale", 10f);
            SpaceScene(s, m);
        }

        [BookShot("ch01-ndc", W = 640, H = 420, Panels = 3)]
        static void Ndc(Shot s)
        {
            var m = s.Mat("Cookbook/Ch01/SpaceViz");
            m.SetFloat("_Mode", 3 + s.Panel);      // 3 NDC / 4 裁剪空间 w / 5 像素坐标
            m.SetFloat("_DepthScale", 12f);
            m.SetFloat("_PixelCell", 40f);
            SpaceScene(s, m);
        }

        static void NormalScene(Shot s, Material m)
        {
            s.Floor(m);
            var cube = s.Cube(m, new Vector3(-1.6f, 0.62f, 0.5f), 0.9f);
            cube.transform.rotation = Quaternion.Euler(25, 40, 15);
            var knot = s.Knot(m, new Vector3(0.05f, 0.95f, 0.2f), 0.85f);
            knot.transform.rotation = Quaternion.Euler(70, 20, 0);
            s.Sphere(m, new Vector3(1.65f, 0.55f, 0.4f), 1.1f);
            s.LookAt(new Vector3(0.2f, 2.2f, -4.8f), new Vector3(0, 0.6f, 0.4f), 40);
        }

        [BookShot("ch01-normals", W = 640, H = 420, Panels = 3)]
        static void Normals(Shot s)
        {
            var m = s.Mat("Cookbook/Ch01/NormalViz");
            m.SetFloat("_Mode", s.Panel);          // 0 物体空间 / 1 世界空间 / 2 观察空间
            NormalScene(s, m);
        }

        [BookShot("ch01-normal-scale", W = 640, H = 420, Panels = 3)]
        static void NormalScale(Shot s)
        {
            int[] modes = { 4, 3, 5 };              // 错误 / 正确 / 差异×4
            var m = s.Mat("Cookbook/Ch01/NormalViz");
            m.SetFloat("_Mode", modes[s.Panel]);
            m.SetColor("_BaseColor", new Color(0.9f, 0.88f, 0.85f));
            var floor = s.Lit(new Color(0.35f, 0.37f, 0.4f), 0, 0.1f);
            s.Floor(floor);
            var sph = s.Sphere(m, new Vector3(-0.9f, 0.55f, 0.2f));
            sph.transform.localScale = new Vector3(2.0f, 0.7f, 0.9f);   // 压扁、拉长的球
            sph.transform.rotation = Quaternion.Euler(0, 30, 0);
            var knot = s.Knot(m, new Vector3(1.3f, 0.75f, 0.4f));
            knot.transform.localScale = new Vector3(0.55f, 1.15f, 0.55f); // 竖向拉长的纽结
            knot.transform.rotation = Quaternion.Euler(0, 20, 0);
            s.SunDir(35, -70, 1.4f);
            s.Background(new Color(0.16f, 0.18f, 0.21f));
            s.LookAt(new Vector3(0.2f, 2.0f, -4.6f), new Vector3(0.1f, 0.6f, 0.3f), 38);
        }

        [BookShot("ch01-depth", W = 640, H = 400, Panels = 3)]
        static void Depth(Shot s)
        {
            // 深度纹理要在“透明物体之前”拷贝出来，DepthViz 才能读到当前帧的深度
            s.Renderer.copyDepthMode = CopyDepthMode.AfterOpaques;
            s.Cam.nearClipPlane = 0.3f;    // Unity 新建相机的默认值
            s.Cam.farClipPlane = 40f;

            s.Floor();
            for (int i = 0; i < 8; i++)
            {
                float z = i * 4f;
                s.Cube(s.Lit(new Color(0.8f, 0.5f, 0.3f)), new Vector3(-2.2f, 1.25f, z)).transform.localScale = new Vector3(0.6f, 2.5f, 0.6f);
                s.Cube(s.Lit(new Color(0.3f, 0.55f, 0.8f)), new Vector3(2.2f, 1.25f, z + 2f)).transform.localScale = new Vector3(0.6f, 2.5f, 0.6f);
            }
            s.Sphere(s.Lit(new Color(0.9f, 0.9f, 0.9f)), new Vector3(-0.5f, 0.5f, 1.0f), 1.0f);
            s.Sphere(s.Lit(new Color(0.9f, 0.9f, 0.9f)), new Vector3(0.6f, 0.8f, 8f), 1.6f);
            s.LookAt(new Vector3(0, 1.6f, -3.0f), new Vector3(0, 1.0f, 10f), 55);

            var m = s.Mat("Cookbook/Ch01/DepthViz");
            m.SetFloat("_Mode", s.Panel);          // 0 原始 / 1 Linear01 / 2 Eye 色带
            m.SetFloat("_BandWidth", 1f);
            m.SetFloat("_EyeMax", 30f);
            // 全屏四边形：顶点着色器会无视它的位置，但它的包围盒必须在视锥内，否则会被 CPU 剔除
            var q = s.Quad(m, s.Cam.transform.position + s.Cam.transform.forward * 2f);
            q.transform.rotation = s.Cam.transform.rotation;
        }

        [BookShot("ch01-interp", W = 640, H = 420, Panels = 2)]
        static void Interp(Shot s)
        {
            var m = s.Mat("Cookbook/Ch01/PerspectiveInterp");
            m.SetTexture("_MainTex", s.CoreTex("uv_grid"));
            m.SetFloat("_Tiling", 2f);
            m.SetFloat("_Affine", s.Panel);        // 0 透视校正 / 1 仿射
            // 只有两个三角形的大平面：三角形越大、深度跨度越大，仿射插值的错误越明显
            s.MeshObj(Meshes.Grid(8f, 1), m, Vector3.zero, 1f, "BigQuad");
            var wall = s.MeshObj(Meshes.Grid(3f, 1), m, new Vector3(3.0f, 1.5f, 1.8f), 1f, "Wall");
            wall.transform.rotation = Quaternion.Euler(-90, 40, 0);   // 一面斜对着相机的墙，同样只有两个三角形
            s.Background(new Color(0.2f, 0.22f, 0.25f));
            s.LookAt(new Vector3(-0.6f, 1.5f, -5.2f), new Vector3(0.3f, 0.2f, 0.5f), 50);
        }

        [BookShot("ch01-screenuv", W = 640, H = 420, Panels = 3)]
        static void ScreenUv(Shot s)
        {
            var m = s.Mat("Cookbook/Ch01/ScreenUV");
            m.SetFloat("_Mode", s.Panel);          // 0 片元里除 / 1 顶点里除（错）/ 2 顶点里除 + noperspective
            m.SetFloat("_Cells", 9f);
            s.MeshObj(Meshes.Grid(10f, 1), m, Vector3.zero, 1f, "BigQuad");
            var cube = s.Cube(m, new Vector3(0.8f, 0.9f, 1.2f), 1.8f);
            cube.transform.rotation = Quaternion.Euler(0, 40, 0);
            s.Background(new Color(0.2f, 0.22f, 0.25f));
            s.LookAt(new Vector3(-0.8f, 1.6f, -4.6f), new Vector3(0.3f, 0.5f, 0.8f), 50);
        }
    }
}
