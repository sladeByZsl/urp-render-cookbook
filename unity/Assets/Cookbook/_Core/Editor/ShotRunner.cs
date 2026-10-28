// 批处理入口：编译检查本章所有 Shader，并渲染本章所有 [BookShot] 配图。
// Unity -batchmode -projectPath <工程> -executeMethod Cookbook.Core.ShotRunner.Run -chapters ch05,ch06 [-shot id] [-noshots] -outdir <目录> -quit
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Reflection;
using System.Text;
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using Object = UnityEngine.Object;

namespace Cookbook.Core
{
    public static class ShotRunner
    {
        static readonly List<string> Errors = new List<string>();
        static Cubemap s_Sky;

        static string Arg(string name, string def = null)
        {
            var a = Environment.GetCommandLineArgs();
            for (int i = 0; i < a.Length - 1; i++) if (a[i] == name) return a[i + 1];
            return def;
        }
        static bool Flag(string name) => Environment.GetCommandLineArgs().Contains(name);

        public static void Run()
        {
            int code = 0;
            try { code = RunInner(); }
            catch (Exception e) { Debug.LogError("[Cookbook] Runner crashed: " + e); code = 2; }
            EditorApplication.Exit(code);
        }

        static int RunInner()
        {
            var chapters = (Arg("-chapters", "") ?? "").ToLowerInvariant().Split(new[] { ',' }, StringSplitOptions.RemoveEmptyEntries);
            string onlyShot = Arg("-shot");
            string outDir = Arg("-outdir", Path.GetFullPath(Path.Combine(Application.dataPath, "../../src/img")));
            Directory.CreateDirectory(outDir);
            PlayerSettings.colorSpace = ColorSpace.Linear;
            ShaderUtil.allowAsyncCompilation = false;
            Application.logMessageReceived += OnLog;

            bool InChapters(string s) => chapters.Length == 0 || chapters.Any(c => s.ToLowerInvariant().Contains("/" + c) || s.ToLowerInvariant().StartsWith(c));

            // 1) Shader 编译检查
            var shaderPaths = AssetDatabase.FindAssets("t:Shader", new[] { "Assets/Cookbook" })
                .Select(AssetDatabase.GUIDToAssetPath).Where(p => InChapters(p)).ToList();
            foreach (var p in shaderPaths) CheckShader(p);
            Debug.Log($"[Cookbook] Checked {shaderPaths.Count} shaders");

            // 2) 渲染配图
            if (!Flag("-noshots"))
            {
                var shots = AppDomain.CurrentDomain.GetAssemblies()
                    .SelectMany(a => { try { return a.GetTypes(); } catch { return new Type[0]; } })
                    .SelectMany(t => t.GetMethods(BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic))
                    .Select(m => (m, attr: m.GetCustomAttribute<BookShotAttribute>()))
                    .Where(x => x.attr != null && InChapters(x.attr.Id) && (onlyShot == null || x.attr.Id == onlyShot))
                    .OrderBy(x => x.attr.Id).ToList();
                foreach (var (m, attr) in shots)
                {
                    try { RenderShot(m, attr, outDir); }
                    catch (Exception e) { Errors.Add($"SHOT {attr.Id}: {(e.InnerException ?? e).Message}\n{(e.InnerException ?? e).StackTrace}"); }
                }
                Debug.Log($"[Cookbook] Rendered {shots.Count} shots");
            }

            Application.logMessageReceived -= OnLog;
            var sb = new StringBuilder();
            foreach (var e in Errors.Distinct()) sb.AppendLine("COOKBOOK-ERROR " + e);
            sb.AppendLine($"COOKBOOK-SUMMARY errors={Errors.Distinct().Count()}");
            Debug.Log(sb.ToString());
            File.WriteAllText(Path.Combine(outDir, "_last_report.txt"), sb.ToString());
            return Errors.Count > 0 ? 1 : 0;
        }

        static void OnLog(string msg, string stack, LogType type)
        {
            if (type == LogType.Error || type == LogType.Exception || type == LogType.Assert)
            {
                if (msg.StartsWith("[Licensing") || msg.Contains("Licensing::")) return;
                Errors.Add("LOG " + msg);
            }
        }

        static void CheckShader(string path)
        {
            var sh = AssetDatabase.LoadAssetAtPath<Shader>(path);
            if (sh == null) { Errors.Add("SHADER load failed " + path); return; }
            var mat = new Material(sh);
            for (int i = 0; i < mat.passCount; i++) ShaderUtil.CompilePass(mat, i, true);
            foreach (var m in ShaderUtil.GetShaderMessages(sh))
                if (m.severity == UnityEditor.Rendering.ShaderCompilerMessageSeverity.Error)
                    Errors.Add($"SHADER {path}:{m.line} {m.message} [{m.platform}] {m.messageDetails}");
            Object.DestroyImmediate(mat);
        }

        // ---------------- 渲染 ----------------
        static void RenderShot(MethodInfo method, BookShotAttribute attr, string outDir)
        {
            var panels = new List<Texture2D>();
            for (int p = 0; p < attr.Panels; p++)
            {
                EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
                var s = NewShot(p);
                method.Invoke(null, new object[] { s });
                panels.Add(Capture(s, attr.W, attr.H, attr.Hdr));
                foreach (var o in s.Temp) if (o != null) Object.DestroyImmediate(o);
            }
            const int gap = 8;
            int w = attr.W * panels.Count + gap * (panels.Count - 1);
            var outTex = new Texture2D(w, attr.H, TextureFormat.RGB24, false);
            var white = Enumerable.Repeat(new Color32(255, 255, 255, 255), w * attr.H).ToArray();
            outTex.SetPixels32(white);
            for (int i = 0; i < panels.Count; i++)
            {
                outTex.SetPixels(i * (attr.W + gap), 0, attr.W, attr.H, panels[i].GetPixels());
                Object.DestroyImmediate(panels[i]);
            }
            outTex.Apply();
            File.WriteAllBytes(Path.Combine(outDir, attr.Id + ".jpg"), outTex.EncodeToJPG(88));
            Object.DestroyImmediate(outTex);
            Debug.Log("[Cookbook] shot " + attr.Id);
        }

        static Shot NewShot(int panel)
        {
            var s = new Shot { Panel = panel };
            var data = ScriptableObject.CreateInstance<UniversalRendererData>();
            ResourceReloader.ReloadAllNullIn(data, UniversalRenderPipelineAsset.packagePath);
            data.postProcessData = AssetDatabase.LoadAssetAtPath<PostProcessData>(UniversalRenderPipelineAsset.packagePath + "/Runtime/Data/PostProcessData.asset");
            data.renderingMode = RenderingMode.ForwardPlus;
            data.copyDepthMode = CopyDepthMode.AfterOpaques;   // 透明物体读到的是本帧深度
            var asset = UniversalRenderPipelineAsset.Create(data);
            asset.supportsCameraDepthTexture = true;
            asset.supportsCameraOpaqueTexture = true;
            asset.supportsHDR = true;
            asset.msaaSampleCount = 4;
            asset.shadowDistance = 30f;
            asset.shadowCascadeCount = 2;
            s.Asset = asset; s.Renderer = data;
            s.AssetProp("m_SoftShadowsSupported", true);
            s.AssetProp("m_AdditionalLightShadowsSupported", true);
            s.AssetProp("m_MainLightShadowmapResolution", 4096);
            s.Temp.Add(asset); s.Temp.Add(data);
            GraphicsSettings.defaultRenderPipeline = asset;
            QualitySettings.renderPipeline = null;

            var camGo = new GameObject("Main Camera") { tag = "MainCamera" };
            s.Cam = camGo.AddComponent<Camera>();
            s.Cam.allowHDR = true; s.Cam.allowMSAA = true;
            s.Cam.nearClipPlane = 0.05f; s.Cam.farClipPlane = 200f;
            s.CamData = camGo.AddComponent<UniversalAdditionalCameraData>();
            s.CamData.renderPostProcessing = false;
            s.LookAt(new Vector3(0, 1.4f, -4.2f), new Vector3(0, 0.55f, 0));

            var sunGo = new GameObject("Sun");
            s.Sun = sunGo.AddComponent<Light>();
            s.Sun.type = LightType.Directional; s.Sun.shadows = LightShadows.Soft; s.Sun.color = new Color(1f, 0.96f, 0.9f);
            sunGo.AddComponent<UniversalAdditionalLightData>();
            s.SunDir(50, -30);
            RenderSettings.sun = s.Sun;

            SetupEnvironment(s);
            return s;
        }

        // 程序化天空：同时作为背景、环境光（球谐）和默认反射
        static Vector3 SkyRadiance(Vector3 d)
        {
            Color zenith = new Color(0.12f, 0.25f, 0.55f), horizon = new Color(0.55f, 0.6f, 0.68f), ground = new Color(0.2f, 0.19f, 0.18f);
            Color c;
            if (d.y >= 0) c = Color.Lerp(horizon, zenith, Mathf.Pow(d.y, 0.45f));
            else c = Color.Lerp(horizon * 0.6f, ground, Mathf.Clamp01(-d.y * 4f));
            Vector3 sunDir = Quaternion.Euler(50, -30, 0) * Vector3.back;
            float sd = Mathf.Max(0, Vector3.Dot(d, sunDir));
            Vector3 v = new Vector3(c.r, c.g, c.b);
            v += new Vector3(1f, 0.9f, 0.75f) * (Mathf.Pow(sd, 64f) * 1.5f + Mathf.Pow(sd, 2000f) * 40f);
            return v;
        }

        static void SetupEnvironment(Shot s)
        {
            if (s_Sky == null)
            {
                const int size = 128;
                s_Sky = new Cubemap(size, TextureFormat.RGBAHalf, true) { name = "CookbookSky", hideFlags = HideFlags.DontSave };
                var faces = new[] { CubemapFace.PositiveX, CubemapFace.NegativeX, CubemapFace.PositiveY, CubemapFace.NegativeY, CubemapFace.PositiveZ, CubemapFace.NegativeZ };
                var px = new Color[size * size];
                foreach (var f in faces)
                {
                    for (int y = 0; y < size; y++)
                        for (int x = 0; x < size; x++)
                        {
                            float u = (x + 0.5f) / size * 2 - 1, v = (y + 0.5f) / size * 2 - 1;
                            Vector3 d;
                            switch (f)
                            {
                                case CubemapFace.PositiveX: d = new Vector3(1, -v, -u); break;
                                case CubemapFace.NegativeX: d = new Vector3(-1, -v, u); break;
                                case CubemapFace.PositiveY: d = new Vector3(u, 1, v); break;
                                case CubemapFace.NegativeY: d = new Vector3(u, -1, -v); break;
                                case CubemapFace.PositiveZ: d = new Vector3(u, -v, 1); break;
                                default: d = new Vector3(-u, -v, -1); break;
                            }
                            var r = SkyRadiance(d.normalized);
                            px[y * size + x] = new Color(r.x, r.y, r.z, 1);
                        }
                    s_Sky.SetPixels(px, f);
                }
                s_Sky.Apply(true, false);
            }
            var skyMat = new Material(Shader.Find("Skybox/Cubemap"));
            skyMat.SetTexture("_Tex", s_Sky);
            s.Temp.Add(skyMat);
            RenderSettings.skybox = skyMat;
            RenderSettings.defaultReflectionMode = DefaultReflectionMode.Custom;
            RenderSettings.customReflectionTexture = s_Sky;
            RenderSettings.reflectionIntensity = 1f;
            RenderSettings.ambientMode = AmbientMode.Skybox;
            RenderSettings.fog = false;

            var sh = new SphericalHarmonicsL2();
            var rnd = new System.Random(7);
            const int N = 4096;
            for (int i = 0; i < N; i++)
            {
                float z = (float)rnd.NextDouble() * 2 - 1, a = (float)rnd.NextDouble() * Mathf.PI * 2, r = Mathf.Sqrt(1 - z * z);
                var d = new Vector3(r * Mathf.Cos(a), z, r * Mathf.Sin(a));
                var L = SkyRadiance(d);
                L = Vector3.Min(L, Vector3.one * 3f); // 太阳尖峰交给方向光，不重复计入环境光
                sh.AddDirectionalLight(d, new Color(L.x, L.y, L.z), 4f / N);
            }
            RenderSettings.ambientProbe = sh;
            s.Cam.clearFlags = CameraClearFlags.Skybox;
        }

        static Texture2D Capture(Shot s, int w, int h, bool hdr)
        {
            var desc = new RenderTextureDescriptor(w, h, RenderTextureFormat.ARGB32, 24) { sRGB = true, msaaSamples = 1 };
            var rt = new RenderTexture(desc);
            rt.Create();
            // 相机目标：URP 14 按目标纹理决定中间缓冲的格式与 MSAA，所以这里直接给 4x MSAA（HDR 时用浮点）
            var camDesc = hdr
                ? new RenderTextureDescriptor(w, h, RenderTextureFormat.ARGBHalf, 24) { sRGB = false, msaaSamples = 4 }
                : new RenderTextureDescriptor(w, h, RenderTextureFormat.ARGB32, 24) { sRGB = true, msaaSamples = 4 };
            var hdrRt = new RenderTexture(camDesc);
            hdrRt.Create();
            s.Cam.targetTexture = hdrRt;
            s.Cam.aspect = (float)w / h;
            for (int i = 0; i < 3; i++) s.Cam.Render();   // 多渲染几次，让阴影/后处理/历史帧稳定
            var prev = RenderTexture.active;
            Graphics.Blit(hdrRt, rt);                       // 解析 MSAA；HDR 时顺便线性浮点 -> sRGB 8 位
            RenderTexture.active = rt;
            var tex = new Texture2D(w, h, TextureFormat.RGBA32, false) { hideFlags = HideFlags.DontSave };
            tex.ReadPixels(new Rect(0, 0, w, h), 0, 0);
            tex.Apply();
            RenderTexture.active = prev;
            s.Cam.targetTexture = null;
            rt.Release(); Object.DestroyImmediate(rt);
            hdrRt.Release(); Object.DestroyImmediate(hdrRt);
            return tex;
        }
    }
}
