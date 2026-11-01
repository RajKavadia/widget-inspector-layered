/* global THREE */
(function () {
  const MIN_LAYER_GAP = 24;
  const DEFAULT_LAYER_GAP = 88;
  const MIN_BOX = 8;
  const MAX_MESHES = 90;
  const CARD_THICKNESS = 2.4;
  const SCREEN_GAP = 4;

  let layerGap = DEFAULT_LAYER_GAP;
  let scene = null;
  let camera = null;
  let controls = null;
  let renderer = null;
  let screenshotMesh = null;
  let screenshotTexture = null;
  let bezelMesh = null;
  let stems = null;
  let ground = null;
  const nodeMeshes = new Map();
  let nodesGroup = null;
  let snapshotData = null;
  let pickHandler = null;
  let pendingSnapshotJson = null;
  let booted = false;
  let snapshotGeneration = 0;
  let showScreenshot = true;
  let layerMode = 'multi';
  let suppressClickPick = false;
  let needsRender = true;
  let renderLoopId = 0;
  let selectedId = null;
  let hoveredId = null;
  let tooltip = null;
  let hint = null;
  const raycaster = new THREE.Raycaster();
  const pointer = new THREE.Vector2();
  const clock = new THREE.Clock();

  function requestRender() {
    needsRender = true;
  }

  function createStudioBackground() {
    const canvas = document.createElement('canvas');
    canvas.width = 8;
    canvas.height = 512;
    const ctx = canvas.getContext('2d');
    const gradient = ctx.createLinearGradient(0, 0, 0, 512);
    gradient.addColorStop(0, '#151821');
    gradient.addColorStop(0.45, '#0e1016');
    gradient.addColorStop(1, '#07080c');
    ctx.fillStyle = gradient;
    ctx.fillRect(0, 0, 8, 512);
    const texture = new THREE.CanvasTexture(canvas);
    texture.magFilter = THREE.LinearFilter;
    texture.minFilter = THREE.LinearFilter;
    return texture;
  }

  function createMapControls(cam, domElement) {
    const target = new THREE.Vector3(0, 0, 0);
    const spherical = new THREE.Spherical();
    const goal = new THREE.Spherical();
    spherical.setFromVector3(cam.position.clone().sub(target));
    goal.copy(spherical);

    let mode = null;
    let lastX = 0;
    let lastY = 0;
    let dragPixels = 0;
    const keys = new Set();

    function clampGoal() {
      goal.radius = Math.max(120, Math.min(14000, goal.radius));
      goal.phi = Math.max(0.18, Math.min(Math.PI * 0.78, goal.phi));
    }

    function applyNow() {
      clampGoal();
      spherical.copy(goal);
      const offset = new THREE.Vector3().setFromSpherical(spherical);
      cam.position.copy(target).add(offset);
      cam.lookAt(target);
      requestRender();
    }

    function panBy(dx, dy) {
      const distance = cam.position.distanceTo(target);
      const panScale = distance * 0.00145;
      const right = new THREE.Vector3().setFromMatrixColumn(cam.matrix, 0);
      const up = new THREE.Vector3().setFromMatrixColumn(cam.matrix, 1);
      target.addScaledVector(right, -dx * panScale);
      target.addScaledVector(up, dy * panScale);
      requestRender();
    }

    domElement.addEventListener('pointerdown', (event) => {
      dragPixels = 0;
      lastX = event.clientX;
      lastY = event.clientY;
      if (event.button === 2 || event.button === 1 || event.shiftKey) {
        mode = 'pan';
      } else if (event.button === 0) {
        mode = 'orbit';
      }
      domElement.setPointerCapture?.(event.pointerId);
    });

    domElement.addEventListener('pointermove', (event) => {
      if (!mode) return;
      const dx = event.clientX - lastX;
      const dy = event.clientY - lastY;
      dragPixels += Math.abs(dx) + Math.abs(dy);
      lastX = event.clientX;
      lastY = event.clientY;
      if (mode === 'pan') {
        panBy(dx, dy);
      } else {
        goal.theta -= dx * 0.0042;
        goal.phi -= dy * 0.0036;
        clampGoal();
        requestRender();
      }
    });

    function endDrag(event) {
      suppressClickPick = dragPixels > 5;
      mode = null;
      if (event?.pointerId != null) {
        try {
          domElement.releasePointerCapture(event.pointerId);
        } catch (_) {
          /* ignore */
        }
      }
    }

    domElement.addEventListener('pointerup', endDrag);
    domElement.addEventListener('pointercancel', endDrag);
    domElement.addEventListener('contextmenu', (event) => event.preventDefault());
    domElement.addEventListener(
      'wheel',
      (event) => {
        event.preventDefault();
        goal.radius *= event.deltaY > 0 ? 1.065 : 0.94;
        clampGoal();
        requestRender();
      },
      { passive: false },
    );

    window.addEventListener('keydown', (event) => {
      if (['KeyW', 'KeyA', 'KeyS', 'KeyD'].includes(event.code)) keys.add(event.code);
    });
    window.addEventListener('keyup', (event) => keys.delete(event.code));

    return {
      target,
      update(dt) {
        if (keys.has('KeyA')) panBy(-22, 0);
        if (keys.has('KeyD')) panBy(22, 0);
        if (keys.has('KeyW')) panBy(0, -22);
        if (keys.has('KeyS')) panBy(0, 22);
        const k = 1 - Math.exp(-10 * dt);
        spherical.theta += (goal.theta - spherical.theta) * k;
        spherical.phi += (goal.phi - spherical.phi) * k;
        spherical.radius += (goal.radius - spherical.radius) * k;
        const offset = new THREE.Vector3().setFromSpherical(spherical);
        cam.position.copy(target).add(offset);
        cam.lookAt(target);
        if (
          Math.abs(goal.theta - spherical.theta) > 0.0004 ||
          Math.abs(goal.radius - spherical.radius) > 0.2
        ) {
          requestRender();
        }
      },
      resetToStudio(distance, zMid) {
        target.set(0, -distance * 0.02, zMid);
        goal.radius = distance;
        goal.theta = 0.72;
        goal.phi = 1.18;
        applyNow();
      },
    };
  }

  function hostElement() {
    return document.querySelector('[id^="widgetscape-host-"]');
  }

  function showError(message) {
    const host = hostElement();
    if (!host) return;
    host.style.display = 'flex';
    host.style.alignItems = 'center';
    host.style.justifyContent = 'center';
    host.style.color = '#ff8a80';
    host.style.padding = '12px';
    host.style.fontFamily = 'sans-serif';
    host.textContent = message;
  }

  function ensureThreeLoaded() {
    if (typeof THREE === 'undefined') {
      showError('3D engine failed to load (THREE missing). Rebuild the extension web bundle.');
      return false;
    }
    return true;
  }

  function ensureHud(host) {
    host.style.background = '#0e1016';
    if (!tooltip) {
      tooltip = document.createElement('div');
      tooltip.style.cssText =
        'position:absolute;pointer-events:none;z-index:3;display:none;' +
        'padding:6px 10px;border-radius:8px;background:rgba(12,14,20,0.88);' +
        'color:#f3f5f8;font:12px/1.35 ui-sans-serif,system-ui,sans-serif;' +
        'border:1px solid rgba(255,255,255,0.08);backdrop-filter:blur(10px);' +
        'box-shadow:0 8px 24px rgba(0,0,0,0.35);max-width:300px;letter-spacing:0.01em;';
      host.appendChild(tooltip);
    }
    if (!hint) {
      hint = document.createElement('div');
      hint.style.cssText =
        'position:absolute;left:10px;bottom:10px;z-index:2;pointer-events:none;' +
        'color:rgba(230,234,240,0.48);font:11px/1.3 ui-sans-serif,system-ui,sans-serif;';
      hint.textContent = 'Drag to orbit · right-drag pan · scroll zoom';
      host.appendChild(hint);
    }
  }

  function cardColor(depth, local) {
    const t = Math.min((depth || 0) / 12, 1);
    if (local) {
      return new THREE.Color().setHSL(0.55 - t * 0.12, 0.62, 0.58);
    }
    return new THREE.Color().setHSL(0.62, 0.08, 0.42 + t * 0.08);
  }

  function initScene() {
    if (!ensureThreeLoaded()) return;
    const host = hostElement();
    if (!host || renderer) return;

    const width = host.clientWidth || 800;
    const height = host.clientHeight || 600;
    ensureHud(host);

    scene = new THREE.Scene();
    scene.background = createStudioBackground();
    scene.fog = new THREE.Fog(0x0b0d12, 1800, 11000);

    camera = new THREE.PerspectiveCamera(38, width / height, 2, 28000);
    camera.position.set(640, 220, 980);

    renderer = new THREE.WebGLRenderer({
      antialias: true,
      alpha: false,
      powerPreference: 'high-performance',
    });
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
    renderer.setSize(width, height);
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.05;
    renderer.domElement.style.display = 'block';
    host.appendChild(renderer.domElement);

    scene.add(new THREE.HemisphereLight(0xb9c7db, 0x141820, 1.15));
    const key = new THREE.DirectionalLight(0xfff4e5, 1.15);
    key.position.set(520, 740, 980);
    scene.add(key);
    const rim = new THREE.DirectionalLight(0x7ec8ff, 0.45);
    rim.position.set(-640, 120, -280);
    scene.add(rim);
    const fill = new THREE.DirectionalLight(0xdde7ff, 0.35);
    fill.position.set(-200, -400, 600);
    scene.add(fill);

    controls = createMapControls(camera, renderer.domElement);
    nodesGroup = new THREE.Group();
    scene.add(nodesGroup);

    const groundGeo = new THREE.CircleGeometry(3200, 64);
    const groundMat = new THREE.MeshPhongMaterial({
      color: 0x12151c,
      emissive: 0x07080c,
      shininess: 8,
      transparent: true,
      opacity: 0.92,
    });
    ground = new THREE.Mesh(groundGeo, groundMat);
    ground.rotation.x = -Math.PI / 2;
    ground.position.y = -900;
    scene.add(ground);

    renderer.domElement.addEventListener('pointerup', onPointerUp);
    renderer.domElement.addEventListener('pointermove', onHoverMove);
    window.addEventListener('resize', onResize);
    if (typeof ResizeObserver !== 'undefined') {
      new ResizeObserver(() => onResize()).observe(host);
    }

    animate();
    booted = true;
    if (pendingSnapshotJson) {
      const json = pendingSnapshotJson;
      pendingSnapshotJson = null;
      window.widgetscapeBridge.loadSnapshot(json);
    }
  }

  function onResize() {
    const host = hostElement();
    if (!host || !renderer || !camera) return;
    const width = host.clientWidth || 800;
    const height = host.clientHeight || 600;
    if (width < 2 || height < 2) return;
    camera.aspect = width / height;
    camera.updateProjectionMatrix();
    renderer.setSize(width, height);
    requestRender();
  }

  function animate() {
    renderLoopId = requestAnimationFrame(animate);
    const dt = Math.min(clock.getDelta(), 0.05);
    if (controls) controls.update(dt);
    if (!needsRender || !renderer || !scene || !camera) return;
    updateScreenshotOpacity();
    renderer.render(scene, camera);
    needsRender = false;
  }

  function updateScreenshotOpacity() {
    if (!screenshotMesh || !camera) return;
    screenshotMesh.visible = showScreenshot;
    if (bezelMesh) bezelMesh.visible = showScreenshot;
    if (!showScreenshot) return;
    const camDir = new THREE.Vector3();
    camera.getWorldDirection(camDir);
    const alignment = new THREE.Vector3(0, 0, 1).dot(camDir.clone().negate());
    screenshotMesh.material.opacity = THREE.MathUtils.clamp(0.78 + alignment * 0.2, 0.78, 1);
    if (bezelMesh) bezelMesh.material.opacity = 0.55;
  }

  function disposeObject(object) {
    object.geometry?.dispose();
    if (Array.isArray(object.material)) {
      for (const material of object.material) material.dispose?.();
    } else {
      object.material?.dispose?.();
    }
    if (object.children) {
      for (const child of object.children) disposeObject(child);
    }
  }

  function detachSharedScreenshot() {
    for (const mesh of nodeMeshes.values()) {
      if (mesh.material?.map === screenshotTexture) mesh.material.map = null;
    }
    if (screenshotMesh?.material?.map === screenshotTexture) {
      screenshotMesh.material.map = null;
    }
  }

  function clearSceneGraph() {
    detachSharedScreenshot();
    nodeMeshes.clear();
    hoveredId = null;
    hideTooltip();
    if (screenshotTexture) {
      screenshotTexture.dispose();
      screenshotTexture = null;
    }
    if (!nodesGroup) return;
    while (nodesGroup.children.length) {
      disposeObject(nodesGroup.children.pop());
    }
    screenshotMesh = null;
    bezelMesh = null;
    stems = null;
  }

  function flutterToSceneX(x, width) {
    return x - width / 2;
  }

  function flutterToSceneY(y, height) {
    return height / 2 - y;
  }

  function layerZ(depth) {
    if (layerMode === 'single') return SCREEN_GAP;
    return SCREEN_GAP + (depth || 0) * layerGap;
  }

  function setSliceUVs(geometry, rect, width, height) {
    const u0 = THREE.MathUtils.clamp(rect.left / width, 0, 1);
    const u1 = THREE.MathUtils.clamp((rect.left + rect.width) / width, 0, 1);
    const v0 = THREE.MathUtils.clamp(1 - (rect.top + rect.height) / height, 0, 1);
    const v1 = THREE.MathUtils.clamp(1 - rect.top / height, 0, 1);
    const uv = geometry.attributes.uv;
    uv.setXY(0, u0, v1);
    uv.setXY(1, u1, v1);
    uv.setXY(2, u0, v0);
    uv.setXY(3, u1, v0);
    uv.needsUpdate = true;
  }

  function frameCamera(width, height, maxDepth) {
    if (!camera || !controls) return;
    const stack = layerMode === 'multi' ? maxDepth * layerGap : 40;
    const dist = Math.max(width, height) * 1.35 + stack * 0.42;
    const zMid = layerMode === 'single' ? 8 : stack * 0.42;
    if (ground) ground.position.y = -Math.max(height * 0.62, 220);
    controls.resetToStudio(dist, zMid);
  }

  function nodeCenter(node, width, height) {
    const rect = node.rect;
    return new THREE.Vector3(
      flutterToSceneX(rect.left + rect.width / 2, width),
      flutterToSceneY(rect.top + rect.height / 2, height),
      layerZ(node.depth),
    );
  }

  function coverageOf(node, width, height) {
    if (!node.rect) return 0;
    return (node.rect.width * node.rect.height) / Math.max(1, width * height);
  }

  function uniqueVisualNodes(nodes, width, height) {
    const ranked = nodes.filter((node) => {
      const rect = node.rect;
      return rect && rect.width >= MIN_BOX && rect.height >= MIN_BOX;
    });
    ranked.sort((a, b) => {
      if (!!b.createdByLocalProject !== !!a.createdByLocalProject) {
        return a.createdByLocalProject ? -1 : 1;
      }
      return a.rect.width * a.rect.height - b.rect.width * b.rect.height;
    });

    const kept = [];
    for (const node of ranked) {
      const cover = coverageOf(node, width, height);
      if (!node.createdByLocalProject && cover > 0.82) continue;
      const twin = kept.find((other) => {
        const a = node.rect;
        const b = other.rect;
        return (
          Math.abs(a.left - b.left) < 3 &&
          Math.abs(a.top - b.top) < 3 &&
          Math.abs(a.width - b.width) < 3 &&
          Math.abs(a.height - b.height) < 3 &&
          Math.abs((a.depth || node.depth) - (other.depth || 0)) <= 1
        );
      });
      if (twin && !node.createdByLocalProject) continue;
      kept.push(node);
      if (kept.length >= MAX_MESHES) break;
    }
    return kept;
  }

  function addCard(node, width, height, rect) {
    const center = nodeCenter(node, width, height);
    const geometry = new THREE.PlaneGeometry(Math.max(rect.width, 1), Math.max(rect.height, 1));
    setSliceUVs(geometry, rect, width, height);
    const local = !!node.createdByLocalProject;
    const cover = coverageOf(node, width, height);
    const baseOpacity = local
      ? THREE.MathUtils.lerp(0.98, 0.82, cover)
      : THREE.MathUtils.lerp(0.88, 0.55, cover);
    const material = new THREE.MeshPhongMaterial({
      color: 0xffffff,
      emissive: 0x141820,
      specular: 0xf7fbff,
      shininess: 22,
      transparent: true,
      opacity: baseOpacity,
      depthWrite: false,
      side: THREE.DoubleSide,
      polygonOffset: true,
      polygonOffsetFactor: -(node.depth || 0),
    });
    if (screenshotTexture) {
      material.map = screenshotTexture;
    }
    const mesh = new THREE.Mesh(geometry, material);
    mesh.position.copy(center);
    const edges = new THREE.LineSegments(
      new THREE.EdgesGeometry(geometry, 20),
      new THREE.LineBasicMaterial({
        color: local ? 0xe8f6ff : 0x9aa3b2,
        transparent: true,
        opacity: local ? 0.7 : 0.28,
      }),
    );
    mesh.add(edges);
    mesh.userData = {
      nodeId: node.id,
      local,
      depth: node.depth || 0,
      baseOpacity,
      edges,
      restZ: center.z,
      rect,
    };
    mesh.renderOrder = 2 + (node.depth || 0);
    nodesGroup.add(mesh);
    nodeMeshes.set(node.id, mesh);
  }

  function rebuildStems(data) {
    if (stems) {
      nodesGroup.remove(stems);
      disposeObject(stems);
      stems = null;
    }
    if (layerMode === 'single') return;
    const width = data.logicalWidth || 390;
    const height = data.logicalHeight || 844;
    const byId = new Map(data.nodes.map((n) => [n.id, n]));
    const positions = [];
    for (const node of data.nodes) {
      if (!nodeMeshes.has(node.id) || !node.parentId || !node.createdByLocalProject) continue;
      const parent = byId.get(node.parentId);
      if (!parent?.rect || !nodeMeshes.has(parent.id)) continue;
      const a = nodeCenter(parent, width, height);
      const b = nodeCenter(node, width, height);
      const mid = a.clone().lerp(b, 0.5);
      mid.z = (a.z + b.z) / 2;
      positions.push(a.x, a.y, a.z, mid.x, mid.y, mid.z, mid.x, mid.y, mid.z, b.x, b.y, b.z);
    }
    if (!positions.length) return;
    const geometry = new THREE.BufferGeometry();
    geometry.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
    stems = new THREE.LineSegments(
      geometry,
      new THREE.LineBasicMaterial({
        color: 0x5d6b7c,
        transparent: true,
        opacity: 0.22,
      }),
    );
    stems.renderOrder = 1;
    nodesGroup.add(stems);
  }

  function layoutNodes(data, reframe) {
    if (!nodesGroup) return;
    const width = data.logicalWidth || 390;
    const height = data.logicalHeight || 844;
    for (const [id, mesh] of nodeMeshes.entries()) {
      const node = data.nodes.find((n) => n.id === id);
      if (!node?.rect) continue;
      const center = nodeCenter(node, width, height);
      mesh.userData.restZ = center.z;
      mesh.position.set(center.x, center.y, center.z);
    }
    rebuildStems(data);
    if (screenshotMesh) screenshotMesh.position.z = 0;
    if (bezelMesh) bezelMesh.position.z = -1.2;
    const maxDepth = data.nodes.reduce((m, n) => Math.max(m, n.depth || 0), 0);
    if (reframe) frameCamera(width, height, maxDepth);
    requestRender();
  }

  function removeScreenshotMeshes() {
    if (screenshotMesh && nodesGroup) {
      if (screenshotMesh.material?.map === screenshotTexture) {
        screenshotMesh.material.map = null;
      }
      nodesGroup.remove(screenshotMesh);
      disposeObject(screenshotMesh);
    }
    if (bezelMesh && nodesGroup) {
      nodesGroup.remove(bezelMesh);
      disposeObject(bezelMesh);
    }
    screenshotMesh = null;
    bezelMesh = null;
  }

  function paintCardsWithScreenshot(texture) {
    for (const mesh of nodeMeshes.values()) {
      mesh.material.map = texture;
      mesh.material.color.setHex(0xffffff);
      mesh.material.needsUpdate = true;
    }
  }

  function applyScreenshotTexture(pngBase64, width, height, generation) {
    if (!pngBase64 || !nodesGroup) return;
    new THREE.TextureLoader().load(`data:image/png;base64,${pngBase64}`, (texture) => {
      if (generation !== snapshotGeneration) {
        texture.dispose();
        return;
      }
      detachSharedScreenshot();
      if (screenshotTexture) screenshotTexture.dispose();
      screenshotTexture = texture;
      texture.colorSpace = THREE.SRGBColorSpace;
      texture.anisotropy = 4;
      texture.generateMipmaps = true;
      texture.minFilter = THREE.LinearMipmapLinearFilter;
      texture.wrapS = THREE.ClampToEdgeWrapping;
      texture.wrapT = THREE.ClampToEdgeWrapping;

      removeScreenshotMeshes();
      const bezel = new THREE.Mesh(
        new THREE.PlaneGeometry(width + 2, height + 2),
        new THREE.MeshPhongMaterial({
          color: 0x10141c,
          emissive: 0x050607,
          transparent: true,
          opacity: 0.55,
          depthWrite: false,
        }),
      );
      bezel.position.set(0, 0, -1.2);
      bezel.renderOrder = 0;
      nodesGroup.add(bezel);
      bezelMesh = bezel;

      const material = new THREE.MeshBasicMaterial({
        map: texture,
        transparent: true,
        opacity: 1,
        depthWrite: false,
      });
      screenshotMesh = new THREE.Mesh(new THREE.PlaneGeometry(width, height), material);
      screenshotMesh.position.set(0, 0, 0);
      screenshotMesh.renderOrder = 0.5;
      screenshotMesh.visible = showScreenshot;
      bezel.visible = showScreenshot;
      nodesGroup.add(screenshotMesh);
      paintCardsWithScreenshot(texture);
      requestRender();
    });
  }

  function buildSceneFromSnapshot(data) {
    snapshotGeneration += 1;
    const generation = snapshotGeneration;
    snapshotData = data;
    clearSceneGraph();
    if (!scene || !nodesGroup) return;

    const width = data.logicalWidth || 390;
    const height = data.logicalHeight || 844;
    const visible = uniqueVisualNodes(data.nodes, width, height);
    const maxDepth = data.nodes.reduce((m, n) => Math.max(m, n.depth || 0), 0);

    for (const node of visible) {
      addCard(node, width, height, node.rect);
    }
    if (visible.length === 0) {
      addCard(
        { id: '__root__', depth: 0, createdByLocalProject: true, rect: { left: 0, top: 0, width, height } },
        width,
        height,
        { left: 0, top: 0, width, height },
      );
    }

    rebuildStems({ ...data, nodes: visible });
    applyScreenshotTexture(data.pngBase64, width, height, generation);
    if (selectedId) setSelection(selectedId);
    frameCamera(width, height, maxDepth);
    requestRender();
  }

  function hideTooltip() {
    if (tooltip) tooltip.style.display = 'none';
  }

  function showTooltip(node, clientX, clientY) {
    if (!tooltip || !node) return;
    const host = hostElement();
    if (!host) return;
    const rect = host.getBoundingClientRect();
    const size = node.rect
      ? `${Math.round(node.rect.width)} × ${Math.round(node.rect.height)}`
      : '';
    tooltip.innerHTML = `<div style="font-weight:600">${node.label || node.id}</div>` +
      (size ? `<div style="opacity:.7;margin-top:2px">${size}</div>` : '');
    tooltip.style.display = 'block';
    tooltip.style.left = `${Math.min(clientX - rect.left + 14, rect.width - 180)}px`;
    tooltip.style.top = `${Math.max(10, clientY - rect.top - 42)}px`;
  }

  function styleMesh(mesh, id) {
    const selected = id === selectedId;
    const hovered = id === hoveredId;
    mesh.material.opacity = selected
      ? 1
      : hovered
        ? Math.min(1, mesh.userData.baseOpacity + 0.08)
        : mesh.userData.baseOpacity;
    mesh.material.color.setHex(selected ? 0xfff1c2 : 0xffffff);
    mesh.material.emissive.setHex(selected ? 0x3d2a08 : hovered ? 0x1a2430 : 0x141820);
    if (mesh.userData.edges) {
      mesh.userData.edges.material.color.setHex(selected ? 0xffe082 : hovered ? 0xffffff : mesh.userData.local ? 0xe8f6ff : 0x9aa3b2);
      mesh.userData.edges.material.opacity = selected ? 0.95 : hovered ? 0.85 : mesh.userData.local ? 0.7 : 0.28;
    }
    mesh.position.z = mesh.userData.restZ + (selected ? 2 : hovered ? 1 : 0);
  }

  function refreshMeshStyles() {
    for (const [id, mesh] of nodeMeshes.entries()) {
      if (id === '__root__') continue;
      styleMesh(mesh, id);
    }
    requestRender();
  }

  function pickAt(clientX, clientY) {
    if (!renderer || !camera || !snapshotData) return null;
    const rect = renderer.domElement.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return null;
    pointer.x = ((clientX - rect.left) / rect.width) * 2 - 1;
    pointer.y = -(((clientY - rect.top) / rect.height) * 2 - 1);
    raycaster.setFromCamera(pointer, camera);
    const hits = raycaster.intersectObjects([...nodeMeshes.values()], false);
    if (hits.length > 0) {
      const id = hits[0].object.userData.nodeId;
      return snapshotData.nodes.find((n) => n.id === id) || null;
    }
    return null;
  }

  function onHoverMove(event) {
    if (!snapshotData) return;
    const hit = pickAt(event.clientX, event.clientY);
    const nextId = hit && hit.id !== '__root__' ? hit.id : null;
    if (nextId !== hoveredId) {
      hoveredId = nextId;
      refreshMeshStyles();
    }
    if (hit && hit.id !== '__root__') showTooltip(hit, event.clientX, event.clientY);
    else hideTooltip();
  }

  function onPointerUp(event) {
    if (suppressClickPick) {
      suppressClickPick = false;
      return;
    }
    if (event.button !== 0) return;
    const hit = pickAt(event.clientX, event.clientY);
    if (!hit || !pickHandler || hit.id === '__root__') return;
    const r = hit.rect || { left: 0, top: 0, width: 0, height: 0 };
    pickHandler(hit.id, r.left + r.width / 2, r.top + r.height / 2);
  }

  function setSelection(nodeId) {
    selectedId = nodeId || null;
    refreshMeshStyles();
  }

  function resetCamera() {
    if (!snapshotData || !camera || !controls) return;
    const width = snapshotData.logicalWidth || 390;
    const height = snapshotData.logicalHeight || 844;
    const maxDepth = snapshotData.nodes.reduce((m, n) => Math.max(m, n.depth || 0), 0);
    frameCamera(width, height, maxDepth);
  }

  window.widgetscapeBridge = {
    loadSnapshot(json) {
      if (!booted) {
        pendingSnapshotJson = json;
        initScene();
        if (!booted && pendingSnapshotJson) return;
      } else {
        initScene();
      }
      try {
        buildSceneFromSnapshot(JSON.parse(json));
      } catch (e) {
        showError('Snapshot parse error: ' + e);
      }
    },
    setSelection(nodeId) {
      setSelection(nodeId || null);
    },
    setTheme(theme) {
      if (!scene) return;
      const dark = theme !== 'light';
      scene.background = dark ? createStudioBackground() : new THREE.Color(0xe8e4dc);
      if (scene.fog) scene.fog.color.set(dark ? 0x0b0d12 : 0xe8e4dc);
      if (hint) hint.style.color = dark ? 'rgba(230,234,240,0.48)' : 'rgba(32,33,36,0.55)';
      requestRender();
    },
    setLayerMode(mode) {
      layerMode = mode === 'single' ? 'single' : 'multi';
      if (snapshotData) layoutNodes(snapshotData, false);
      else requestRender();
    },
    setLayerGap(gap) {
      const next = Number(gap);
      if (!Number.isFinite(next)) return;
      layerGap = Math.max(MIN_LAYER_GAP, next);
      if (snapshotData) layoutNodes(snapshotData, false);
    },
    setShowScreenshot(visible) {
      showScreenshot = visible !== false;
      if (screenshotMesh) screenshotMesh.visible = showScreenshot;
      if (bezelMesh) bezelMesh.visible = showScreenshot;
      requestRender();
    },
    updateScreenshot(pngBase64) {
      if (!snapshotData || !pngBase64) return;
      snapshotData.pngBase64 = pngBase64;
      snapshotGeneration += 1;
      applyScreenshotTexture(
        pngBase64,
        snapshotData.logicalWidth || 390,
        snapshotData.logicalHeight || 844,
        snapshotGeneration,
      );
    },
    resetCamera() {
      resetCamera();
    },
    setPickHandler(handler) {
      pickHandler = handler;
    },
    isReady() {
      return booted;
    },
  };

  void renderLoopId;
})();
