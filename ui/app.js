// app.js — webview client. POST /call/<handler> with JSON body.

(function () {
  const PORT = window.SDR_PORT;
  const BASE = 'http://127.0.0.1:' + PORT;

  async function callLua(handler, payload) {
    const resp = await fetch(BASE + '/call/' + handler, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload || {}),
    });
    const data = await resp.json();
    if (data.ok) return data.result;
    throw new Error(typeof data.result === 'string' ? data.result : JSON.stringify(data.result));
  }

  async function pollPushLoop() {
    while (true) {
      try {
        const resp = await fetch(BASE + '/push');
        const data = await resp.json();
        (data.events || []).forEach((ev) => {
          const fn = pushHandlers[ev.name];
          if (fn) fn(ev.data || {});
        });
      } catch (_) {
        await new Promise(r => setTimeout(r, 1000));
        continue;
      }
      await new Promise(r => setTimeout(r, 250));
    }
  }

  const pushHandlers = {
    status: (d) => {
      const dot = document.getElementById('status-dot');
      dot.className = 'dot ' + (d.status || 'idle');
      document.getElementById('status-text').textContent = d.status || 'idle';
    },
    event_count: (d) => {
      document.getElementById('rec-events').textContent = d.count + ' events';
    },
    sequence_updated: (seq) => {
      currentSeq = seq;
      renderTimeline();
      updateActiveLabels();
    },
    replay_progress: (d) => {
      document.getElementById('rec-events').textContent =
        'replay ' + d.i + '/' + d.n + ' (' + d.type + ')';
    },
    replay_done: () => {
      document.getElementById('rec-events').textContent = 'replay done';
    },
    capture_done: (d) => {
      document.getElementById('last-output').textContent = d.path || '(no path)';
    },
  };

  // ─── State ─────────────────────────────────────────────────────
  let currentSeq = null;

  function updateActiveLabels() {
    const pa = document.getElementById('preset-active');
    if (pa) pa.textContent = currentSeq && currentSeq.preset_name ? currentSeq.preset_name : '— none —';
    const ta = document.getElementById('timeline-active');
    if (ta) ta.textContent = currentSeq && currentSeq.name ? currentSeq.name : '— none —';
    const link = document.getElementById('timeline-preset-link');
    if (link) {
      if (currentSeq && currentSeq.preset_name) {
        link.textContent = `Linked preset: ${currentSeq.preset_name}`;
      } else {
        link.textContent = 'No preset linked.';
      }
    }
  }

  // ─── Sequence + Preset lists ────────────────────────────────────
  async function refreshSequenceList() {
    const list = await callLua('list_sequences', {});
    const sel = document.getElementById('seq-select');
    sel.innerHTML = '<option value="">— choose —</option>';
    (list || []).forEach((name) => {
      const opt = document.createElement('option');
      opt.value = name; opt.textContent = name; sel.appendChild(opt);
    });
    if (currentSeq && currentSeq.name) sel.value = currentSeq.name;
  }

  async function refreshPresetList() {
    const list = await callLua('list_presets', {});
    const buildOptions = (sel) => {
      if (!sel) return;
      sel.innerHTML = '<option value="">— choose preset —</option>';
      (list || []).forEach((n) => {
        const o = document.createElement('option'); o.value = n; o.textContent = n;
        sel.appendChild(o);
      });
      if (currentSeq && currentSeq.preset_name) sel.value = currentSeq.preset_name;
    };
    buildOptions(document.getElementById('preset-select'));
    buildOptions(document.getElementById('preset-select-edit'));
  }

  async function loadSequence(name) {
    if (!name) return;
    const seq = await callLua('load_sequence', { name });
    currentSeq = seq;
    applySeqToUI();
    renderTimeline();
    updateActiveLabels();
    if (seq.preset_name) {
      document.getElementById('preset-select').value = seq.preset_name;
      document.getElementById('preset-select-edit').value = seq.preset_name;
    }
  }

  async function loadPresetIntoCurrentSeq(name) {
    if (!name || !currentSeq) return;
    const r = await callLua('apply_preset', { name });
    if (r.error) return alert(r.error);
    if (r.mismatch) {
      if (!confirm('Warning: ' + r.mismatch + '\n\nApply anyway?')) return;
    }
    currentSeq = r.sequence;
    applySeqToUI();
    renderTimeline();
    updateActiveLabels();
    document.getElementById('preset-name').value = name;
    document.getElementById('last-output').textContent = 'preset loaded: ' + name;
  }

  function applySeqToUI() {
    if (!currentSeq) return;
    const vp = currentSeq.viewport || {};
    document.querySelectorAll('input[name=vp-mode]').forEach((r) => {
      r.checked = (r.value === (vp.mode || 'viewport'));
    });
    if (vp.preset) document.getElementById('vp-preset').value = vp.preset;
    document.getElementById('vp-w').value = vp.width || 1920;
    document.getElementById('vp-h').value = vp.height || 1080;
    const r = vp.region || {};
    document.getElementById('vp-region').textContent =
      r.w ? `region: ${r.x},${r.y} ${r.w}×${r.h}` : 'region: not set';

    const pb = currentSeq.playback || {};
    document.getElementById('auto-path').checked = pb.auto_path === true;
    document.getElementById('auto-path-pps').value = pb.auto_path_pps || 1000;
    document.getElementById('auto-path-easing').value = pb.auto_path_easing || 'in_out';
    document.getElementById('click-effects').checked = pb.show_click_effects === true;
    document.getElementById('show-keystrokes').checked = pb.show_keystrokes === true;
    document.getElementById('pre-delay-ms').value  = (pb.pre_delay_ms  != null) ? pb.pre_delay_ms  : 1000;
    document.getElementById('post-delay-ms').value = (pb.post_delay_ms != null) ? pb.post_delay_ms : 1000;

    const sh = (currentSeq.viewport && currentSeq.viewport.overlay_shift) || { dx: 0, dy: 0 };
    document.getElementById('overlay-shift-x').value = sh.dx || 0;
    document.getElementById('overlay-shift-y').value = sh.dy || 0;

    const out = currentSeq.output || {};
    document.getElementById('auto-crop-universal').checked = out.auto_crop_universal === true;
    document.getElementById('auto-rescale').checked = out.rescale === true;
    document.getElementById('rescale-w').value = out.rescale_w || 1920;
    document.getElementById('rescale-h').value = out.rescale_h || 1080;
    document.getElementById('rescale-yt-w').value = out.rescale_youtube_w || 1920;
    document.getElementById('rescale-yt-h').value = out.rescale_youtube_h || 1080;
    document.getElementById('rescale-rl-w').value = out.rescale_reels_w || 1080;
    document.getElementById('rescale-rl-h').value = out.rescale_reels_h || 1920;
  }

  function readVpFromUI() {
    const mode = document.querySelector('input[name=vp-mode]:checked').value;
    const preset = document.getElementById('vp-preset').value;
    const width  = parseInt(document.getElementById('vp-w').value, 10);
    const height = parseInt(document.getElementById('vp-h').value, 10);
    if (!currentSeq) return null;
    currentSeq.viewport = currentSeq.viewport || {};
    currentSeq.viewport.mode = mode;
    currentSeq.viewport.preset = preset;
    currentSeq.viewport.width = width;
    currentSeq.viewport.height = height;
  }

  function readPlaybackFromUI() {
    if (!currentSeq) return;
    currentSeq.playback = currentSeq.playback || {};
    currentSeq.playback.auto_path          = document.getElementById('auto-path').checked;
    currentSeq.playback.auto_path_pps      = parseInt(document.getElementById('auto-path-pps').value, 10) || 1000;
    currentSeq.playback.auto_path_easing   = document.getElementById('auto-path-easing').value || 'in_out';
    currentSeq.playback.show_click_effects = document.getElementById('click-effects').checked;
    currentSeq.playback.show_keystrokes    = document.getElementById('show-keystrokes').checked;
    currentSeq.playback.pre_delay_ms       = parseInt(document.getElementById('pre-delay-ms').value, 10);
    currentSeq.playback.post_delay_ms      = parseInt(document.getElementById('post-delay-ms').value, 10);
  }

  function readShiftFromUI() {
    if (!currentSeq) return;
    currentSeq.viewport = currentSeq.viewport || {};
    currentSeq.viewport.overlay_shift = {
      dx: parseInt(document.getElementById('overlay-shift-x').value, 10) || 0,
      dy: parseInt(document.getElementById('overlay-shift-y').value, 10) || 0,
    };
  }

  function readOutputFromUI() {
    if (!currentSeq) return;
    currentSeq.output = currentSeq.output || {};
    currentSeq.output.auto_crop_universal = document.getElementById('auto-crop-universal').checked;
    currentSeq.output.rescale   = document.getElementById('auto-rescale').checked;
    currentSeq.output.rescale_w = parseInt(document.getElementById('rescale-w').value, 10) || 1920;
    currentSeq.output.rescale_h = parseInt(document.getElementById('rescale-h').value, 10) || 1080;
    currentSeq.output.rescale_youtube_w = parseInt(document.getElementById('rescale-yt-w').value, 10) || 1920;
    currentSeq.output.rescale_youtube_h = parseInt(document.getElementById('rescale-yt-h').value, 10) || 1080;
    currentSeq.output.rescale_reels_w   = parseInt(document.getElementById('rescale-rl-w').value, 10) || 1080;
    currentSeq.output.rescale_reels_h   = parseInt(document.getElementById('rescale-rl-h').value, 10) || 1920;
  }

  function readAllFromUI() {
    readVpFromUI();
    readPlaybackFromUI();
    readShiftFromUI();
    readOutputFromUI();
  }

  // ─── Auto-save preset settings (viewport + playback + output) ──
  // Triggered when user changes any preset-tab control. Persists to disk
  // under the active preset name. If no preset name is set, prompts once.
  let _autoSaveDebounce = null;
  function autoSavePreset() {
    readAllFromUI();
    if (!currentSeq) return;
    if (!currentSeq.preset_name) return; // no active preset → silent skip
    clearTimeout(_autoSaveDebounce);
    _autoSaveDebounce = setTimeout(async () => {
      try {
        await callLua('save_preset', { name: currentSeq.preset_name, sequence: currentSeq });
        // Also update the timeline so its linked preset_name stays in sync.
        await callLua('save_preset_to_sequence', { sequence: currentSeq });
      } catch (e) { console.warn('autoSavePreset:', e.message); }
    }, 400);
  }

  // ─── Timeline ──────────────────────────────────────────────────
  function totalDurationMs(seq) {
    const pb = seq.playback || {};
    const ap = pb.auto_path === true;
    const pps = pb.auto_path_pps || 1000;
    let total = 0; let prev = null; let inDrag = false;
    for (const e of seq.events || []) {
      if (ap && e.type === 'mouse_move' && !inDrag) {
        // skip
      } else {
        total += (e.pause_before_ms || 0);
        if (ap && (e.type === 'mouse_down' || e.type === 'mouse_up')) {
          const x = (e.x_window != null ? e.x_window : e.x);
          const y = (e.y_window != null ? e.y_window : e.y);
          if (prev && x != null && y != null) {
            const dx = x - prev.x, dy = y - prev.y;
            total += Math.sqrt(dx*dx + dy*dy) / Math.max(50, pps) * 1000;
          }
          if (x != null && y != null) prev = { x, y };
        }
      }
      if (e.type === 'mouse_down') inDrag = true;
      else if (e.type === 'mouse_up') inDrag = false;
    }
    return total;
  }

  function renderTimeline() {
    const wrap = document.getElementById('timeline');
    wrap.innerHTML = '';
    if (!currentSeq) return;
    const allEvents = currentSeq.events || [];
    const autoPath = (currentSeq.playback || {}).auto_path === true;

    let displayEvents = allEvents;
    if (autoPath) {
      displayEvents = [];
      let pendingMoves = null;
      for (const evt of allEvents) {
        if (evt.type === 'mouse_move') {
          if (!pendingMoves) pendingMoves = { count: 0, pause: 0 };
          pendingMoves.count += 1;
          pendingMoves.pause += (evt.pause_before_ms || 0);
        } else {
          if (pendingMoves) {
            displayEvents.push({ _synthetic: true, type: 'auto_path',
              count: pendingMoves.count, pause_before_ms: pendingMoves.pause });
            pendingMoves = null;
          }
          displayEvents.push(evt);
        }
      }
      if (pendingMoves) {
        displayEvents.push({ _synthetic: true, type: 'auto_path',
          count: pendingMoves.count, pause_before_ms: pendingMoves.pause });
      }
    }

    document.getElementById('timeline-meta').textContent =
      `${allEvents.length} events (${displayEvents.length} shown) · ${(totalDurationMs(currentSeq)/1000).toFixed(2)}s`;

    displayEvents.forEach((evt) => {
      const pauseChip = document.createElement('span');
      pauseChip.className = 'chip pause';
      const pauseInput = document.createElement('input');
      pauseInput.type = 'number'; pauseInput.value = evt.pause_before_ms || 0; pauseInput.min = 0;
      pauseInput.addEventListener('change', () => {
        evt.pause_before_ms = parseInt(pauseInput.value, 10) || 0;
        renderTimeline();
      });
      pauseChip.appendChild(pauseInput);
      pauseChip.appendChild(document.createTextNode(' ms'));
      wrap.appendChild(pauseChip);

      const evChip = document.createElement('span');
      evChip.className = 'chip event ' + (evt.type || '');
      let label = evt.type;
      if (evt._synthetic && evt.type === 'auto_path') {
        label = `auto-path (${evt.count} moves)`;
      } else if (evt.type && evt.type.startsWith('mouse_')) {
        label += ` ${evt.button || ''} @${evt.x},${evt.y}`;
        evChip.title = JSON.stringify(evt, null, 2);
      } else if (evt.type === 'key_down' || evt.type === 'key_up') {
        label += ` ${(evt.modifiers || []).map(m => m + '+').join('')}${evt.key || ''}`;
        evChip.title = JSON.stringify(evt, null, 2);
      } else {
        evChip.title = JSON.stringify(evt, null, 2);
      }
      evChip.textContent = label;
      if (!evt._synthetic) {
        evChip.addEventListener('click', () => {
          const choice = prompt('Action: (d)elete  (c)omment  (s)kip', 'c');
          if (choice === 'd') {
            const idx = (currentSeq.events || []).indexOf(evt);
            if (idx >= 0) { currentSeq.events.splice(idx, 1); renderTimeline(); }
          } else if (choice === 'c') {
            const c = prompt('Comment:', evt.comment || '');
            if (c !== null) { evt.comment = c; renderTimeline(); }
          }
        });
      }
      wrap.appendChild(evChip);
    });
  }

  // ─── Header (top card) ─────────────────────────────────────────
  document.getElementById('preset-select').addEventListener('change', async (e) => {
    const name = e.target.value;
    if (!name) return;
    document.getElementById('preset-name').value = name;
    if (currentSeq) await loadPresetIntoCurrentSeq(name);
  });

  async function applyViewport() {
    // Build envelope from UI — works without a loaded timeline.
    const envelope = buildPresetFromUI();
    try {
      const result = await callLua('apply_viewport', { sequence: envelope });
      if (result && result.error) {
        document.getElementById('vp-region').textContent = 'ERROR: ' + result.error;
      } else if (result && result.region) {
        const r = result.region;
        document.getElementById('vp-region').textContent = `region: ${r.x},${r.y} ${r.w}×${r.h}`;
        if (currentSeq) {
          currentSeq.viewport = currentSeq.viewport || {};
          currentSeq.viewport.region = r;
          currentSeq.viewport._region_base = { x: r.x, y: r.y, w: r.w, h: r.h };
        }
      }
    } catch (e) {
      document.getElementById('vp-region').textContent = 'ERR apply: ' + e.message;
    }
  }
  document.getElementById('btn-apply-vp').addEventListener('click', applyViewport);
  document.getElementById('btn-apply-vp-2') &&
    document.getElementById('btn-apply-vp-2').addEventListener('click', applyViewport);

  // Single overlay toggle that flips between Show / Hide.
  let overlayVisible = false;
  function updateOverlayBtnLabels() {
    const label = overlayVisible ? 'Hide overlay' : 'Show overlay';
    ['btn-toggle-overlay', 'btn-toggle-overlay-2'].forEach((id) => {
      const el = document.getElementById(id);
      if (el) el.textContent = label;
    });
  }
  async function toggleOverlay() {
    if (overlayVisible) {
      await callLua('hide_overlay', {});
      overlayVisible = false;
    } else {
      const r = await callLua('show_overlay', {});
      overlayVisible = !!(r && r.shown);
      if (r && r.error) alert(r.error);
    }
    updateOverlayBtnLabels();
  }
  document.getElementById('btn-toggle-overlay').addEventListener('click', toggleOverlay);
  document.getElementById('btn-toggle-overlay-2') &&
    document.getElementById('btn-toggle-overlay-2').addEventListener('click', toggleOverlay);

  // ─── Timeline tab ──────────────────────────────────────────────
  document.getElementById('seq-select').addEventListener('change', (e) => loadSequence(e.target.value));

  // New = prompt → create → save immediately
  document.getElementById('btn-new').addEventListener('click', async () => {
    const name = prompt('Timeline name:');
    if (!name) return;
    try {
      currentSeq = await callLua('new_sequence', { name: name.trim() });
      applySeqToUI(); renderTimeline(); updateActiveLabels();
      // Immediately persist so refresh shows it.
      await callLua('save_timeline', { sequence: currentSeq });
      await refreshSequenceList();
      document.getElementById('last-output').textContent = 'created + saved timeline: ' + name;
    } catch (e) { alert('new failed: ' + e.message); }
  });

  document.getElementById('btn-save-timeline').addEventListener('click', async () => {
    if (!currentSeq) return;
    await callLua('save_timeline', { sequence: currentSeq });
    document.getElementById('last-output').textContent = 'saved ' + currentSeq.name;
  });

  document.getElementById('btn-clear-timeline').addEventListener('click', async () => {
    if (!currentSeq) return;
    if (!confirm('Clear all events from "' + currentSeq.name + '"?')) return;
    currentSeq.events = [];
    renderTimeline();
    await callLua('save_timeline', { sequence: currentSeq });
    document.getElementById('last-output').textContent = 'cleared events';
  });

  // Build a "preset envelope" from current UI controls (works WITHOUT a
  // loaded timeline — presets are first-class, decoupled from timelines).
  function buildPresetFromUI() {
    // Start from currentSeq if present so user-typed/edited values survive,
    // else from a clean default seed.
    const seed = currentSeq ? JSON.parse(JSON.stringify(currentSeq)) : {
      version: 1, name: '__draft__', events: [],
      viewport: {}, playback: {}, output: {}, chrome_offsets: {},
    };
    const saved = currentSeq;
    currentSeq = seed;
    readAllFromUI();
    const result = seed;
    currentSeq = saved;
    return result;
  }

  // ─── Preset tab ────────────────────────────────────────────────
  // The "Editing preset" dropdown drives which preset gets saved/duplicated.
  // Loading a preset from this dropdown applies it to the active timeline
  // (if any) AND populates the UI controls so user can edit + save.
  document.getElementById('preset-select-edit').addEventListener('change', async (e) => {
    const name = e.target.value;
    if (!name) return;
    document.getElementById('preset-select').value = name;
    if (currentSeq) {
      await loadPresetIntoCurrentSeq(name);
    } else {
      // No timeline → just load preset values into UI for editing/saving.
      const p = await callLua('apply_preset', { name }).catch(() => null);
      // apply_preset requires currentSeq; fall back to manual load.
      const preset = await callLua('list_presets', {}).then(() => null); // noop
      // Use a synthetic seq to drive UI controls.
      currentSeq = { name: '__draft__', events: [],
        viewport: {}, playback: {}, output: {}, chrome_offsets: {},
        preset_name: name };
      // Re-fetch preset content via apply_preset by temporarily allowing it.
      const r = await callLua('apply_preset', { name }).catch(() => null);
      if (r && r.sequence) currentSeq = r.sequence;
      applySeqToUI(); updateActiveLabels();
    }
  });

  document.getElementById('btn-preset-new').addEventListener('click', async () => {
    const name = prompt('Preset name:');
    if (!name) return;
    const envelope = buildPresetFromUI();
    try {
      await callLua('save_preset', { name: name.trim(), sequence: envelope });
      await refreshPresetList();
      document.getElementById('preset-select').value = name.trim();
      document.getElementById('preset-select-edit').value = name.trim();
      if (currentSeq) {
        currentSeq.preset_name = name.trim();
        await callLua('save_preset_to_sequence', { sequence: currentSeq });
      }
      updateActiveLabels();
      document.getElementById('last-output').textContent = 'created + saved preset: ' + name;
    } catch (e) { alert('preset new failed: ' + e.message); }
  });

  document.getElementById('btn-preset-save').addEventListener('click', async () => {
    const name = document.getElementById('preset-select-edit').value
              || (currentSeq && currentSeq.preset_name);
    if (!name) return alert('Pick a preset to save into (or create a new one)');
    const envelope = buildPresetFromUI();
    await callLua('save_preset', { name, sequence: envelope });
    if (currentSeq) {
      currentSeq.preset_name = name;
      await callLua('save_preset_to_sequence', { sequence: currentSeq });
    }
    await refreshPresetList();
    updateActiveLabels();
    document.getElementById('last-output').textContent = 'preset saved: ' + name;
  });

  document.getElementById('btn-preset-duplicate').addEventListener('click', async () => {
    const src = document.getElementById('preset-select-edit').value
             || (currentSeq && currentSeq.preset_name);
    if (!src) return alert('Pick a preset to duplicate first');
    const dest = prompt('New name for duplicate of "' + src + '":', src + '-copy');
    if (!dest) return;
    try {
      const r = await callLua('duplicate_preset', { src, dest: dest.trim() });
      if (r && r.error) return alert('duplicate failed: ' + r.error);
      await refreshPresetList();
      document.getElementById('preset-select-edit').value = dest.trim();
      document.getElementById('preset-select').value = dest.trim();
      document.getElementById('last-output').textContent = 'duplicated: ' + src + ' → ' + dest;
    } catch (e) { alert('duplicate failed: ' + e.message); }
  });

  // Viewport
  document.getElementById('vp-preset').addEventListener('change', (e) => {
    const opt = e.target.selectedOptions[0];
    if (opt.dataset.w) document.getElementById('vp-w').value = opt.dataset.w;
    if (opt.dataset.h) document.getElementById('vp-h').value = opt.dataset.h;
    autoSavePreset();
  });

  ['overlay-shift-x', 'overlay-shift-y'].forEach((id) => {
    document.getElementById(id).addEventListener('change', async () => {
      readShiftFromUI();
      autoSavePreset();
      if (currentSeq && currentSeq.viewport && currentSeq.viewport.region) {
        const r = currentSeq.viewport.region;
        const sh = currentSeq.viewport.overlay_shift || { dx: 0, dy: 0 };
        if (!currentSeq.viewport._region_base) {
          currentSeq.viewport._region_base = { x: r.x - sh.dx, y: r.y - sh.dy, w: r.w, h: r.h };
        }
        const base = currentSeq.viewport._region_base;
        currentSeq.viewport.region = { x: base.x + sh.dx, y: base.y + sh.dy, w: base.w, h: base.h };
        const rr = currentSeq.viewport.region;
        document.getElementById('vp-region').textContent = `region: ${rr.x},${rr.y} ${rr.w}×${rr.h}`;
      }
      callLua('show_overlay', { shift: currentSeq && currentSeq.viewport.overlay_shift }).catch(() => {});
    });
  });

  // Recording
  document.getElementById('btn-rec').addEventListener('click', async () => {
    if (!currentSeq) return alert('load a timeline first');
    await callLua('start_record', { append: false });
  });

  document.getElementById('btn-rec-continue').addEventListener('click', async () => {
    if (!currentSeq) return alert('load a timeline first');
    await callLua('start_record', { append: true });
    document.getElementById('last-output').textContent = 'continuing recording (append)';
  });

  // Playback / Output — auto-save preset on any change
  document.getElementById('auto-path').addEventListener('change', () => {
    readPlaybackFromUI(); renderTimeline(); autoSavePreset();
  });
  ['click-effects', 'show-keystrokes', 'pre-delay-ms', 'post-delay-ms',
   'auto-path-pps', 'auto-path-easing']
    .forEach((id) => document.getElementById(id).addEventListener('change', () => {
      readPlaybackFromUI(); autoSavePreset();
    }));
  ['auto-crop-universal', 'auto-rescale', 'rescale-w', 'rescale-h',
   'rescale-yt-w', 'rescale-yt-h', 'rescale-rl-w', 'rescale-rl-h']
    .forEach((id) => document.getElementById(id).addEventListener('change', () => {
      readOutputFromUI(); autoSavePreset();
    }));

  document.getElementById('btn-apply-auto').addEventListener('click', async () => {
    if (!currentSeq) return;
    const events = currentSeq.events || [];
    const out = []; let pendingPause = 0;
    for (const e of events) {
      if (e.type === 'mouse_move') pendingPause += (e.pause_before_ms || 0);
      else {
        const clone = Object.assign({}, e);
        clone.pause_before_ms = (clone.pause_before_ms || 0) + pendingPause;
        pendingPause = 0;
        out.push(clone);
      }
    }
    if (pendingPause > 0 && out.length) {
      out[out.length - 1].pause_before_ms = (out[out.length - 1].pause_before_ms || 0) + pendingPause;
    }
    const dropped = events.length - out.length;
    if (!confirm(`Drop ${dropped} mouse_move events?`)) return;
    currentSeq.events = out;
    currentSeq.events.forEach((e, i) => { e.id = 'evt_' + String(i + 1).padStart(4, '0'); });
    readPlaybackFromUI();
    await callLua('save_timeline', { sequence: currentSeq });
    renderTimeline();
  });

  document.getElementById('btn-play').addEventListener('click', async () => {
    if (!currentSeq) return;
    readAllFromUI();
    await callLua('set_active_sequence', { sequence: currentSeq });
    callLua('play', { sequence: currentSeq });
  });

  document.getElementById('btn-capture').addEventListener('click', async () => {
    if (!currentSeq) return;
    readAllFromUI();
    await callLua('set_active_sequence', { sequence: currentSeq });
    const r = await callLua('capture_and_play', {});
    if (r.error) alert(r.error);
    else document.getElementById('last-output').textContent = 'capturing → ' + r.output;
  });

  // ─── Tabs ──────────────────────────────────────────────────────
  document.querySelectorAll('.tab-btn').forEach((btn) => {
    btn.addEventListener('click', async () => {
      document.querySelectorAll('.tab-btn').forEach(b => b.classList.toggle('active', b === btn));
      const tab = btn.dataset.tab;
      document.querySelectorAll('.tab').forEach(t => t.hidden = t.dataset.tab !== tab);
      if (tab === 'manage') await renderManagePane();
    });
  });

  // ─── Manage pane ───────────────────────────────────────────────
  async function renderManagePane() {
    const [presets, sequences] = await Promise.all([
      callLua('list_presets', {}),
      callLua('list_sequences_with_meta', {}),
    ]);
    const mp = document.getElementById('manage-presets');
    mp.innerHTML = '';
    (presets || []).forEach((name) => mp.appendChild(makeManageRow('preset', name)));
    if (!presets || !presets.length) mp.innerHTML = '<div class="muted">no presets yet</div>';

    const ms = document.getElementById('manage-timelines');
    ms.innerHTML = '';
    (sequences || []).forEach((info) => ms.appendChild(makeManageRow('timeline', info.name, info)));
    if (!sequences || !sequences.length) ms.innerHTML = '<div class="muted">no timelines yet</div>';
  }

  function makeManageRow(kind, name, info) {
    const row = document.createElement('div');
    row.className = 'manage-row';
    const nm = document.createElement('span');
    nm.className = 'name'; nm.textContent = name;
    row.appendChild(nm);

    if (kind === 'timeline' && info) {
      const meta = document.createElement('span');
      meta.className = 'muted'; meta.style.fontSize = '11px';
      meta.textContent = `(${info.events} events, preset: ${info.preset_name || '—'})`;
      row.appendChild(meta);
    }

    const renameBtn = document.createElement('button');
    renameBtn.textContent = 'Rename';
    renameBtn.addEventListener('click', async () => {
      const next = prompt('New name:', name);
      if (!next || next === name) return;
      const handler = kind === 'preset' ? 'rename_preset' : 'rename_sequence';
      const r = await callLua(handler, { old: name, new: next });
      if (r.error) return alert(r.error);
      await renderManagePane();
      if (kind === 'timeline') await refreshSequenceList(); else await refreshPresetList();
    });
    row.appendChild(renameBtn);

    const exportBtn = document.createElement('button');
    exportBtn.textContent = 'Export to Desktop';
    exportBtn.addEventListener('click', async () => {
      const handler = kind === 'preset' ? 'export_preset' : 'export_sequence';
      const r = await callLua(handler, { name });
      document.getElementById('last-output').textContent = 'exported → ' + (r.exported || '?');
    });
    row.appendChild(exportBtn);

    const delBtn = document.createElement('button');
    delBtn.className = 'danger'; delBtn.textContent = 'Delete';
    delBtn.addEventListener('click', async () => {
      if (!confirm('Delete ' + kind + ' "' + name + '"?')) return;
      const handler = kind === 'preset' ? 'delete_preset' : 'delete_sequence';
      await callLua(handler, { name });
      await renderManagePane();
      if (kind === 'timeline') await refreshSequenceList(); else await refreshPresetList();
    });
    row.appendChild(delBtn);

    return row;
  }

  document.getElementById('btn-ping') && document.getElementById('btn-ping').addEventListener('click', async () => {
    const r = await callLua('ping_companion', {});
    document.getElementById('last-output').textContent = JSON.stringify(r);
  });

  // ─── Init ──────────────────────────────────────────────────────
  (async () => {
    await refreshSequenceList();
    await refreshPresetList();
    try {
      const active = await callLua('get_active_sequence', {});
      if (active && active.name && active.sequence) {
        currentSeq = active.sequence;
        const sel = document.getElementById('seq-select');
        if ([...sel.options].some(o => o.value === active.name)) sel.value = active.name;
        applySeqToUI(); renderTimeline(); updateActiveLabels();
        if (currentSeq.preset_name) {
          document.getElementById('preset-select').value = currentSeq.preset_name;
          document.getElementById('preset-select-edit').value = currentSeq.preset_name;
        }
      }
    } catch (_) {}
    pollPushLoop();
  })();
})();
