// MonoBehaviour：书里的运行时脚本（如 PlanarReflection、GrassRenderer）在网页里对应 behaviours/<C# 类型全名>.js。
//   export default class {
//     constructor(engine, json, obj, scene) {}   // json.data = 导出的序列化字段，obj = 所在物体
//     async init() {}
//     update(time, dt) {}                        // 每帧调用
//   }
// 没有网页版的脚本会被忽略（大多数只在编辑器里起作用）。
const cache = new Map();
let listPromise = null;

export async function loadBehaviour(engine, b, scene) {
  // behaviours/index.json 列出有网页版的组件（由 tools/shot.mjs 和 build_site.py 生成）
  if (!listPromise) listPromise = engine.assets.json('behaviours/index.json').catch(() => null);
  const list = await listPromise;
  if (list && !list.includes(b.type)) return null;
  const url = engine.assets.url(`behaviours/${b.type}.js`);
  if (!cache.has(url)) cache.set(url, import(url).catch(() => null));
  const mod = await cache.get(url);
  if (!mod) return null;
  const impl = new mod.default(engine, b.json, b.obj, scene);
  if (impl.init) await impl.init();
  return impl;
}
