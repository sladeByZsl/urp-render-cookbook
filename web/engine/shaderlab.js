// 解析 “ShaderLab 外壳 + GLSL 代码” 格式的着色器文件（*.glsl），并按关键字编译变体。
//
// 文件结构与 Unity 的 .shader 一样，只是 HLSLPROGRAM/ENDHLSL 换成 GLSLPROGRAM/ENDGLSL：
//   Shader "Cookbook/Ch05/Lambert" {
//     SubShader {
//       Tags { "Queue"="Geometry" }
//       GLSLINCLUDE ...所有 Pass 共用的代码... ENDGLSL
//       Pass { Name "ForwardLit" Tags { "LightMode"="UniversalForward" } Cull Back
//         GLSLPROGRAM
//         #ifdef VERTEX   ...顶点着色器，写 void main()...   #endif
//         #ifdef FRAGMENT ...片元着色器，写 void main()，输出到 fragColor... #endif
//         ENDGLSL }
//       UsePass "Cookbook/Common/SHADOWCASTER"
//     }
//   }
// Properties 块可以省略：属性的名字、范围、默认值以 HLSL 原版为准（网页从 shaders.json 读取）。

export const ATTRIBS = { positionOS: 0, normalOS: 1, tangentOS: 2, color: 3, texcoord0: 4, texcoord1: 5, texcoord2: 6, texcoord3: 7 };

// invariant gl_Position：同一网格被不同 Shader 再画一遍（ZTest Equal/Greater、预深度 Pass）时，深度必须逐位相同，否则会闪出 Z-fighting 噪点
const STAGE_PRELUDE = {
  VERTEX: `#define VERTEX 1
#define VARYING out
invariant gl_Position;
in vec4 positionOS;
in vec3 normalOS;
in vec4 tangentOS;
in vec4 color;
in vec4 texcoord0;
in vec4 texcoord1;
in vec4 texcoord2;
in vec4 texcoord3;
`,
  FRAGMENT: `#define FRAGMENT 1
#define VARYING in
layout(location = 0) out vec4 fragColor;
`,
};

// ---------------- 词法 ----------------
function tokenize(src) {
  const toks = [];
  let i = 0, line = 1;
  const n = src.length;
  while (i < n) {
    const c = src[i];
    if (c === '\n') { line++; i++; continue; }
    if (/\s/.test(c)) { i++; continue; }
    if (c === '/' && src[i + 1] === '/') { while (i < n && src[i] !== '\n') i++; continue; }
    if (c === '/' && src[i + 1] === '*') { const e = src.indexOf('*/', i + 2); const end = e < 0 ? n : e + 2; line += countLines(src, i, end); i = end; continue; }
    // GLSL 代码块原样截取
    const blk = /^(GLSLPROGRAM|GLSLINCLUDE)\b/.exec(src.slice(i, i + 12));
    if (blk) {
      const end = src.indexOf('ENDGLSL', i);
      if (end < 0) throw new Error(`第 ${line} 行：${blk[1]} 缺少 ENDGLSL`);
      const bodyStart = i + blk[1].length;
      toks.push({ t: 'code', kind: blk[1], v: src.slice(bodyStart, end), line, bodyLine: line });
      line += countLines(src, i, end + 7);
      i = end + 7;
      continue;
    }
    if (c === '"') { let j = i + 1; while (j < n && src[j] !== '"') j++; toks.push({ t: 'str', v: src.slice(i + 1, j), line }); i = j + 1; continue; }
    if ('{}()[]=,'.includes(c)) { toks.push({ t: 'p', v: c, line }); i++; continue; }
    let j = i;
    while (j < n && !/[\s{}()[\]=,"]/.test(src[j])) j++;
    toks.push({ t: 'w', v: src.slice(i, j), line });
    i = j;
  }
  return toks;
}
function countLines(s, a, b) { let k = 0; for (let i = a; i < b; i++) if (s[i] === '\n') k++; return k; }

// ---------------- 语法 ----------------
const STATE_WORDS = new Set(['Cull', 'ZWrite', 'ZTest', 'Blend', 'BlendOp', 'ColorMask', 'Offset', 'AlphaToMask', 'ZClip', 'Conservative']);

export function parseShaderLab(src, file) {
  const toks = tokenize(src);
  let p = 0;
  const peek = () => toks[p];
  const next = () => toks[p++];
  const err = (m, t = peek()) => { throw new Error(`${file}:${t ? t.line : '?'}: ${m}`); };
  const expect = (v) => { const t = next(); if (!t || t.v !== v) err(`应为 ${v}`, t); return t; };

  const parseTags = () => {
    expect('{');
    const tags = {};
    while (peek() && peek().v !== '}') { const k = next().v; expect('='); tags[k] = next().v; }
    expect('}');
    return tags;
  };
  const skipBlock = () => { let d = 0; do { const t = next(); if (!t) err('块没有闭合'); if (t.v === '{') d++; else if (t.v === '}') d--; } while (d > 0); };
  // 渲染状态值可能是 [_Prop] 形式（运行时从材质读）
  const value = () => {
    const t = next();
    if (t.v === '[') { const name = next().v; expect(']'); return { prop: name }; }
    return t.v;
  };
  const parseState = (word, state) => {
    const line = peek() ? peek().line : 0;
    const restOfLine = () => { const out = []; while (peek() && peek().line === line && peek().t !== 'code' && peek().v !== '}' && !(peek().t === 'w' && (STATE_WORDS.has(peek().v) || ['Pass', 'Name', 'Tags', 'Stencil', 'UsePass', 'LOD'].includes(peek().v)))) { if (peek().v === ',') { next(); continue; } out.push(value()); } return out; };
    switch (word) {
      case 'Cull': state.cull = value(); break;
      case 'ZWrite': state.zwrite = value(); break;
      case 'ZTest': state.ztest = value(); break;
      case 'BlendOp': state.blendOp = restOfLine(); break;
      case 'ColorMask': { const v = restOfLine(); state.colorMask = v[0]; break; }
      case 'Offset': state.offset = restOfLine(); break;
      case 'AlphaToMask': state.alphaToMask = value(); break;
      case 'ZClip': case 'Conservative': value(); break;
      case 'Blend': {
        let v = restOfLine();
        if (v.length && /^\d$/.test(v[0])) v = v.slice(1);   // Blend 0 One One（多目标）只取 0 号
        state.blend = v;
        break;
      }
    }
  };
  const parseStencil = () => {
    expect('{');
    const s = {};
    while (peek() && peek().v !== '}') { const k = next().v; s[k] = value(); }
    expect('}');
    return s;
  };

  const shader = { name: '', subShaders: [], include: [], file };
  if (next().v !== 'Shader') err('文件应以 Shader "名字" 开头', toks[0]);
  shader.name = next().v;
  expect('{');
  while (peek() && peek().v !== '}') {
    const t = next();
    if (t.v === 'Properties') { skipBlock(); continue; }
    if (t.t === 'code' && t.kind === 'GLSLINCLUDE') { shader.include.push({ code: t.v, line: t.bodyLine }); continue; }
    if (t.v === 'Fallback' || t.v === 'FallBack') { next(); continue; }
    if (t.v === 'CustomEditor') { next(); continue; }
    if (t.v === 'SubShader') {
      const sub = { tags: {}, state: {}, include: [], passes: [] };
      expect('{');
      while (peek() && peek().v !== '}') {
        const u = next();
        if (u.v === 'Tags') sub.tags = parseTags();
        else if (u.v === 'LOD') next();
        else if (u.t === 'code' && u.kind === 'GLSLINCLUDE') sub.include.push({ code: u.v, line: u.bodyLine });
        else if (STATE_WORDS.has(u.v)) parseState(u.v, sub.state);
        else if (u.v === 'Stencil') sub.state.stencil = parseStencil();
        else if (u.v === 'UsePass') sub.passes.push({ usePass: next().v });
        else if (u.v === 'Pass') {
          const pass = { name: '', tags: {}, state: { ...sub.state }, code: null, line: u.line };
          expect('{');
          while (peek() && peek().v !== '}') {
            const w = next();
            if (w.v === 'Name') pass.name = next().v;
            else if (w.v === 'Tags') pass.tags = parseTags();
            else if (STATE_WORDS.has(w.v)) parseState(w.v, pass.state);
            else if (w.v === 'Stencil') pass.state.stencil = parseStencil();
            else if (w.t === 'code' && w.kind === 'GLSLPROGRAM') pass.code = { code: w.v, line: w.bodyLine };
            else if (w.t === 'code' && w.kind === 'GLSLINCLUDE') sub.include.push({ code: w.v, line: w.bodyLine });
            else err(`Pass 里不认识的指令 ${w.v}`, w);
          }
          expect('}');
          sub.passes.push(pass);
        } else err(`SubShader 里不认识的指令 ${u.v}`, u);
      }
      expect('}');
      shader.subShaders.push(sub);
      continue;
    }
    err(`不认识的指令 ${t.v}`, t);
  }
  return shader;
}

// 收集代码里用到的 #include（用于预加载）
export function findIncludes(code) {
  const out = [];
  const re = /^[ \t]*#[ \t]*include[ \t]+"([^"]+)"/gm;
  let m;
  while ((m = re.exec(code))) out.push(m[1]);
  return out;
}

// 收集 #pragma 声明的关键字（shader_feature / multi_compile 等）
export function findKeywords(code) {
  const kws = [];
  const re = /^[ \t]*#[ \t]*pragma[ \t]+(shader_feature|multi_compile)\w*[ \t]+([^\n]*)/gm;
  let m;
  while ((m = re.exec(code))) {
    const group = m[2].split(/\s+/).filter((k) => k && k !== '_' && !/^__+$/.test(k));
    kws.push(group);
  }
  return kws;
}

// ---------------- 拼源码 ----------------
// 用 #line 把报错行号映射回原文件；源串号 N 对应 files[N]
export class SourceBuilder {
  constructor(resolveInclude) {
    this.resolveInclude = resolveInclude;   // (path) => { text, file }
    this.files = [];
    this.parts = [];
  }
  fileIndex(file) {
    let i = this.files.indexOf(file);
    if (i < 0) { i = this.files.length; this.files.push(file); }
    return i;
  }
  add(code, file, line, seen = new Set()) {
    const fi = this.fileIndex(file);
    const lines = code.split('\n');
    this.parts.push(`#line ${line} ${fi}`);
    for (let k = 0; k < lines.length; k++) {
      const m = /^[ \t]*#[ \t]*include[ \t]+"([^"]+)"/.exec(lines[k]);
      if (m) {
        const inc = this.resolveInclude(m[1]);
        if (!inc) throw new Error(`${file}:${line + k}: 找不到 #include "${m[1]}"`);
        if (!seen.has(inc.file)) {
          seen.add(inc.file);
          this.add(inc.text, inc.file, 1, seen);
        }
        this.parts.push(`#line ${line + k + 1} ${fi}`);
        continue;
      }
      // #pragma 在 WebGL 里没用，留空行保持行号
      this.parts.push(/^[ \t]*#[ \t]*pragma\b/.test(lines[k]) ? '' : lines[k]);
    }
  }
  toString() { return this.parts.join('\n'); }
}

// 把 WebGL 的报错（ERROR: 源串号:行号: 信息）翻译成 文件:行号
export function mapErrors(log, files) {
  const out = [];
  for (const ln of (log || '').split('\n')) {
    const m = /^(ERROR|WARNING):\s*(\d+):(\d+):\s*(.*)$/.exec(ln.trim());
    if (m) out.push({ level: m[1], file: files[+m[2]] || '?', line: +m[3], message: m[4] });
    else if (ln.trim()) out.push({ level: 'ERROR', file: '?', line: 0, message: ln.trim() });
  }
  return out;
}

export { STAGE_PRELUDE };
