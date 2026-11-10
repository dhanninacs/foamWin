/* ============================================================================
   Dye in water — a stable-fluids solver for the hero.
   Velocity + pressure (Jacobi) + vorticity confinement + dye advection, all in
   half-float textures on the GPU. It is the same class of solver the product
   ships, rendered as ink instead of residuals. If anything at all goes wrong
   (no WebGL2, no float targets, lost context) the page falls back to a static
   gradient and still looks deliberate.
   ========================================================================== */
(function () {
  "use strict";

  var canvas = document.querySelector("[data-fluid]");
  if (!canvas) return;

  var root = document.documentElement;
  var reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  var gl = canvas.getContext("webgl2", {
    alpha: false, depth: false, stencil: false, antialias: false,
    preserveDrawingBuffer: false, powerPreference: "low-power"
  });

  function bail(reason) {
    root.classList.add("no-webgl");
    if (window.console && console.info) console.info("[fluid] falling back:", reason);
  }

  if (!gl) { bail("no webgl2"); return; }
  if (!gl.getExtension("EXT_color_buffer_float")) { bail("no float render targets"); return; }

  /* ── Shaders ──────────────────────────────────────────────────────────── */

  var VERT = [
    "#version 300 es",
    "precision highp float;",
    "in vec2 aPosition;",
    "out vec2 vUv;",
    "out vec2 vL; out vec2 vR; out vec2 vT; out vec2 vB;",
    "uniform vec2 texelSize;",
    "void main () {",
    "  vUv = aPosition * 0.5 + 0.5;",
    "  vL = vUv - vec2(texelSize.x, 0.0);",
    "  vR = vUv + vec2(texelSize.x, 0.0);",
    "  vT = vUv + vec2(0.0, texelSize.y);",
    "  vB = vUv - vec2(0.0, texelSize.y);",
    "  gl_Position = vec4(aPosition, 0.0, 1.0);",
    "}"
  ].join("\n");

  var FRAG = {
    advection: [
      "precision highp float; precision highp sampler2D;",
      "in vec2 vUv; out vec4 outColor;",
      "uniform sampler2D uVelocity; uniform sampler2D uSource;",
      "uniform vec2 texelSize; uniform float dt; uniform float dissipation;",
      "void main () {",
      "  vec2 coord = vUv - dt * texture(uVelocity, vUv).xy * texelSize;",
      "  outColor = texture(uSource, coord) / (1.0 + dissipation * dt);",
      "}"
    ].join("\n"),

    divergence: [
      "precision highp float; precision highp sampler2D;",
      "in vec2 vUv; in vec2 vL; in vec2 vR; in vec2 vT; in vec2 vB; out vec4 outColor;",
      "uniform sampler2D uVelocity;",
      "void main () {",
      "  float L = texture(uVelocity, vL).x;",
      "  float R = texture(uVelocity, vR).x;",
      "  float T = texture(uVelocity, vT).y;",
      "  float B = texture(uVelocity, vB).y;",
      "  vec2 C = texture(uVelocity, vUv).xy;",
      "  if (vL.x < 0.0) L = -C.x;",
      "  if (vR.x > 1.0) R = -C.x;",
      "  if (vT.y > 1.0) T = -C.y;",
      "  if (vB.y < 0.0) B = -C.y;",
      "  outColor = vec4(0.5 * (R - L + T - B), 0.0, 0.0, 1.0);",
      "}"
    ].join("\n"),

    curl: [
      "precision highp float; precision highp sampler2D;",
      "in vec2 vL; in vec2 vR; in vec2 vT; in vec2 vB; out vec4 outColor;",
      "uniform sampler2D uVelocity;",
      "void main () {",
      "  float L = texture(uVelocity, vL).y;",
      "  float R = texture(uVelocity, vR).y;",
      "  float T = texture(uVelocity, vT).x;",
      "  float B = texture(uVelocity, vB).x;",
      "  outColor = vec4(0.5 * (R - L - T + B), 0.0, 0.0, 1.0);",
      "}"
    ].join("\n"),

    vorticity: [
      "precision highp float; precision highp sampler2D;",
      "in vec2 vUv; in vec2 vL; in vec2 vR; in vec2 vT; in vec2 vB; out vec4 outColor;",
      "uniform sampler2D uVelocity; uniform sampler2D uCurl;",
      "uniform float curl; uniform float dt;",
      "void main () {",
      "  float L = texture(uCurl, vL).x;",
      "  float R = texture(uCurl, vR).x;",
      "  float T = texture(uCurl, vT).x;",
      "  float B = texture(uCurl, vB).x;",
      "  float C = texture(uCurl, vUv).x;",
      "  vec2 force = 0.5 * vec2(abs(T) - abs(B), abs(R) - abs(L));",
      "  force /= length(force) + 0.0001;",
      "  force *= curl * C;",
      "  force.y *= -1.0;",
      "  vec2 vel = texture(uVelocity, vUv).xy;",
      "  vel += force * dt;",
      "  vel = min(max(vel, -1000.0), 1000.0);",
      "  outColor = vec4(vel, 0.0, 1.0);",
      "}"
    ].join("\n"),

    pressure: [
      "precision highp float; precision highp sampler2D;",
      "in vec2 vUv; in vec2 vL; in vec2 vR; in vec2 vT; in vec2 vB; out vec4 outColor;",
      "uniform sampler2D uPressure; uniform sampler2D uDivergence;",
      "void main () {",
      "  float L = texture(uPressure, vL).x;",
      "  float R = texture(uPressure, vR).x;",
      "  float T = texture(uPressure, vT).x;",
      "  float B = texture(uPressure, vB).x;",
      "  float divergence = texture(uDivergence, vUv).x;",
      "  outColor = vec4((L + R + B + T - divergence) * 0.25, 0.0, 0.0, 1.0);",
      "}"
    ].join("\n"),

    gradient: [
      "precision highp float; precision highp sampler2D;",
      "in vec2 vUv; in vec2 vL; in vec2 vR; in vec2 vT; in vec2 vB; out vec4 outColor;",
      "uniform sampler2D uPressure; uniform sampler2D uVelocity;",
      "void main () {",
      "  float L = texture(uPressure, vL).x;",
      "  float R = texture(uPressure, vR).x;",
      "  float T = texture(uPressure, vT).x;",
      "  float B = texture(uPressure, vB).x;",
      "  vec2 vel = texture(uVelocity, vUv).xy;",
      "  vel -= vec2(R - L, T - B);",
      "  outColor = vec4(vel, 0.0, 1.0);",
      "}"
    ].join("\n"),

    splat: [
      "precision highp float; precision highp sampler2D;",
      "in vec2 vUv; out vec4 outColor;",
      "uniform sampler2D uTarget; uniform float aspectRatio;",
      "uniform vec3 color; uniform vec2 point; uniform float radius;",
      "void main () {",
      "  vec2 p = vUv - point.xy;",
      "  p.x *= aspectRatio;",
      "  vec3 base = texture(uTarget, vUv).xyz;",
      "  outColor = vec4(base + exp(-dot(p, p) / radius) * color, 1.0);",
      "}"
    ].join("\n"),

    display: [
      "precision highp float; precision highp sampler2D;",
      "in vec2 vUv; out vec4 outColor;",
      "uniform sampler2D uTexture; uniform vec2 resolution;",
      "void main () {",
      "  vec3 c = texture(uTexture, vUv).rgb;",
      "  c = vec3(1.0) - exp(-c * 0.92);",           // tone map: dye reads as light
      "  float vig = 1.0 - smoothstep(0.32, 1.0, length(vUv - 0.5)) * 0.5;",
      "  c *= vig;",
      "  c = pow(c, vec3(0.94));",
      "  float n = fract(sin(dot(gl_FragCoord.xy, vec2(12.9898, 78.233))) * 43758.5453);",
      "  c += (n - 0.5) * 0.016;",
      "  outColor = vec4(c, 1.0);",
      "}"
    ].join("\n")
  };

  /* ── GL plumbing ──────────────────────────────────────────────────────── */

  function compile(type, source) {
    var s = gl.createShader(type);
    gl.shaderSource(s, source);
    gl.compileShader(s);
    if (!gl.getShaderParameter(s, gl.COMPILE_STATUS)) {
      throw new Error("shader: " + gl.getShaderInfoLog(s));
    }
    return s;
  }

  var vertShader = compile(gl.VERTEX_SHADER, VERT);

  function makeProgram(fragSource) {
    var p = gl.createProgram();
    gl.attachShader(p, vertShader);
    gl.attachShader(p, compile(gl.FRAGMENT_SHADER, "#version 300 es\n" + fragSource));
    gl.bindAttribLocation(p, 0, "aPosition");
    gl.linkProgram(p);
    if (!gl.getProgramParameter(p, gl.LINK_STATUS)) {
      throw new Error("link: " + gl.getProgramInfoLog(p));
    }
    var uniforms = {};
    var count = gl.getProgramParameter(p, gl.ACTIVE_UNIFORMS);
    for (var i = 0; i < count; i++) {
      var info = gl.getActiveUniform(p, i);
      uniforms[info.name] = gl.getUniformLocation(p, info.name);
    }
    return { program: p, uniforms: uniforms, bind: function () { gl.useProgram(p); } };
  }

  var programs;
  try {
    programs = {
      advection: makeProgram(FRAG.advection),
      divergence: makeProgram(FRAG.divergence),
      curl: makeProgram(FRAG.curl),
      vorticity: makeProgram(FRAG.vorticity),
      pressure: makeProgram(FRAG.pressure),
      gradient: makeProgram(FRAG.gradient),
      splat: makeProgram(FRAG.splat),
      display: makeProgram(FRAG.display)
    };
  } catch (err) {
    bail(err.message);
    return;
  }

  // Full-screen triangle pair.
  var quad = gl.createBuffer();
  gl.bindBuffer(gl.ARRAY_BUFFER, quad);
  gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, -1, 1, 1, 1, 1, -1]), gl.STATIC_DRAW);
  var indexBuffer = gl.createBuffer();
  gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, indexBuffer);
  gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint16Array([0, 1, 2, 0, 2, 3]), gl.STATIC_DRAW);
  gl.vertexAttribPointer(0, 2, gl.FLOAT, false, 0, 0);
  gl.enableVertexAttribArray(0);

  function blit(target) {
    if (target == null) {
      gl.viewport(0, 0, gl.drawingBufferWidth, gl.drawingBufferHeight);
      gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    } else {
      gl.viewport(0, 0, target.width, target.height);
      gl.bindFramebuffer(gl.FRAMEBUFFER, target.fbo);
    }
    gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, 0);
  }

  var RGBA16F = gl.RGBA16F;
  var HALF = gl.HALF_FLOAT;

  function createFBO(w, h, filter) {
    gl.activeTexture(gl.TEXTURE0);
    var texture = gl.createTexture();
    gl.bindTexture(gl.TEXTURE_2D, texture);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, filter);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, filter);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texImage2D(gl.TEXTURE_2D, 0, RGBA16F, w, h, 0, gl.RGBA, HALF, null);

    var fbo = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fbo);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, texture, 0);
    gl.viewport(0, 0, w, h);
    gl.clearColor(0, 0, 0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT);

    return {
      texture: texture, fbo: fbo, width: w, height: h,
      texelSizeX: 1 / w, texelSizeY: 1 / h,
      attach: function (unit) {
        gl.activeTexture(gl.TEXTURE0 + unit);
        gl.bindTexture(gl.TEXTURE_2D, texture);
        return unit;
      }
    };
  }

  function createDoubleFBO(w, h, filter) {
    var a = createFBO(w, h, filter);
    var b = createFBO(w, h, filter);
    return {
      width: w, height: h, texelSizeX: 1 / w, texelSizeY: 1 / h,
      read: a, write: b,
      swap: function () { var t = a; a = b; b = t; this.read = a; this.write = b; }
    };
  }

  /* ── World state ──────────────────────────────────────────────────────── */

  var SIM_RES = 132;
  var DYE_RES = 512;
  var PRESSURE_ITER = 20;
  var CURL_STRENGTH = 15;
  var VELOCITY_DISSIPATION = 0.2;
  var DENSITY_DISSIPATION = 0.6;
  var SPLAT_RADIUS = 0.0016;

  var dye, velocity, divergence, curl, pressure;

  function resolution(base) {
    var aspect = gl.drawingBufferWidth / gl.drawingBufferHeight;
    if (!isFinite(aspect) || aspect <= 0) aspect = 1;
    var min = Math.round(base);
    var max = Math.round(base * aspect);
    return gl.drawingBufferWidth > gl.drawingBufferHeight
      ? { width: max, height: min }
      : { width: min, height: max };
  }

  function buildFramebuffers() {
    var sim = resolution(SIM_RES);
    var dy = resolution(DYE_RES);
    dye = createDoubleFBO(dy.width, dy.height, gl.LINEAR);
    velocity = createDoubleFBO(sim.width, sim.height, gl.LINEAR);
    divergence = createFBO(sim.width, sim.height, gl.NEAREST);
    curl = createFBO(sim.width, sim.height, gl.NEAREST);
    pressure = createDoubleFBO(sim.width, sim.height, gl.NEAREST);
  }

  function resize() {
    var dpr = Math.min(window.devicePixelRatio || 1, 1.75);
    var w = Math.max(1, Math.floor(canvas.clientWidth * dpr));
    var h = Math.max(1, Math.floor(canvas.clientHeight * dpr));
    if (canvas.width === w && canvas.height === h) return false;
    canvas.width = w;
    canvas.height = h;
    buildFramebuffers();
    return true;
  }

  /* ── Dye palette ──────────────────────────────────────────────────────── */

  // Saturated inks only. Anything pale turns grey once two of them mix.
  var PALETTE = [
    [0.95, 0.16, 0.07],  // vermilion — the brand ink
    [0.09, 0.13, 0.78],  // ultramarine
    [0.02, 0.38, 0.30],  // jade, pointing at Stokes
    [0.78, 0.26, 0.04]   // ember
  ];

  function pickColor(strength) {
    var c = PALETTE[(Math.random() * PALETTE.length) | 0];
    var k = strength == null ? 0.5 + Math.random() * 0.45 : strength;
    return [c[0] * k, c[1] * k, c[2] * k];
  }

  function splat(x, y, dx, dy, color, radius) {
    var p = programs.splat;
    p.bind();
    gl.uniform1i(p.uniforms.uTarget, velocity.read.attach(0));
    gl.uniform1f(p.uniforms.aspectRatio, canvas.width / canvas.height);
    gl.uniform2f(p.uniforms.point, x, y);
    gl.uniform3f(p.uniforms.color, dx, dy, 0);
    gl.uniform1f(p.uniforms.radius, radius || SPLAT_RADIUS);
    blit(velocity.write);
    velocity.swap();

    gl.uniform1i(p.uniforms.uTarget, dye.read.attach(0));
    gl.uniform3f(p.uniforms.color, color[0], color[1], color[2]);
    blit(dye.write);
    dye.swap();
  }

  /* ── One simulation tick ──────────────────────────────────────────────── */

  function step(dt) {
    var simTexel = [velocity.texelSizeX, velocity.texelSizeY];

    // Vorticity confinement keeps the ink curling instead of dissolving.
    var p = programs.curl;
    p.bind();
    gl.uniform2f(p.uniforms.texelSize, simTexel[0], simTexel[1]);
    gl.uniform1i(p.uniforms.uVelocity, velocity.read.attach(0));
    blit(curl);

    p = programs.vorticity;
    p.bind();
    gl.uniform2f(p.uniforms.texelSize, simTexel[0], simTexel[1]);
    gl.uniform1i(p.uniforms.uVelocity, velocity.read.attach(0));
    gl.uniform1i(p.uniforms.uCurl, curl.attach(1));
    gl.uniform1f(p.uniforms.curl, CURL_STRENGTH);
    gl.uniform1f(p.uniforms.dt, dt);
    blit(velocity.write);
    velocity.swap();

    // Project to a divergence-free field.
    p = programs.divergence;
    p.bind();
    gl.uniform2f(p.uniforms.texelSize, simTexel[0], simTexel[1]);
    gl.uniform1i(p.uniforms.uVelocity, velocity.read.attach(0));
    blit(divergence);

    p = programs.pressure;
    p.bind();
    gl.uniform2f(p.uniforms.texelSize, simTexel[0], simTexel[1]);
    gl.uniform1i(p.uniforms.uDivergence, divergence.attach(0));
    gl.uniform1i(p.uniforms.uPressure, pressure.read.attach(1));
    for (var i = 0; i < PRESSURE_ITER; i++) {
      gl.uniform1i(p.uniforms.uPressure, pressure.read.attach(0));
      blit(pressure.write);
      pressure.swap();
    }

    p = programs.gradient;
    p.bind();
    gl.uniform2f(p.uniforms.texelSize, simTexel[0], simTexel[1]);
    gl.uniform1i(p.uniforms.uPressure, pressure.read.attach(0));
    gl.uniform1i(p.uniforms.uVelocity, velocity.read.attach(1));
    blit(velocity.write);
    velocity.swap();

    // Advect velocity, then the dye it carries.
    p = programs.advection;
    p.bind();
    gl.uniform2f(p.uniforms.texelSize, simTexel[0], simTexel[1]);
    gl.uniform1i(p.uniforms.uVelocity, velocity.read.attach(0));
    gl.uniform1i(p.uniforms.uSource, velocity.read.attach(0));
    gl.uniform1f(p.uniforms.dt, dt);
    gl.uniform1f(p.uniforms.dissipation, VELOCITY_DISSIPATION);
    blit(velocity.write);
    velocity.swap();

    var dyeTexel = [dye.texelSizeX, dye.texelSizeY];
    gl.uniform2f(p.uniforms.texelSize, dyeTexel[0], dyeTexel[1]);
    gl.uniform1i(p.uniforms.uVelocity, velocity.read.attach(0));
    gl.uniform1i(p.uniforms.uSource, dye.read.attach(1));
    gl.uniform1f(p.uniforms.dissipation, DENSITY_DISSIPATION);
    blit(dye.write);
    dye.swap();
  }

  function render() {
    var p = programs.display;
    p.bind();
    gl.uniform1i(p.uniforms.uTexture, dye.read.attach(0));
    gl.uniform2f(p.uniforms.resolution, canvas.width, canvas.height);
    blit(null);
  }

  /* ── Currents ─────────────────────────────────────────────────────────── */

  /* Ink is not thrown at the screen, it is drawn through it. A few emitters
     drift along slow arcs, laying dye down every frame; advection and vorticity
     turn those lines into filaments, and the solver does the rest. */
  var emitters = [];

  function makeEmitter(i) {
    var angle = (i / 5) * Math.PI * 2 + Math.random();
    return {
      x: 0.5 + Math.cos(angle) * (0.16 + Math.random() * 0.22),
      y: 0.5 + Math.sin(angle) * (0.14 + Math.random() * 0.2),
      a: angle + Math.PI * 0.5,
      spin: (Math.random() < 0.5 ? -1 : 1) * (0.22 + Math.random() * 0.5),
      speed: 0.1 + Math.random() * 0.14,
      color: PALETTE[i % PALETTE.length],
      ink: 0.45 + Math.random() * 0.4,
      radius: 0.00042 + Math.random() * 0.0006,
      force: 560 + Math.random() * 520
    };
  }

  function resetEmitters() {
    emitters = [];
    for (var i = 0; i < 5; i++) emitters.push(makeEmitter(i));
  }

  function emit(dt) {
    for (var i = 0; i < emitters.length; i++) {
      var e = emitters[i];
      e.a += e.spin * dt;
      e.x += Math.cos(e.a) * e.speed * dt;
      e.y += Math.sin(e.a) * e.speed * dt;

      // Turn back at the edges instead of piling ink up against them.
      if (e.x < 0.06 || e.x > 0.94) { e.a = Math.PI - e.a; e.x = Math.min(0.94, Math.max(0.06, e.x)); }
      if (e.y < 0.06 || e.y > 0.94) { e.a = -e.a; e.y = Math.min(0.94, Math.max(0.06, e.y)); }

      var c = e.color;
      var k = e.ink * 0.52;
      splat(e.x, e.y,
        Math.cos(e.a) * e.force,
        Math.sin(e.a) * e.force,
        [c[0] * k, c[1] * k, c[2] * k],
        e.radius);
    }
  }

  function seedField() {
    resetEmitters();
    // Let the first ribbons form before anyone sees the page.
    for (var s = 0; s < 34; s++) { emit(0.02); step(0.02); }
  }

  /* ── Life ─────────────────────────────────────────────────────────────── */

  var lastTime = 0;
  var raf = null;
  var visible = true;
  var frames = 0;

  function frame(now) {
    raf = requestAnimationFrame(frame);
    if (!visible || document.hidden) { lastTime = now; return; }
    var dt = Math.min((now - lastTime) / 1000 || 0.016, 0.033);
    lastTime = now;
    emit(dt);
    step(dt);
    render();
    frames++;
  }

  function start() {
    resize();
    seedField();
    render();
    canvas.classList.add("ready");

    if (reduceMotion) return; // one still frame of ink, no animation

    lastTime = performance.now();
    raf = requestAnimationFrame(frame);
  }

  /* ── Pointer & device ─────────────────────────────────────────────────── */

  function pointerStart(e) {
    var rect = canvas.getBoundingClientRect();
    var x = (e.clientX - rect.left) / rect.width;
    var y = 1 - (e.clientY - rect.top) / rect.height;
    var a = Math.random() * Math.PI * 2;
    splat(x, y, Math.cos(a) * 1800, Math.sin(a) * 1800, pickColor(0.9), SPLAT_RADIUS * 1.8);
  }

  var px = 0, py = 0, hasPointer = false;

  function pointerMove(e) {
    var rect = canvas.getBoundingClientRect();
    var x = (e.clientX - rect.left) / rect.width;
    var y = 1 - (e.clientY - rect.top) / rect.height;
    if (!hasPointer) { px = x; py = y; hasPointer = true; return; }
    var dx = (x - px) * 5200;
    var dy = (y - py) * 5200;
    px = x; py = y;
    if (Math.abs(dx) + Math.abs(dy) < 1) return;
    splat(x, y, dx, dy, pickColor(0.42), SPLAT_RADIUS * 1.1);
  }

  if (!reduceMotion) {
    canvas.addEventListener("pointerdown", pointerStart);
    canvas.addEventListener("pointermove", pointerMove);
    canvas.addEventListener("pointerleave", function () { hasPointer = false; });
  }

  if ("IntersectionObserver" in window) {
    new IntersectionObserver(function (entries) {
      visible = entries[0].isIntersecting;
    }, { threshold: 0 }).observe(canvas);
  }

  var resizeTimer = null;
  window.addEventListener("resize", function () {
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(function () {
      if (resize() && !reduceMotion) seedField();
      render();
    }, 220);
  });

  canvas.addEventListener("webglcontextlost", function (e) {
    e.preventDefault();
    if (raf) cancelAnimationFrame(raf);
    bail("context lost");
  });

  try {
    start();
  } catch (err) {
    bail(err.message);
  }

  // Small hook so the page can be checked automatically.
  window.__fluid = { ok: true, frames: function () { return frames; } };
})();
