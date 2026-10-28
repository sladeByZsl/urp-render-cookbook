// WebGL2 小工具：贴图、渲染目标、着色器程序与 uniform 反射
export class GLContext {
  constructor(canvas, opts = {}) {
    const gl = canvas.getContext('webgl2', { antialias: false, alpha: false, depth: false, stencil: false, premultipliedAlpha: false, preserveDrawingBuffer: !!opts.preserveDrawingBuffer, powerPreference: 'high-performance' });
    if (!gl) throw new Error('浏览器不支持 WebGL2');
    this.gl = gl;
    this.canvas = canvas;
    this.extColorFloat = gl.getExtension('EXT_color_buffer_float');
    this.extFloatLinear = gl.getExtension('OES_texture_float_linear');
    this.extAniso = gl.getExtension('EXT_texture_filter_anisotropic');
    this.extBlendMinMax = true;
    this.maxSamples = gl.getParameter(gl.MAX_SAMPLES);
    this.defaults = {};
    this.makeDefaultTextures();
  }

  // ---------------- 贴图 ----------------
  makeDefaultTextures() {
    const solid = (r, g, b, a, srgb = false) => this.texture2D(1, 1, srgb ? 'SRGB8_ALPHA8' : 'RGBA8', new Uint8Array([r, g, b, a]), { mips: false, filter: 'Point' });
    this.defaults.white = solid(255, 255, 255, 255);
    this.defaults.black = solid(0, 0, 0, 0);
    this.defaults.gray = solid(128, 128, 128, 255);
    this.defaults.grey = this.defaults.gray;
    this.defaults.bump = solid(128, 128, 255, 255);
    this.defaults.red = solid(255, 0, 0, 255);
    this.defaults.linearGray = solid(128, 128, 128, 255);
    const gl = this.gl;
    const cube = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_CUBE_MAP, cube);
    for (let f = 0; f < 6; f++) gl.texImage2D(gl.TEXTURE_CUBE_MAP_POSITIVE_X + f, 0, gl.RGBA8, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 0, 0]));
    gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
    this.defaults.cube = { tex: cube, target: gl.TEXTURE_CUBE_MAP, width: 1, height: 1 };
    const t3 = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_3D, t3);
    gl.texImage3D(gl.TEXTURE_3D, 0, gl.RGBA8, 1, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([255, 255, 255, 255]));
    this.defaults.tex3d = { tex: t3, target: gl.TEXTURE_3D, width: 1, height: 1 };
    // 阴影图的占位：深度比较纹理，比较结果恒为 1
    const sh = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, sh);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.DEPTH_COMPONENT24, 1, 1, 0, gl.DEPTH_COMPONENT, gl.UNSIGNED_INT, new Uint32Array([0xffffffff]));
    this.setShadowCompare(sh);
    this.defaults.shadow = { tex: sh, target: gl.TEXTURE_2D, width: 1, height: 1, shadow: true };
  }

  setShadowCompare(tex) {
    const gl = this.gl;
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_COMPARE_MODE, gl.COMPARE_REF_TO_TEXTURE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_COMPARE_FUNC, gl.LEQUAL);
  }

  formatInfo(name) {
    const gl = this.gl;
    const F = {
      RGBA8: [gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE],
      SRGB8_ALPHA8: [gl.SRGB8_ALPHA8, gl.RGBA, gl.UNSIGNED_BYTE],
      RGBA16F: [gl.RGBA16F, gl.RGBA, gl.HALF_FLOAT],
      RGBA16F_FROM32: [gl.RGBA16F, gl.RGBA, gl.FLOAT],
      RGBA32F: [gl.RGBA32F, gl.RGBA, gl.FLOAT],
      R16F: [gl.R16F, gl.RED, gl.HALF_FLOAT],
      R32F: [gl.R32F, gl.RED, gl.FLOAT],
      RG16F: [gl.RG16F, gl.RG, gl.HALF_FLOAT],
      R8: [gl.R8, gl.RED, gl.UNSIGNED_BYTE],
      RG8: [gl.RG8, gl.RG, gl.UNSIGNED_BYTE],
      R11F_G11F_B10F: [gl.R11F_G11F_B10F, gl.RGB, gl.HALF_FLOAT],
      DEPTH24: [gl.DEPTH_COMPONENT24, gl.DEPTH_COMPONENT, gl.UNSIGNED_INT],
      DEPTH32F: [gl.DEPTH_COMPONENT32F, gl.DEPTH_COMPONENT, gl.FLOAT],
      DEPTH24_STENCIL8: [gl.DEPTH24_STENCIL8, gl.DEPTH_STENCIL, gl.UNSIGNED_INT_24_8],
    };
    if (!F[name]) throw new Error('未知贴图格式 ' + name);
    return F[name];
  }

  applySampler(target, o) {
    const gl = this.gl;
    const wrap = (w) => (w === 'Clamp' ? gl.CLAMP_TO_EDGE : w === 'Mirror' ? gl.MIRRORED_REPEAT : w === 'MirrorOnce' ? gl.MIRRORED_REPEAT : gl.REPEAT);
    const mips = o.mips !== false;
    const filter = o.filter || 'Bilinear';
    gl.texParameteri(target, gl.TEXTURE_WRAP_S, wrap(o.wrapU || o.wrap || 'Repeat'));
    gl.texParameteri(target, gl.TEXTURE_WRAP_T, wrap(o.wrapV || o.wrap || 'Repeat'));
    if (target === gl.TEXTURE_3D) gl.texParameteri(target, gl.TEXTURE_WRAP_R, wrap(o.wrapU || o.wrap || 'Repeat'));
    if (filter === 'Point') {
      gl.texParameteri(target, gl.TEXTURE_MIN_FILTER, mips ? gl.NEAREST_MIPMAP_NEAREST : gl.NEAREST);
      gl.texParameteri(target, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    } else {
      gl.texParameteri(target, gl.TEXTURE_MIN_FILTER, mips ? (filter === 'Trilinear' ? gl.LINEAR_MIPMAP_LINEAR : gl.LINEAR_MIPMAP_NEAREST) : gl.LINEAR);
      gl.texParameteri(target, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    }
    if (this.extAniso && o.aniso > 1 && mips) gl.texParameterf(target, this.extAniso.TEXTURE_MAX_ANISOTROPY_EXT, Math.min(16, o.aniso));
  }

  texture2D(w, h, format, data, o = {}) {
    const gl = this.gl;
    const [ifmt, fmt, type] = this.formatInfo(format);
    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.texImage2D(gl.TEXTURE_2D, 0, ifmt, w, h, 0, fmt, type, data || null);
    if (o.levels) o.levels.forEach((lv, i) => i > 0 && gl.texImage2D(gl.TEXTURE_2D, i, ifmt, lv.w, lv.h, 0, fmt, type, lv.data));
    else if (o.mips !== false && data) gl.generateMipmap(gl.TEXTURE_2D);
    this.applySampler(gl.TEXTURE_2D, { ...o, mips: o.mips !== false && (!!data || !!o.levels) });
    return { tex, target: gl.TEXTURE_2D, width: w, height: h, format };
  }

  textureFromImage(img, o = {}) {
    const gl = this.gl;
    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, tex);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.texImage2D(gl.TEXTURE_2D, 0, o.srgb ? gl.SRGB8_ALPHA8 : gl.RGBA8, gl.RGBA, gl.UNSIGNED_BYTE, img);
    const mips = o.mips !== false;
    if (mips) gl.generateMipmap(gl.TEXTURE_2D);
    this.applySampler(gl.TEXTURE_2D, { ...o, mips });
    return { tex, target: gl.TEXTURE_2D, width: img.width, height: img.height };
  }

  // levels: [{mip, face, w, h, data}]
  textureCube(size, format, levels, o = {}) {
    const gl = this.gl;
    const [ifmt, fmt, type] = this.formatInfo(format);
    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_CUBE_MAP, tex);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    let maxMip = 0;
    for (const lv of levels) {
      gl.texImage2D(gl.TEXTURE_CUBE_MAP_POSITIVE_X + lv.face, lv.mip, ifmt, lv.w, lv.h, 0, fmt, type, lv.data);
      maxMip = Math.max(maxMip, lv.mip);
    }
    gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAX_LEVEL, maxMip);
    // 与 applySampler 一致：Unity 的 Bilinear 在 mip 之间取最近一级（不插值），只有 Trilinear 才在两级 mip 间插值
    const cubeMin = o.filter === 'Point' ? gl.NEAREST_MIPMAP_NEAREST : o.filter === 'Bilinear' ? gl.LINEAR_MIPMAP_NEAREST : gl.LINEAR_MIPMAP_LINEAR;
    gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MIN_FILTER, maxMip > 0 ? cubeMin : gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_MAG_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_CUBE_MAP, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    return { tex, target: gl.TEXTURE_CUBE_MAP, width: size, height: size, mips: maxMip + 1 };
  }

  texture3D(w, h, d, format, data, o = {}) {
    const gl = this.gl;
    const [ifmt, fmt, type] = this.formatInfo(format);
    const tex = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_3D, tex);
    gl.pixelStorei(gl.UNPACK_ALIGNMENT, 1);
    gl.texImage3D(gl.TEXTURE_3D, 0, ifmt, w, h, d, 0, fmt, type, data);
    this.applySampler(gl.TEXTURE_3D, { ...o, mips: false });
    return { tex, target: gl.TEXTURE_3D, width: w, height: h, depth: d };
  }

  // ---------------- 渲染目标 ----------------
  // color: 格式名或 null；depth: 'DEPTH24_STENCIL8' | 'DEPTH24' | null；samples>1 时用多重采样 renderbuffer，resolve() 解析到贴图
  renderTarget(w, h, { color = 'RGBA16F', depth = null, samples = 1, filter = 'Bilinear', mips = false, depthTexture = true, renderbuffers = false } = {}) {
    const gl = this.gl;
    const rt = { w, h, color, depth, samples, fbo: gl.createFramebuffer(), filter };
    gl.bindFramebuffer(gl.FRAMEBUFFER, rt.fbo);
    // renderbuffers=true：即使不开 MSAA 也画到 renderbuffer，再 resolve 成贴图（这样采样深度/颜色时不会和正在写的附件冲突）
    if (samples > 1 || renderbuffers) {
      samples = samples > 1 ? Math.min(samples, this.maxSamples) : 0;
      rt.samples = samples;
      if (color) {
        rt.colorRB = gl.createRenderbuffer();
        gl.bindRenderbuffer(gl.RENDERBUFFER, rt.colorRB);
        gl.renderbufferStorageMultisample(gl.RENDERBUFFER, samples, this.formatInfo(color)[0], w, h);
        gl.framebufferRenderbuffer(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.RENDERBUFFER, rt.colorRB);
      }
      if (depth) {
        rt.depthRB = gl.createRenderbuffer();
        gl.bindRenderbuffer(gl.RENDERBUFFER, rt.depthRB);
        gl.renderbufferStorageMultisample(gl.RENDERBUFFER, samples, this.formatInfo(depth)[0], w, h);
        gl.framebufferRenderbuffer(gl.FRAMEBUFFER, depth === 'DEPTH24_STENCIL8' ? gl.DEPTH_STENCIL_ATTACHMENT : gl.DEPTH_ATTACHMENT, gl.RENDERBUFFER, rt.depthRB);
      }
      // 解析目标（单采样贴图）
      rt.resolve = this.renderTarget(w, h, { color, depth: depth && depthTexture ? depth : null, samples: 1, filter, mips });
      rt.texture = rt.resolve.texture;
      rt.depthTexture = rt.resolve.depthTexture;
    } else {
      if (color) {
        rt.texture = this.texture2D(w, h, color, null, { mips: false, filter, wrap: 'Clamp' });
        if (mips) {
          gl.bindTexture(gl.TEXTURE_2D, rt.texture.tex);
          gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR_MIPMAP_LINEAR);
          rt.texture.hasMips = true;
        }
        gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, rt.texture.tex, 0);
      }
      if (depth) {
        rt.depthTexture = this.texture2D(w, h, depth, null, { mips: false, filter: 'Point', wrap: 'Clamp' });
        gl.framebufferTexture2D(gl.FRAMEBUFFER, depth === 'DEPTH24_STENCIL8' ? gl.DEPTH_STENCIL_ATTACHMENT : gl.DEPTH_ATTACHMENT, gl.TEXTURE_2D, rt.depthTexture.tex, 0);
      }
    }
    if (!color) { gl.drawBuffers([gl.NONE]); gl.readBuffer(gl.NONE); }
    const st = gl.checkFramebufferStatus(gl.FRAMEBUFFER);
    if (st !== gl.FRAMEBUFFER_COMPLETE) console.warn('Framebuffer 不完整', st.toString(16), w, h, color, depth, samples);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    return rt;
  }

  // 把多重采样目标解析到它的 resolve 贴图（颜色和/或深度）
  resolve(rt, { color = true, depth = false } = {}) {
    if (!rt.resolve) return;
    const gl = this.gl;
    gl.bindFramebuffer(gl.READ_FRAMEBUFFER, rt.fbo);
    gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, rt.resolve.fbo);
    let mask = 0;
    if (color && rt.color) mask |= gl.COLOR_BUFFER_BIT;
    if (depth && rt.depth && rt.resolve.depthTexture) mask |= gl.DEPTH_BUFFER_BIT | (rt.depth === 'DEPTH24_STENCIL8' ? gl.STENCIL_BUFFER_BIT : 0);
    if (mask) gl.blitFramebuffer(0, 0, rt.w, rt.h, 0, 0, rt.w, rt.h, mask, gl.NEAREST);
    gl.bindFramebuffer(gl.READ_FRAMEBUFFER, null);
    gl.bindFramebuffer(gl.DRAW_FRAMEBUFFER, null);
  }

  deleteRT(rt) {
    if (!rt) return;
    const gl = this.gl;
    gl.deleteFramebuffer(rt.fbo);
    if (rt.colorRB) gl.deleteRenderbuffer(rt.colorRB);
    if (rt.depthRB) gl.deleteRenderbuffer(rt.depthRB);
    if (rt.resolve) this.deleteRT(rt.resolve);
    else {
      if (rt.texture) gl.deleteTexture(rt.texture.tex);
      if (rt.depthTexture) gl.deleteTexture(rt.depthTexture.tex);
    }
  }

  // ---------------- 着色器程序 ----------------
  // 失败时抛出 ShaderError，errors 是 [{stage, source, line, message}]
  program(vsSource, fsSource, attribLocations) {
    const gl = this.gl;
    const compile = (type, src, stage) => {
      const s = gl.createShader(type);
      gl.shaderSource(s, src);
      gl.compileShader(s);
      if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
        const log = gl.getShaderInfoLog(s) || '';
        gl.deleteShader(s);
        throw new ShaderError(stage, log);
      }
      return s;
    };
    const vs = compile(gl.VERTEX_SHADER, vsSource, 'vertex');
    const fs = compile(gl.FRAGMENT_SHADER, fsSource, 'fragment');
    const p = gl.createProgram();
    gl.attachShader(p, vs);
    gl.attachShader(p, fs);
    for (const [name, loc] of Object.entries(attribLocations)) gl.bindAttribLocation(p, loc, name);
    gl.linkProgram(p);
    gl.deleteShader(vs);
    gl.deleteShader(fs);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) {
      const log = gl.getProgramInfoLog(p);
      gl.deleteProgram(p);
      throw new ShaderError('link', log);
    }
    // uniform 反射：名字 → {loc, type, size, unit}
    const uniforms = new Map();
    let unit = 0;
    const n = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
    for (let i = 0; i < n; i++) {
      const info = gl.getActiveUniform(p, i);
      const isArray = info.name.endsWith('[0]');
      const name = isArray ? info.name.slice(0, -3) : info.name;
      const loc = gl.getUniformLocation(p, info.name);
      const u = { name, loc, type: info.type, size: info.size, isArray };
      if (isSampler(gl, info.type)) u.unit = unit++;
      uniforms.set(name, u);
    }
    return { program: p, uniforms };
  }
}

export class ShaderError extends Error {
  constructor(stage, log) {
    super(`${stage} 编译失败：\n${log}`);
    this.stage = stage;
    this.log = log;
  }
}

export function isSampler(gl, t) {
  return [gl.SAMPLER_2D, gl.SAMPLER_CUBE, gl.SAMPLER_3D, gl.SAMPLER_2D_SHADOW, gl.SAMPLER_2D_ARRAY, gl.INT_SAMPLER_2D, gl.UNSIGNED_INT_SAMPLER_2D].includes(t);
}

export function setUniform(gl, u, v) {
  const L = u.loc;
  switch (u.type) {
    case gl.FLOAT: u.isArray ? gl.uniform1fv(L, v) : gl.uniform1f(L, typeof v === 'number' ? v : v[0]); break;
    case gl.FLOAT_VEC2: gl.uniform2fv(L, v.length >= 2 ? (u.isArray ? v : v.slice(0, 2)) : [v[0], 0]); break;
    case gl.FLOAT_VEC3: gl.uniform3fv(L, u.isArray ? v : (v.length >= 3 ? v.slice(0, 3) : [v[0], v[1] || 0, 0])); break;
    case gl.FLOAT_VEC4: gl.uniform4fv(L, u.isArray ? v : (typeof v === 'number' ? [v, 0, 0, 0] : v.length === 4 ? v : [v[0] || 0, v[1] || 0, v[2] || 0, v[3] === undefined ? 1 : v[3]])); break;
    case gl.INT: case gl.BOOL: u.isArray ? gl.uniform1iv(L, v) : gl.uniform1i(L, typeof v === 'number' ? v : v[0]); break;
    case gl.INT_VEC2: gl.uniform2iv(L, v); break;
    case gl.INT_VEC4: gl.uniform4iv(L, v); break;
    case gl.UNSIGNED_INT: gl.uniform1ui(L, typeof v === 'number' ? v : v[0]); break;
    case gl.FLOAT_MAT4: gl.uniformMatrix4fv(L, false, v); break;
    case gl.FLOAT_MAT3: gl.uniformMatrix3fv(L, false, v); break;
    case gl.FLOAT_MAT2: gl.uniformMatrix2fv(L, false, v); break;
    default: break;
  }
}
