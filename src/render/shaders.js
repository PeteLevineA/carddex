export const frontVertexShader = `
  varying vec2 vUv;
  varying vec3 vWorldPosition;
  varying vec3 vWorldNormal;

  uniform sampler2D uDepthMap;
  uniform float uDepthScale;
  uniform float uCurve;

  void main() {
    vUv = uv;

    vec3 p = position;
    float depth = texture2D(uDepthMap, uv).r;
    vec2 centered = uv - 0.5;
    float cardMask = smoothstep(0.0, 0.045, uv.x) *
      smoothstep(0.0, 0.045, uv.y) *
      smoothstep(0.0, 0.045, 1.0 - uv.x) *
      smoothstep(0.0, 0.045, 1.0 - uv.y);
    float gentleBow = (1.0 - dot(centered, centered) * 3.0) * uCurve;
    p.z += ((depth - 0.28) * uDepthScale + gentleBow) * cardMask;

    vec4 worldPosition = modelMatrix * vec4(p, 1.0);
    vWorldPosition = worldPosition.xyz;
    vWorldNormal = normalize(mat3(modelMatrix) * normal);
    gl_Position = projectionMatrix * viewMatrix * worldPosition;
  }
`;

export const frontFragmentShader = `
  precision highp float;

  varying vec2 vUv;
  varying vec3 vWorldPosition;
  varying vec3 vWorldNormal;

  uniform sampler2D uCardTexture;
  uniform sampler2D uDepthMap;
  uniform float uTime;
  uniform float uFoilStrength;
  uniform float uFoilReveal;
  uniform float uFoilFocus;
  uniform float uExposure;
  uniform int uPattern;
  uniform int uCoverage;
  uniform vec4 uArtRect;
  uniform vec3 uLightPosition;
  uniform vec2 uMouse;
  uniform vec2 uFoilHotspot;
  uniform float uExpanded;

  float hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
  }

  vec3 spectral(float t) {
    vec3 phase = vec3(0.0, 0.34, 0.67);
    return 0.54 + 0.46 * cos(6.28318 * (phase + t));
  }

  float rectMask(vec2 uv, vec4 rect) {
    float left = smoothstep(rect.x, rect.x + 0.015, uv.x);
    float right = 1.0 - smoothstep(rect.x + rect.z - 0.015, rect.x + rect.z, uv.x);
    float bottom = smoothstep(rect.y, rect.y + 0.015, uv.y);
    float top = 1.0 - smoothstep(rect.y + rect.w - 0.015, rect.y + rect.w, uv.y);
    return clamp(left * right * top * bottom, 0.0, 1.0);
  }

  float coverageMask(vec2 uv) {
    float art = rectMask(uv, uArtRect);
    if (uCoverage == 1) {
      return 1.0;
    }
    if (uCoverage == 2) {
      return clamp(1.0 - art * 0.92, 0.0, 1.0);
    }
    return art;
  }

  float starShape(vec2 p) {
    vec2 a = abs(p);
    float core = smoothstep(0.06, 0.0, length(p));
    float vertical = smoothstep(0.018, 0.0, a.x) * smoothstep(0.18, 0.0, a.y);
    float horizontal = smoothstep(0.018, 0.0, a.y) * smoothstep(0.18, 0.0, a.x);
    float diagonalA = smoothstep(0.012, 0.0, abs(p.x - p.y)) * smoothstep(0.13, 0.0, length(p));
    float diagonalB = smoothstep(0.012, 0.0, abs(p.x + p.y)) * smoothstep(0.13, 0.0, length(p));
    return clamp(core + vertical + horizontal + diagonalA * 0.55 + diagonalB * 0.55, 0.0, 1.0);
  }

  float starlight(vec2 uv, float angle) {
    vec2 grid = uv * vec2(13.0, 18.0);
    vec2 cell = floor(grid);
    vec2 local = fract(grid) - 0.5;
    float seed = hash12(cell);
    local += vec2(seed - 0.5, hash12(cell + 7.1) - 0.5) * 0.45;
    float reveal = smoothstep(0.66, 1.0, sin(seed * 18.0 + angle * 4.8));
    return starShape(local) * reveal * step(0.52, seed);
  }

  float cosmosLayer(vec2 uv, float scale, float angle) {
    vec2 grid = uv * scale;
    vec2 cell = floor(grid);
    vec2 local = fract(grid) - 0.5;
    float seed = hash12(cell);
    float radius = mix(0.12, 0.34, hash12(cell + 4.0));
    float disc = smoothstep(radius, radius - 0.035, length(local));
    float ring = smoothstep(radius + 0.035, radius, length(local)) * smoothstep(radius - 0.085, radius - 0.045, length(local));
    float glint = smoothstep(0.55, 1.0, sin(seed * 12.0 + angle * 3.2));
    return (disc * 0.55 + ring * 0.65) * glint;
  }

  float tinsel(vec2 uv, float angle) {
    float fine = smoothstep(0.78, 1.0, sin((uv.y + angle * 0.02) * 130.0));
    float wide = smoothstep(0.35, 1.0, sin((uv.y - angle * 0.015) * 34.0));
    return fine * 0.42 + wide * 0.34;
  }

  float sheen(vec2 uv, float angle) {
    float diagonal = uv.x * 1.15 - uv.y * 0.82 + angle * 0.09;
    float band = smoothstep(0.82, 1.0, sin(diagonal * 31.0));
    float sweep = smoothstep(0.34, 0.95, sin(diagonal * 6.0 + angle * 1.7));
    return band * 0.35 + sweep * 0.7;
  }

  float crackedIce(vec2 uv, float angle) {
    float a = abs(sin((uv.x * 9.0 + uv.y * 15.0 + angle * 0.08) * 3.14159));
    float b = abs(sin((uv.x * 17.0 - uv.y * 7.0 - angle * 0.05) * 3.14159));
    float c = abs(sin((uv.x * 5.0 - uv.y * 21.0 + angle * 0.03) * 3.14159));
    float cracks = pow(1.0 - min(min(a, b), c), 11.0);
    float facets = smoothstep(0.55, 1.0, sin((uv.x * 8.0 + uv.y * 5.0) + angle));
    return cracks * 1.2 + facets * 0.28;
  }

  float crosshatch(vec2 uv, float angle) {
    float a = smoothstep(0.88, 1.0, sin((uv.x + uv.y + angle * 0.02) * 88.0));
    float b = smoothstep(0.88, 1.0, sin((uv.x - uv.y - angle * 0.02) * 88.0));
    return (a + b) * 0.48;
  }

  float waterWeb(vec2 uv, float angle) {
    float waveA = sin(uv.x * 22.0 + sin(uv.y * 18.0 + angle) * 1.8);
    float waveB = sin(uv.y * 28.0 + sin(uv.x * 16.0 - angle * 0.7) * 1.5);
    float web = smoothstep(0.78, 1.0, abs(waveA * waveB));
    return web * 0.72;
  }

  float sequin(vec2 uv, float angle) {
    vec2 grid = uv * vec2(17.0, 24.0);
    vec2 cell = floor(grid);
    vec2 local = fract(grid) - 0.5;
    float seed = hash12(cell);
    float disc = smoothstep(0.34, 0.26, length(local));
    float crescent = smoothstep(0.23, 0.18, length(local - vec2(0.08, -0.08)));
    float twinkle = smoothstep(0.18, 1.0, sin(seed * 10.0 + angle * 2.7));
    return disc * (0.38 + crescent * 0.5) * twinkle;
  }

  float fireworks(vec2 uv, float angle) {
    vec2 grid = uv * vec2(8.0, 12.0);
    vec2 cell = floor(grid);
    vec2 local = fract(grid) - 0.5;
    float seed = hash12(cell);
    float radial = abs(sin(atan(local.y, local.x) * mix(5.0, 9.0, seed)));
    float burst = smoothstep(0.85, 1.0, radial) * smoothstep(0.42, 0.04, length(local));
    return burst * smoothstep(0.45, 1.0, sin(seed * 15.0 + angle * 4.0));
  }

  float pattern(vec2 uv, float angle) {
    if (uPattern == 0) return starlight(uv, angle);
    if (uPattern == 1) return cosmosLayer(uv, 8.0, angle) + cosmosLayer(uv + 0.11, 17.0, angle) * 0.72;
    if (uPattern == 2) return tinsel(uv, angle);
    if (uPattern == 3) return sheen(uv, angle);
    if (uPattern == 4) return crackedIce(uv, angle);
    if (uPattern == 5) return crosshatch(uv, angle);
    if (uPattern == 6) return waterWeb(uv, angle);
    if (uPattern == 7) return sequin(uv, angle);
    if (uPattern == 8) return fireworks(uv, angle);
    return 0.35 + 0.25 * sin((uv.x + uv.y) * 42.0 + angle);
  }

  void main() {
    vec4 texel = texture2D(uCardTexture, vUv);
    vec3 base = texel.rgb;
    float depth = texture2D(uDepthMap, vUv).r;
    vec3 viewDir = normalize(cameraPosition - vWorldPosition);
    vec3 lightDir = normalize(uLightPosition - vWorldPosition);
    vec3 normal = normalize(vWorldNormal);

    float facing = clamp(dot(normal, viewDir), 0.0, 1.0);
    float grazing = pow(1.0 - facing, 1.6);
    float lambert = max(dot(normal, lightDir), 0.0);
    float spec = pow(max(dot(reflect(-lightDir, normal), viewDir), 0.0), 42.0);
    float angle = uTime * 0.8 + atan(viewDir.x, viewDir.z) * 2.4 + uMouse.x * 0.8 - uMouse.y * 0.25;

    float foilMask = coverageMask(vUv);
    float patternValue = pattern(vUv, angle);
    float focus = clamp(uFoilFocus, 0.0, 1.0);
    float reveal = clamp(uFoilReveal, 0.0, 1.0);
    float hotspotRadius = mix(1.12, 0.34, focus);
    float hotspot = 1.0 - smoothstep(0.0, hotspotRadius, distance(vUv, uFoilHotspot));
    float broadGrazing = smoothstep(0.015, 0.74, grazing);
    float broadSpec = smoothstep(0.0, 0.50, spec);
    float sweep = abs(sin(angle + depth * 8.0)) * mix(0.24, 0.12, focus);
    float revealBias = mix(-0.08, 0.42, reveal);
    float gateInput = broadGrazing * 0.58 + broadSpec * 0.74 + hotspot * 0.46 + sweep + revealBias;
    float gateLow = mix(0.34, 0.14, reveal);
    float gateHigh = mix(0.94, 0.56, reveal);
    float angleGate = smoothstep(gateLow, gateHigh, gateInput);
    angleGate = max(angleGate, reveal * mix(0.14, 0.34, 1.0 - focus));
    float focusedPattern = pow(max(patternValue, 0.0), mix(0.72, 1.55, focus));
    float foil = clamp(focusedPattern * foilMask * angleGate * uFoilStrength * mix(1.08, 1.62, reveal), 0.0, 1.72);

    vec3 rainbow = spectral(vUv.x * 0.66 + vUv.y * 0.35 + angle * 0.09 + depth * 0.28 + hotspot * 0.08);
    vec3 inkPreserve = mix(base, base * (0.75 + lambert * 0.35), 0.35);
    vec3 holo = inkPreserve + rainbow * foil * (0.64 + grazing * 1.30 + hotspot * 0.38);
    vec3 glint = vec3(1.0, 0.94, 0.72) * (spec * 0.75 + hotspot * foil * 0.08) * (0.65 + foilMask);
    vec3 color = mix(base, holo, clamp(foil * mix(0.58, 0.82, reveal), 0.0, 0.90)) + glint;
    color += base * lambert * 0.08 + depth * 0.035;
    color = pow(color * uExposure, vec3(0.92));

    gl_FragColor = vec4(color, texel.a);
  }
`;
