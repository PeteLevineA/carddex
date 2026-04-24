import { createIcons, Box, Layers3, Maximize2, Minimize2, Pause, Play, RotateCcw, ScanLine, Sparkles, SunMedium } from "lucide";
import "./style.css";
import { CardScene } from "./render/CardScene.js";
import { HOLO_PATTERNS, patternLabels } from "./data/cards.js";

const app = document.querySelector("#app");

if (!app) {
  throw new Error("Missing #app root");
}

const state = {
  cards: [],
  selected: undefined,
  expanded: false,
  autoRotate: false,
  activePattern: undefined,
  foilStrength: 1,
  depthScale: 0.12,
};

let scene;

async function bootstrap() {
  state.cards = await loadCatalog();
  state.selected = state.cards[0];
  state.activePattern = state.selected?.holoPattern;
  state.foilStrength = state.selected?.foilStrength ?? 1;
  state.depthScale = state.selected?.depthScale ?? 0.12;
  renderShell();

  const canvas = document.querySelector("#card-scene");
  if (!canvas || !state.selected) return;

  scene = new CardScene(canvas);
  scene.onArtworkClick = () => setExpanded(!state.expanded);
  scene.onStateChange = ({ rotationX, rotationY, expanded }) => {
    state.expanded = expanded;
    updateReadout(rotationX, rotationY);
    updateExpandButton();
  };
  await scene.setCard(state.selected);
  scene.animate();

  window.addEventListener("resize", () => scene.resize());
  hydrateIcons();
  bindControls();
  updateInspector();
}

async function loadCatalog() {
  const response = await fetch("/cards/catalog.json");
  if (!response.ok) {
    throw new Error("Unable to load /cards/catalog.json");
  }
  return response.json();
}

function renderShell() {
  app.innerHTML = `
    <aside class="library-panel">
      <div class="brand-row">
        <span class="brand-mark" aria-hidden="true"></span>
        <div>
          <h1>Card Lightbox</h1>
          <p>${state.cards.length} processed cards</p>
        </div>
      </div>
      <label class="search">
        <i data-lucide="scan-line" aria-hidden="true"></i>
        <input id="card-search" type="search" placeholder="Search cards" />
      </label>
      <div id="card-list" class="card-list"></div>
    </aside>

    <main class="viewer-panel">
      <div class="scene-shell">
        <canvas id="card-scene" aria-label="3D Pokemon card viewer"></canvas>
        <div class="scene-vignette" aria-hidden="true"></div>
      </div>
      <section class="hud hud-top" aria-label="Viewer controls">
        <div class="hud-cluster">
          <span class="status-dot"></span>
          <div>
            <span class="micro-label">Pattern</span>
            <strong id="hud-pattern">${state.selected ? patternLabels[state.selected.holoPattern] : "None"}</strong>
          </div>
        </div>
        <div class="hud-cluster">
          <i data-lucide="layers-3" aria-hidden="true"></i>
          <div>
            <span class="micro-label">Depth</span>
            <strong id="hud-depth">${state.depthScale.toFixed(2)}</strong>
          </div>
        </div>
        <div class="hud-controls">
          <button class="icon-button" id="reset-view" type="button" title="Reset view" aria-label="Reset view">
            <i data-lucide="rotate-ccw" aria-hidden="true"></i>
          </button>
          <button class="icon-button" id="auto-rotate" type="button" title="Auto rotate" aria-label="Auto rotate">
            <i data-lucide="play" aria-hidden="true"></i>
          </button>
          <button class="icon-button wide" id="toggle-expand" type="button" title="Expand artwork" aria-label="Expand artwork">
            <i data-lucide="maximize-2" aria-hidden="true"></i>
            <span>Art</span>
          </button>
        </div>
      </section>
      <section class="hud hud-bottom" aria-label="Rotation status">
        <span id="rotation-x">X -0.08</span>
        <span id="rotation-y">Y 0.22</span>
        <span id="mode-label">Card</span>
      </section>
    </main>

    <aside class="inspector-panel">
      <section class="selected-card" id="selected-card"></section>
      <section class="control-block">
        <div class="control-title">
          <i data-lucide="sparkles" aria-hidden="true"></i>
          <span>Foil Family</span>
        </div>
        <div class="pattern-grid" id="pattern-grid"></div>
      </section>
      <section class="control-block">
        <label class="slider-row">
          <span><i data-lucide="sun-medium" aria-hidden="true"></i> Foil</span>
          <output id="foil-output">${state.foilStrength.toFixed(2)}</output>
          <input id="foil-strength" type="range" min="0" max="2" step="0.01" value="${state.foilStrength}" />
        </label>
        <label class="slider-row">
          <span><i data-lucide="box" aria-hidden="true"></i> Depth</span>
          <output id="depth-output">${state.depthScale.toFixed(2)}</output>
          <input id="depth-scale" type="range" min="0" max="0.28" step="0.005" value="${state.depthScale}" />
        </label>
      </section>
    </aside>
  `;

  renderCardList("");
  renderPatternGrid();
}

function renderCardList(filter) {
  const list = document.querySelector("#card-list");
  if (!list) return;
  const normalized = filter.trim().toLowerCase();
  const cards = state.cards.filter((card) => {
    const haystack = `${card.name} ${card.subtitle} ${card.set} ${card.rarity}`.toLowerCase();
    return haystack.includes(normalized);
  });
  list.innerHTML = cards
    .map(
      (card) => `
        <button class="library-card ${card.id === state.selected?.id ? "active" : ""}" type="button" data-card-id="${card.id}">
          <img src="${card.image}" alt="${card.name}" />
          <span>
            <strong>${card.name}</strong>
            <small>${patternLabels[card.holoPattern]} / ${card.rarity}</small>
          </span>
        </button>
      `,
    )
    .join("");
}

function renderPatternGrid() {
  const grid = document.querySelector("#pattern-grid");
  if (!grid) return;
  grid.innerHTML = HOLO_PATTERNS.map(
    (pattern) => `
      <button class="pattern-chip ${pattern === state.activePattern ? "active" : ""}" type="button" data-pattern="${pattern}">
        ${patternLabels[pattern]}
      </button>
    `,
  ).join("");
}

function bindControls() {
  document.querySelector("#card-list")?.addEventListener("click", async (event) => {
    const button = event.target.closest("[data-card-id]");
    if (!button) return;
    const next = state.cards.find((card) => card.id === button.dataset.cardId);
    if (!next) return;
    state.selected = next;
    state.activePattern = next.holoPattern;
    state.foilStrength = next.foilStrength;
    state.depthScale = next.depthScale;
    await scene.setCard(next);
    scene.setFoilStrength(state.foilStrength);
    scene.setDepthScale(state.depthScale);
    renderCardList(document.querySelector("#card-search")?.value ?? "");
    renderPatternGrid();
    updateInspector();
    hydrateIcons();
  });

  document.querySelector("#card-search")?.addEventListener("input", (event) => {
    renderCardList(event.target.value);
  });

  document.querySelector("#pattern-grid")?.addEventListener("click", (event) => {
    const button = event.target.closest("[data-pattern]");
    if (!button) return;
    state.activePattern = button.dataset.pattern;
    scene.setPattern(state.activePattern);
    renderPatternGrid();
    updateInspector();
  });

  document.querySelector("#reset-view")?.addEventListener("click", () => scene.resetView());

  document.querySelector("#auto-rotate")?.addEventListener("click", () => {
    state.autoRotate = !state.autoRotate;
    scene.setAutoRotate(state.autoRotate);
    const button = document.querySelector("#auto-rotate");
    if (!button) return;
    button.innerHTML = state.autoRotate
      ? `<i data-lucide="pause" aria-hidden="true"></i>`
      : `<i data-lucide="play" aria-hidden="true"></i>`;
    button.setAttribute("aria-label", state.autoRotate ? "Pause auto rotate" : "Auto rotate");
    button.setAttribute("title", state.autoRotate ? "Pause auto rotate" : "Auto rotate");
    hydrateIcons();
  });

  document.querySelector("#toggle-expand")?.addEventListener("click", () => {
    setExpanded(!state.expanded);
  });

  document.querySelector("#foil-strength")?.addEventListener("input", (event) => {
    state.foilStrength = Number(event.target.value);
    scene.setFoilStrength(state.foilStrength);
    const output = document.querySelector("#foil-output");
    if (output) output.value = state.foilStrength.toFixed(2);
  });

  document.querySelector("#depth-scale")?.addEventListener("input", (event) => {
    state.depthScale = Number(event.target.value);
    scene.setDepthScale(state.depthScale);
    const output = document.querySelector("#depth-output");
    const hud = document.querySelector("#hud-depth");
    if (output) output.value = state.depthScale.toFixed(2);
    if (hud) hud.textContent = state.depthScale.toFixed(2);
  });
}

function setExpanded(expanded) {
  state.expanded = expanded;
  scene.setExpanded(expanded);
  updateExpandButton();
  updateInspector();
}

function updateExpandButton() {
  const button = document.querySelector("#toggle-expand");
  const mode = document.querySelector("#mode-label");
  if (!button) return;
  button.innerHTML = state.expanded
    ? `<i data-lucide="minimize-2" aria-hidden="true"></i><span>Card</span>`
    : `<i data-lucide="maximize-2" aria-hidden="true"></i><span>Art</span>`;
  button.setAttribute("aria-label", state.expanded ? "Return to card" : "Expand artwork");
  button.setAttribute("title", state.expanded ? "Return to card" : "Expand artwork");
  if (mode) mode.textContent = state.expanded ? "Expanded Art" : "Card";
  hydrateIcons();
}

function updateReadout(rotationX, rotationY) {
  const x = document.querySelector("#rotation-x");
  const y = document.querySelector("#rotation-y");
  if (x) x.textContent = `X ${rotationX.toFixed(2)}`;
  if (y) y.textContent = `Y ${rotationY.toFixed(2)}`;
}

function updateInspector() {
  if (!state.selected) return;
  const selected = document.querySelector("#selected-card");
  const pattern = document.querySelector("#hud-pattern");
  const depth = document.querySelector("#hud-depth");
  const foilInput = document.querySelector("#foil-strength");
  const depthInput = document.querySelector("#depth-scale");
  const foilOutput = document.querySelector("#foil-output");
  const depthOutput = document.querySelector("#depth-output");

  if (selected) {
    selected.innerHTML = `
      <img src="${state.expanded ? state.selected.expandedImage : state.selected.image}" alt="${state.selected.name}" />
      <div>
        <span class="micro-label">${state.selected.set} #${state.selected.number}</span>
        <h2>${state.selected.name}</h2>
        <p>${state.selected.subtitle}</p>
        <dl>
          <div><dt>Rarity</dt><dd>${state.selected.rarity}</dd></div>
          <div><dt>Foil</dt><dd>${patternLabels[state.activePattern ?? state.selected.holoPattern]}</dd></div>
          <div><dt>Coverage</dt><dd>${state.expanded ? "Expanded" : state.selected.holoCoverage}</dd></div>
        </dl>
      </div>
    `;
  }

  if (pattern) pattern.textContent = patternLabels[state.activePattern ?? state.selected.holoPattern];
  if (depth) depth.textContent = state.depthScale.toFixed(2);
  if (foilInput) foilInput.value = String(state.foilStrength);
  if (depthInput) depthInput.value = String(state.depthScale);
  if (foilOutput) foilOutput.value = state.foilStrength.toFixed(2);
  if (depthOutput) depthOutput.value = state.depthScale.toFixed(2);
}

function hydrateIcons() {
  createIcons({
    icons: {
      Box,
      Layers3,
      Maximize2,
      Minimize2,
      Pause,
      Play,
      RotateCcw,
      ScanLine,
      Sparkles,
      SunMedium,
    },
  });
}

bootstrap().catch((error) => {
  app.innerHTML = `<pre class="boot-error">${error instanceof Error ? error.message : String(error)}</pre>`;
});
