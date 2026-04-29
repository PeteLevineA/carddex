# @carddex/shaders

Canonical GLSL source for the Carddex holofoil renderer.

The web app at `apps/web/` is the source of truth for this GLSL. This package
re-exports those strings so that:

1. The Node-side build can extract them and produce a `shaders.h` Metal header
   for the iOS app's `CarddexHolofoil` target.
2. Shader-parity tests (golden screenshots) can pin the GLSL hash to the MSL
   port and fail CI when the two diverge unintentionally.

## Patterns

Each holofoil "family" defined in the GLSL must have a matching MSL function
in `apps/ios/Carddex/Sources/CarddexHolofoil/Shaders/Holofoil.metal`:

- `starlight`
- `cosmos`
- `tinsel`
- `sheen`
- `cracked-ice`
- `crosshatch`
- `water-web`
- `sequin`
- `fireworks`
- `plain`
