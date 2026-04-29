// Re-export the canonical shader source from the web app. Keeping a single
// copy avoids accidental drift between targets; the iOS Metal port reads the
// same strings (via a build-time extract) when running shader-parity tests.
export {
  frontVertexShader,
  frontFragmentShader,
  // expanded shaders are also re-exported when the web app defines them.
} from "../../../apps/web/src/render/shaders.js";
