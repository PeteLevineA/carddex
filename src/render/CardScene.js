import {
  ACESFilmicToneMapping,
  BoxGeometry,
  Color,
  Group,
  LinearSRGBColorSpace,
  Mesh,
  MeshBasicMaterial,
  PerspectiveCamera,
  PlaneGeometry,
  Raycaster,
  Scene,
  ShaderMaterial,
  SRGBColorSpace,
  TextureLoader,
  Vector2,
  Vector3,
  Vector4,
  WebGLRenderer,
} from "three";
import { coverageId, patternId } from "../data/cards.js";
import { frontFragmentShader, frontVertexShader } from "./shaders.js";

const CARD_WIDTH = 2.5;
const CARD_HEIGHT = 3.5;

export class CardScene {
  constructor(canvas) {
    this.canvas = canvas;
    this.scene = new Scene();
    this.camera = new PerspectiveCamera(38, 1, 0.1, 100);
    this.textureLoader = new TextureLoader();
    this.raycaster = new Raycaster();
    this.pointer = new Vector2();
    this.lightPosition = new Vector3(-2.2, 2.7, 4.4);
    this.foilHotspot = new Vector2(0.54, 0.58);
    this.foilReveal = 0.72;
    this.foilFocus = 0.36;
    this.expanded = false;
    this.autoRotate = false;
    this.targetRotation = new Vector2(-0.08, 0.22);
    this.currentRotation = new Vector2(-0.08, 0.22);
    this.dragStart = new Vector2();
    this.lastPointer = new Vector2();
    this.isDragging = false;
    this.clickCandidate = false;
    this.startedAt = performance.now();

    this.renderer = new WebGLRenderer({
      canvas,
      antialias: true,
      alpha: true,
      powerPreference: "high-performance",
    });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.toneMapping = ACESFilmicToneMapping;
    this.renderer.toneMappingExposure = 1.04;
    this.scene.background = new Color(0x08090b);
    this.camera.position.set(0, 0, 6.2);

    this.bindPointerEvents();
    this.resize();
  }

  async setCard(card) {
    this.card = card;
    this.expanded = false;
    this.textures = await this.loadTextures(card);
    this.rebuildMeshes();
    this.notifyState();
  }

  setExpanded(expanded) {
    if (!this.card || !this.textures || !this.frontMesh) return;
    this.expanded = expanded;
    this.applyTextures();
    this.notifyState();
  }

  toggleExpanded() {
    this.setExpanded(!this.expanded);
  }

  setAutoRotate(enabled) {
    this.autoRotate = enabled;
  }

  setFoilStrength(value) {
    if (!this.frontMesh) return;
    this.frontMesh.material.uniforms.uFoilStrength.value = value;
  }

  setFoilReveal(value) {
    this.foilReveal = value;
    if (!this.frontMesh) return;
    this.frontMesh.material.uniforms.uFoilReveal.value = value;
  }

  setFoilFocus(value) {
    this.foilFocus = value;
    if (!this.frontMesh) return;
    this.frontMesh.material.uniforms.uFoilFocus.value = value;
  }

  setFoilHotspot(x, y) {
    this.foilHotspot.set(x, y);
    if (!this.frontMesh) return;
    this.frontMesh.material.uniforms.uFoilHotspot.value.copy(this.foilHotspot);
  }

  setLightPosition(x, y, z) {
    this.lightPosition.set(x, y, z);
    if (!this.frontMesh) return;
    this.frontMesh.material.uniforms.uLightPosition.value.copy(this.lightPosition);
  }

  setDepthScale(value) {
    if (!this.frontMesh) return;
    this.frontMesh.material.uniforms.uDepthScale.value = this.expanded ? value * 1.35 : value;
  }

  setPattern(pattern) {
    if (!this.frontMesh) return;
    this.frontMesh.material.uniforms.uPattern.value = patternId[pattern];
  }

  resetView() {
    this.targetRotation.set(-0.08, 0.22);
    this.currentRotation.copy(this.targetRotation);
    this.notifyState();
  }

  resize() {
    const rect = this.canvas.getBoundingClientRect();
    const width = Math.max(1, rect.width);
    const height = Math.max(1, rect.height);
    this.camera.aspect = width / height;
    this.camera.updateProjectionMatrix();
    this.renderer.setSize(width, height, false);
  }

  animate = () => {
    const elapsed = (performance.now() - this.startedAt) / 1000;
    if (this.autoRotate && !this.isDragging) {
      this.targetRotation.y += 0.006;
      this.targetRotation.x = Math.sin(elapsed * 0.5) * 0.12;
    }

    this.currentRotation.lerp(this.targetRotation, 0.09);
    if (this.frontMesh && this.cardGroup) {
      const scale = this.expanded ? 1.12 : 1;
      this.cardGroup.rotation.x = this.currentRotation.x;
      this.cardGroup.rotation.y = this.currentRotation.y;
      this.cardGroup.scale.setScalar(scale);
      this.frontMesh.material.uniforms.uTime.value = elapsed;
      this.frontMesh.material.uniforms.uMouse.value.set(this.pointer.x, this.pointer.y);
    }

    this.renderer.render(this.scene, this.camera);
    requestAnimationFrame(this.animate);
  };

  async loadTextures(card) {
    const [front, depth, expanded, expandedDepth] = await Promise.all([
      this.textureLoader.loadAsync(card.image),
      this.textureLoader.loadAsync(card.depth),
      this.textureLoader.loadAsync(card.expandedImage),
      this.textureLoader.loadAsync(card.expandedDepth),
    ]);
    front.colorSpace = SRGBColorSpace;
    expanded.colorSpace = SRGBColorSpace;
    depth.colorSpace = LinearSRGBColorSpace;
    expandedDepth.colorSpace = LinearSRGBColorSpace;
    for (const texture of [front, depth, expanded, expandedDepth]) {
      texture.anisotropy = Math.min(8, this.renderer.capabilities.getMaxAnisotropy());
    }
    return { card: front, depth, expanded, expandedDepth };
  }

  rebuildMeshes() {
    if (!this.card || !this.textures) return;
    if (this.cardGroup) this.scene.remove(this.cardGroup);

    const geometry = new PlaneGeometry(CARD_WIDTH, CARD_HEIGHT, 150, 210);
    const uniforms = {
      uCardTexture: { value: this.textures.card },
      uDepthMap: { value: this.textures.depth },
      uTime: { value: 0 },
      uFoilStrength: { value: this.card.foilStrength },
      uFoilReveal: { value: this.foilReveal },
      uFoilFocus: { value: this.foilFocus },
      uExposure: { value: 1 },
      uPattern: { value: patternId[this.card.holoPattern] },
      uCoverage: { value: coverageId[this.card.holoCoverage] },
      uArtRect: { value: new Vector4() },
      uLightPosition: { value: this.lightPosition.clone() },
      uMouse: { value: new Vector2() },
      uFoilHotspot: { value: this.foilHotspot.clone() },
      uDepthScale: { value: this.card.depthScale },
      uCurve: { value: 0.024 },
      uExpanded: { value: 0 },
    };

    const material = new ShaderMaterial({
      uniforms,
      vertexShader: frontVertexShader,
      fragmentShader: frontFragmentShader,
      transparent: true,
    });
    this.frontMesh = new Mesh(geometry, material);
    this.frontMesh.position.z = 0.032;

    const backMaterial = new MeshBasicMaterial({ color: 0x153f8c });
    this.backMesh = new Mesh(new PlaneGeometry(CARD_WIDTH, CARD_HEIGHT, 1, 1), backMaterial);
    this.backMesh.rotation.y = Math.PI;
    this.backMesh.position.z = -0.032;

    const edgeMaterial = new MeshBasicMaterial({ color: 0x12100e });
    this.edgeMesh = new Mesh(new BoxGeometry(CARD_WIDTH, CARD_HEIGHT, 0.055), edgeMaterial);
    this.edgeMesh.renderOrder = -1;

    this.cardGroup = new Group();
    this.cardGroup.add(this.edgeMesh, this.backMesh, this.frontMesh);
    this.scene.add(this.cardGroup);
    this.applyTextures();
  }

  applyTextures() {
    if (!this.card || !this.textures || !this.frontMesh) return;
    const uniforms = this.frontMesh.material.uniforms;
    uniforms.uCardTexture.value = this.expanded ? this.textures.expanded : this.textures.card;
    uniforms.uDepthMap.value = this.expanded ? this.textures.expandedDepth : this.textures.depth;
    uniforms.uDepthScale.value = this.expanded ? this.card.depthScale * 1.35 : this.card.depthScale;
    uniforms.uFoilStrength.value = this.expanded ? this.card.foilStrength * 1.08 : this.card.foilStrength;
    uniforms.uExpanded.value = this.expanded ? 1 : 0;
    uniforms.uCoverage.value = this.expanded ? 1 : coverageId[this.card.holoCoverage];
    const rect = this.expanded ? { x: 0, y: 0, w: 1, h: 1 } : this.card.artworkRegion;
    uniforms.uArtRect.value.set(rect.x, rect.y, rect.w, rect.h);
  }

  bindPointerEvents() {
    this.canvas.addEventListener("pointerdown", (event) => {
      this.isDragging = true;
      this.clickCandidate = true;
      this.dragStart.set(event.clientX, event.clientY);
      this.lastPointer.copy(this.dragStart);
      this.canvas.setPointerCapture(event.pointerId);
    });

    this.canvas.addEventListener("pointermove", (event) => {
      const rect = this.canvas.getBoundingClientRect();
      this.pointer.x = ((event.clientX - rect.left) / rect.width) * 2 - 1;
      this.pointer.y = -(((event.clientY - rect.top) / rect.height) * 2 - 1);

      if (!this.isDragging) return;
      const dx = event.clientX - this.lastPointer.x;
      const dy = event.clientY - this.lastPointer.y;
      this.lastPointer.set(event.clientX, event.clientY);
      this.targetRotation.y += dx * 0.009;
      this.targetRotation.x = clamp(this.targetRotation.x + dy * 0.006, -0.9, 0.9);
      if (this.dragStart.distanceTo(this.lastPointer) > 5) {
        this.clickCandidate = false;
      }
      this.notifyState();
    });

    this.canvas.addEventListener("pointerup", (event) => {
      this.isDragging = false;
      this.canvas.releasePointerCapture(event.pointerId);
      if (this.clickCandidate) {
        this.handleCanvasClick(event.clientX, event.clientY);
      }
      this.clickCandidate = false;
    });

    this.canvas.addEventListener(
      "wheel",
      (event) => {
        event.preventDefault();
        this.camera.position.z = clamp(this.camera.position.z + event.deltaY * 0.002, 4.5, 8.0);
      },
      { passive: false },
    );
  }

  handleCanvasClick(clientX, clientY) {
    if (!this.frontMesh || !this.card) return;
    const rect = this.canvas.getBoundingClientRect();
    const mouse = new Vector2(
      ((clientX - rect.left) / rect.width) * 2 - 1,
      -(((clientY - rect.top) / rect.height) * 2 - 1),
    );
    this.raycaster.setFromCamera(mouse, this.camera);
    const hit = this.raycaster.intersectObject(this.frontMesh)[0];
    if (!hit?.uv) return;
    const target = this.expanded ? { x: 0, y: 0, w: 1, h: 1 } : this.card.artworkRegion;
    const inArtwork =
      hit.uv.x >= target.x &&
      hit.uv.x <= target.x + target.w &&
      hit.uv.y >= target.y &&
      hit.uv.y <= target.y + target.h;
    if (inArtwork) {
      this.onArtworkClick?.();
    }
  }

  notifyState() {
    this.onStateChange?.({
      rotationX: this.currentRotation.x,
      rotationY: this.currentRotation.y,
      expanded: this.expanded,
    });
  }
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}
