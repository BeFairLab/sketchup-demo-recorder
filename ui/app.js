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
      markTimelineDirty();
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
  let currentSeq = null;        // active timeline (for record / play / capture)
  let activePresetName = null;  // header's chosen preset (drives Apply to SketchUp)
  let editingPreset = null;     // {name, viewport, playback, output, ...} — Preset Settings tab only
  let editingPresetDirty = false;
  let timelineDirty = false;    // tracks unsaved changes to events OR preset link

  function defaultPresetBody() {
    return {
      viewport: {
        mode: 'viewport', preset: 'youtube_1080p',
        width: 1920, height: 1080,
        overlay_shift: { dx: 0, dy: 0 },
      },
      chrome_offsets: { top: 70, bottom: 25, left: 0, right: 0 },
      playback: {
        auto_path: false, auto_path_pps: 1000, auto_path_easing: 'in_out',
        show_click_effects: false, show_keystrokes: false,
        pre_delay_ms: 1000, post_delay_ms: 1000,
      },
      output: {
        auto_crop_universal: false,
        rescale: false, rescale_w: 1920, rescale_h: 1080,
        rescale_youtube_w: 1920, rescale_youtube_h: 1080,
        rescale_reels_w: 1080, rescale_reels_h: 1920,
      },
    };
  }

  function updateDirtyBadge() {
    const el = document.getElementById('preset-dirty');
    if (!el) return;
    el.textContent = editingPresetDirty ? '● Unsaved changes' : '';
    el.style.color = editingPresetDirty ? '#d70015' : '';
  }

  function markEditingDirty() {
    if (!editingPreset) return;
    editingPresetDirty = true;
    updateDirtyBadge();
  }

  function updateTimelineDirtyBadge() {
    const el = document.getElementById('timeline-dirty');
    if (!el) return;
    el.textContent = timelineDirty ? '● Unsaved changes' : '';
    el.style.color = timelineDirty ? '#d70015' : '';
  }
  function markTimelineDirty() {
    if (!currentSeq) return;
    timelineDirty = true;
    updateTimelineDirtyBadge();
  }
  function confirmDiscardTimelineDirty() {
    if (!timelineDirty) return true;
    return confirm('Timeline "' + (currentSeq && currentSeq.name) +
      '" has unsaved changes. Discard?');
  }

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
    const buildOptions = (sel, defaultVal) => {
      if (!sel) return;
      sel.innerHTML = '<option value="">— none —</option>';
      (list || []).forEach((n) => {
        const o = document.createElement('option'); o.value = n; o.textContent = n;
        sel.appendChild(o);
      });
      if (defaultVal) sel.value = defaultVal;
    };
    const linkedName = currentSeq && currentSeq.preset_name;
    buildOptions(document.getElementById('preset-select'), linkedName);
    buildOptions(document.getElementById('preset-select-edit'), null);
    buildOptions(document.getElementById('seq-preset-link'), linkedName);
  }

  async function loadSequence(name) {
    if (!name) return;
    if (!confirmDiscardTimelineDirty()) return;
    const seq = await callLua('load_sequence', { name });
    currentSeq = seq;
    timelineDirty = false;
    updateTimelineDirtyBadge();
    renderTimeline();
    updateActiveLabels();
    if (seq.preset_name) {
      document.getElementById('preset-select').value = seq.preset_name;
      document.getElementById('seq-preset-link').value = seq.preset_name;
      activePresetName = seq.preset_name;
    } else {
      document.getElementById('seq-preset-link').value = '';
    }
    // Preset-tab controls are NOT populated here — they live in the editor.
  }

  // Apply a preset by name to the active timeline. Wraps the Lua apply_preset
  // handler with mismatch confirmation.
  async function linkPresetToTimeline(name) {
    if (!name || !currentSeq) return;
    const r = await callLua('apply_preset', { name });
    if (r.error) return alert(r.error);
    if (r.mismatch) {
      if (!confirm('Warning: ' + r.mismatch + '\n\nApply anyway?')) return;
    }
    currentSeq = r.sequence;
    renderTimeline();
    updateActiveLabels();
    markTimelineDirty();
    document.getElementById('last-output').textContent = 'preset linked: ' + name;
  }

  // ─── Editing-preset ↔ UI controls ──────────────────────────────
  // The Preset Settings tab is a pure editor: UI controls bind to
  // editingPreset, NOT to currentSeq. Changes mark dirty; explicit Save
  // writes back to disk.

  function showUniversalCustomEditor(show) {
    document.getElementById('universal-custom-editor').hidden = !show;
    document.getElementById('universal-custom-editor-fields').hidden = !show;
  }

  function applyEditingPresetToControls() {
    const ep = editingPreset || defaultPresetBody();
    const vp = ep.viewport || {};
    document.querySelectorAll('input[name=vp-mode]').forEach((r) => {
      r.checked = (r.value === (vp.mode || 'viewport'));
    });
    if (vp.preset) document.getElementById('vp-preset').value = vp.preset;
    document.getElementById('vp-w').value = vp.width || 1920;
    document.getElementById('vp-h').value = vp.height || 1080;
    const sh = vp.overlay_shift || { dx: 0, dy: 0 };
    document.getElementById('overlay-shift-x').value = sh.dx || 0;
    document.getElementById('overlay-shift-y').value = sh.dy || 0;
    // Universal custom fields
    const uc = vp.universal_custom || {};
    document.getElementById('uc-yt-w').value = (uc.youtube && uc.youtube.w) || 1920;
    document.getElementById('uc-yt-h').value = (uc.youtube && uc.youtube.h) || 1080;
    document.getElementById('uc-rl-w').value = (uc.reels   && uc.reels.w)   || 1080;
    document.getElementById('uc-rl-h').value = (uc.reels   && uc.reels.h)   || 1920;
    showUniversalCustomEditor(vp.preset === 'universal_custom');

    const pb = ep.playback || {};
    document.getElementById('auto-path').checked = pb.auto_path === true;
    document.getElementById('auto-path-pps').value = pb.auto_path_pps || 1000;
    document.getElementById('auto-path-easing').value = pb.auto_path_easing || 'in_out';
    document.getElementById('click-effects').checked = pb.show_click_effects === true;
    document.getElementById('show-keystrokes').checked = pb.show_keystrokes === true;
    const preMs  = (pb.pre_delay_ms  != null) ? pb.pre_delay_ms  : 1000;
    const postMs = (pb.post_delay_ms != null) ? pb.post_delay_ms : 1000;
    document.getElementById('pre-delay-ms').value  = preMs;
    document.getElementById('post-delay-ms').value = postMs;
    document.getElementById('pre-delay-enabled').checked  = preMs > 0;
    document.getElementById('post-delay-enabled').checked = postMs > 0;

    const out = ep.output || {};
    document.getElementById('auto-crop-universal').checked = out.auto_crop_universal === true;
    document.getElementById('auto-rescale').checked = out.rescale === true;
    document.getElementById('rescale-w').value = out.rescale_w || 1920;
    document.getElementById('rescale-h').value = out.rescale_h || 1080;
    document.getElementById('rescale-yt-w').value = out.rescale_youtube_w || 1920;
    document.getElementById('rescale-yt-h').value = out.rescale_youtube_h || 1080;
    document.getElementById('rescale-rl-w').value = out.rescale_reels_w || 1080;
    document.getElementById('rescale-rl-h').value = out.rescale_reels_h || 1920;
    selectResolutionPreset('rescale-preset', out.rescale_w, out.rescale_h);
    selectResolutionPreset('rescale-yt-preset', out.rescale_youtube_w, out.rescale_youtube_h);
    selectResolutionPreset('rescale-rl-preset', out.rescale_reels_w, out.rescale_reels_h);
  }

  function selectResolutionPreset(selectId, w, h) {
    const sel = document.getElementById(selectId);
    if (!sel) return;
    for (const opt of sel.options) {
      if (parseInt(opt.dataset.w, 10) === w && parseInt(opt.dataset.h, 10) === h) {
        sel.value = opt.value;
        return;
      }
    }
    sel.value = 'custom';
  }

  function readControlsIntoEditingPreset() {
    if (!editingPreset) editingPreset = defaultPresetBody();
    editingPreset.viewport = editingPreset.viewport || {};
    editingPreset.viewport.mode = document.querySelector('input[name=vp-mode]:checked').value;
    editingPreset.viewport.preset = document.getElementById('vp-preset').value;
    editingPreset.viewport.width  = parseInt(document.getElementById('vp-w').value, 10);
    editingPreset.viewport.height = parseInt(document.getElementById('vp-h').value, 10);
    editingPreset.viewport.overlay_shift = {
      dx: parseInt(document.getElementById('overlay-shift-x').value, 10) || 0,
      dy: parseInt(document.getElementById('overlay-shift-y').value, 10) || 0,
    };
    editingPreset.viewport.universal_custom = {
      youtube: {
        w: parseInt(document.getElementById('uc-yt-w').value, 10) || 1920,
        h: parseInt(document.getElementById('uc-yt-h').value, 10) || 1080,
      },
      reels: {
        w: parseInt(document.getElementById('uc-rl-w').value, 10) || 1080,
        h: parseInt(document.getElementById('uc-rl-h').value, 10) || 1920,
      },
    };
    editingPreset.playback = editingPreset.playback || {};
    editingPreset.playback.auto_path          = document.getElementById('auto-path').checked;
    editingPreset.playback.auto_path_pps      = parseInt(document.getElementById('auto-path-pps').value, 10) || 1000;
    editingPreset.playback.auto_path_easing   = document.getElementById('auto-path-easing').value || 'in_out';
    editingPreset.playback.show_click_effects = document.getElementById('click-effects').checked;
    editingPreset.playback.show_keystrokes    = document.getElementById('show-keystrokes').checked;
    editingPreset.playback.pre_delay_ms       = document.getElementById('pre-delay-enabled').checked
      ? (parseInt(document.getElementById('pre-delay-ms').value, 10) || 0) : 0;
    editingPreset.playback.post_delay_ms      = document.getElementById('post-delay-enabled').checked
      ? (parseInt(document.getElementById('post-delay-ms').value, 10) || 0) : 0;
    editingPreset.output = editingPreset.output || {};
    editingPreset.output.auto_crop_universal = document.getElementById('auto-crop-universal').checked;
    editingPreset.output.rescale   = document.getElementById('auto-rescale').checked;
    editingPreset.output.rescale_w = parseInt(document.getElementById('rescale-w').value, 10) || 1920;
    editingPreset.output.rescale_h = parseInt(document.getElementById('rescale-h').value, 10) || 1080;
    editingPreset.output.rescale_youtube_w = parseInt(document.getElementById('rescale-yt-w').value, 10) || 1920;
    editingPreset.output.rescale_youtube_h = parseInt(document.getElementById('rescale-yt-h').value, 10) || 1080;
    editingPreset.output.rescale_reels_w   = parseInt(document.getElementById('rescale-rl-w').value, 10) || 1080;
    editingPreset.output.rescale_reels_h   = parseInt(document.getElementById('rescale-rl-h').value, 10) || 1920;
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
        markTimelineDirty();
        renderTimeline();
      });
      pauseChip.appendChild(pauseInput);
      pauseChip.appendChild(document.createTextNode(' ms'));
      wrap.appendChild(pauseChip);

      const evChip = document.createElement('span');
      evChip.className = 'chip event ' + (evt.type || '');
      if (evt.skipped) evChip.classList.add('skipped');
      let label = evt.type;
      if (evt._synthetic && evt.type === 'auto_path') {
        label = `auto-path (${evt.count} moves)`;
      } else if (evt.type === 'nop') {
        label = `pause`;
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
        evChip.addEventListener('click', (e) => {
          showEventMenu(e.target, evt);
        });
      }
      wrap.appendChild(evChip);
    });
  }

  // Inline action menu shown next to a clicked event chip.
  function showEventMenu(anchorEl, evt) {
    document.querySelectorAll('.event-menu').forEach(m => m.remove());
    const menu = document.createElement('div');
    menu.className = 'event-menu';

    const mkItem = (label, fn) => {
      const b = document.createElement('button');
      b.textContent = label;
      b.addEventListener('click', () => { fn(); menu.remove(); });
      return b;
    };

    const idx = currentSeq.events.indexOf(evt);

    menu.appendChild(mkItem('Delete', () => {
      if (idx < 0) return;
      currentSeq.events.splice(idx, 1);
      markTimelineDirty(); renderTimeline();
    }));

    menu.appendChild(mkItem(evt.skipped ? 'Un-skip' : 'Skip during replay', () => {
      evt.skipped = !evt.skipped;
      markTimelineDirty(); renderTimeline();
    }));

    menu.appendChild(mkItem('Insert pause before…', () => {
      const ms = parseInt(prompt('Pause duration (ms) before this event:', '500'), 10);
      if (!ms || ms <= 0) return;
      const nop = { id: 'evt_nop_' + Date.now(), type: 'nop', pause_before_ms: ms };
      currentSeq.events.splice(idx, 0, nop);
      markTimelineDirty(); renderTimeline();
    }));

    menu.appendChild(mkItem('Insert pause after…', () => {
      const ms = parseInt(prompt('Pause duration (ms) after this event:', '500'), 10);
      if (!ms || ms <= 0) return;
      const nop = { id: 'evt_nop_' + Date.now(), type: 'nop', pause_before_ms: ms };
      currentSeq.events.splice(idx + 1, 0, nop);
      markTimelineDirty(); renderTimeline();
    }));

    menu.appendChild(mkItem('Comment…', () => {
      const c = prompt('Comment:', evt.comment || '');
      if (c !== null) { evt.comment = c; markTimelineDirty(); renderTimeline(); }
    }));

    menu.appendChild(mkItem('Close', () => {}));

    const rect = anchorEl.getBoundingClientRect();
    menu.style.left = (rect.left + window.scrollX) + 'px';
    menu.style.top  = (rect.bottom + window.scrollY + 4) + 'px';
    document.body.appendChild(menu);

    // Dismiss on outside click.
    const dismiss = (ev) => {
      if (!menu.contains(ev.target)) {
        menu.remove();
        document.removeEventListener('mousedown', dismiss, true);
      }
    };
    setTimeout(() => document.addEventListener('mousedown', dismiss, true), 0);
  }

  // ─── Header (top card) ─────────────────────────────────────────
  // Header preset = ACTIVE preset for Apply / capture / replay.
  // Independent of the Preset Settings tab editor.
  document.getElementById('preset-select').addEventListener('change', async (e) => {
    const name = e.target.value;
    activePresetName = name || null;
    document.getElementById('seq-preset-link').value = name || '';
    if (!name || !currentSeq) return;
    await linkPresetToTimeline(name);
  });

  // Build a sequence envelope for apply_viewport. Priority:
  //   1. Header active preset
  //   2. Current timeline (already has linked preset's viewport merged in)
  //   3. Editing preset (Preset Settings tab editor)
  //   4. Defaults
  async function presetEnvelopeForApply() {
    if (activePresetName) {
      const p = await callLua('get_preset', { name: activePresetName });
      if (p && !p.error) return Object.assign({ name: '__active__', events: [] }, p);
    }
    if (currentSeq) return JSON.parse(JSON.stringify(currentSeq));
    if (editingPreset) return Object.assign({ name: '__editing__', events: [] }, editingPreset);
    return Object.assign({ name: '__defaults__', events: [] }, defaultPresetBody());
  }

  async function applyViewport() {
    const envelope = await presetEnvelopeForApply();
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
      renderTimeline(); updateActiveLabels();
      timelineDirty = false; updateTimelineDirtyBadge();
      // Persist immediately so it shows in the sequence list.
      await callLua('save_timeline', { sequence: currentSeq });
      await refreshSequenceList();
      document.getElementById('last-output').textContent = 'created + saved timeline: ' + name;
    } catch (e) { alert('new failed: ' + e.message); }
  });

  document.getElementById('btn-save-timeline').addEventListener('click', async () => {
    if (!currentSeq) return;
    await callLua('save_timeline', { sequence: currentSeq });
    timelineDirty = false;
    updateTimelineDirtyBadge();
    document.getElementById('last-output').textContent = 'saved ' + currentSeq.name;
  });

  document.getElementById('btn-clear-timeline').addEventListener('click', async () => {
    if (!currentSeq) return;
    if (!confirm('Clear all events from "' + currentSeq.name + '"?')) return;
    currentSeq.events = [];
    renderTimeline();
    markTimelineDirty();
  });

  // Linked-preset selector on the timeline tab.
  document.getElementById('seq-preset-link').addEventListener('change', async (e) => {
    if (!currentSeq) return alert('load a timeline first');
    const name = e.target.value || null;
    currentSeq.preset_name = name;
    // Mirror to header active preset.
    document.getElementById('preset-select').value = name || '';
    activePresetName = name;
    // Apply preset's settings to currentSeq so they take effect for capture
    // without waiting for an explicit Save.
    if (name) {
      const r = await callLua('apply_preset', { name }).catch(() => null);
      if (r && r.sequence) currentSeq = r.sequence;
    }
    markTimelineDirty();
    updateActiveLabels();
  });

  // (former buildPresetFromUI removed — preset save now reads controls
  // directly via readControlsIntoEditingPreset into editingPreset)

  // ─── Preset Settings tab (decoupled editor) ────────────────────
  // This tab manages PRESET FILES only. It does NOT affect:
  //   - header's active preset (used for Apply / capture)
  //   - currentSeq.preset_name
  //   - any in-progress recording / playback
  //
  // Editing flow:
  //   1. Pick preset in 'Editing preset' dropdown → loads its values into
  //      the UI controls below. editingPresetDirty = false.
  //   2. Change any control → editingPresetDirty = true; '● Unsaved changes'
  //      badge appears.
  //   3. Click 'Save changes' → writes back to that preset file. Dirty cleared.
  //   4. Click 'New…' → prompt for name, controls reset to defaults, dirty
  //      cleared after immediate save.

  function confirmDiscardDirty() {
    if (!editingPresetDirty) return true;
    return confirm('You have unsaved changes to "' + (editingPreset && editingPreset.name)
      + '". Discard them?');
  }

  document.getElementById('preset-select-edit').addEventListener('change', async (e) => {
    const name = e.target.value;
    if (!name) {
      editingPreset = null;
      editingPresetDirty = false;
      updateDirtyBadge();
      return;
    }
    if (!confirmDiscardDirty()) {
      // revert dropdown to whatever is currently being edited
      e.target.value = (editingPreset && editingPreset.name) || '';
      return;
    }
    try {
      const preset = await callLua('get_preset', { name });
      if (preset && preset.error) return alert(preset.error);
      editingPreset = Object.assign({ name }, preset);
      editingPresetDirty = false;
      applyEditingPresetToControls();
      updateDirtyBadge();
    } catch (e2) { alert('load preset failed: ' + e2.message); }
  });

  document.getElementById('btn-preset-new').addEventListener('click', async () => {
    if (!confirmDiscardDirty()) return;
    const name = prompt('New preset name:');
    if (!name) return;
    const trimmed = name.trim();
    editingPreset = Object.assign({ name: trimmed }, defaultPresetBody());
    applyEditingPresetToControls();
    try {
      await callLua('save_preset', { name: trimmed, sequence: editingPreset });
      editingPresetDirty = false;
      updateDirtyBadge();
      await refreshPresetList();
      // Activate immediately: select in editor, in header, link to timeline.
      document.getElementById('preset-select-edit').value = trimmed;
      document.getElementById('preset-select').value = trimmed;
      activePresetName = trimmed;
      if (currentSeq) {
        currentSeq.preset_name = trimmed;
        document.getElementById('seq-preset-link').value = trimmed;
        markTimelineDirty();
      }
      updateActiveLabels();
      document.getElementById('last-output').textContent = 'created + activated preset: ' + trimmed;
    } catch (e) { alert('preset new failed: ' + e.message); }
  });

  document.getElementById('btn-preset-save').addEventListener('click', async () => {
    if (!editingPreset || !editingPreset.name) {
      return alert('Pick a preset to edit (or create a new one) first');
    }
    readControlsIntoEditingPreset();
    try {
      await callLua('save_preset', { name: editingPreset.name, sequence: editingPreset });
      editingPresetDirty = false;
      updateDirtyBadge();
      document.getElementById('last-output').textContent = 'preset saved: ' + editingPreset.name;
    } catch (e) { alert('save failed: ' + e.message); }
  });

  document.getElementById('btn-preset-duplicate').addEventListener('click', async () => {
    const src = (editingPreset && editingPreset.name)
             || document.getElementById('preset-select-edit').value;
    if (!src) return alert('Pick a preset to duplicate first');
    const dest = prompt('New name for duplicate of "' + src + '":', src + '-copy');
    if (!dest) return;
    try {
      const r = await callLua('duplicate_preset', { src, dest: dest.trim() });
      if (r && r.error) return alert('duplicate failed: ' + r.error);
      await refreshPresetList();
      document.getElementById('preset-select-edit').value = dest.trim();
      // Switch editor to the new copy.
      const p = await callLua('get_preset', { name: dest.trim() });
      editingPreset = Object.assign({ name: dest.trim() }, p);
      editingPresetDirty = false;
      applyEditingPresetToControls();
      updateDirtyBadge();
      document.getElementById('last-output').textContent = 'duplicated: ' + src + ' → ' + dest;
    } catch (e) { alert('duplicate failed: ' + e.message); }
  });

  // Viewport — mark editing preset dirty on change.
  document.getElementById('vp-preset').addEventListener('change', (e) => {
    const opt = e.target.selectedOptions[0];
    if (opt.dataset.w) document.getElementById('vp-w').value = opt.dataset.w;
    if (opt.dataset.h) document.getElementById('vp-h').value = opt.dataset.h;
    showUniversalCustomEditor(e.target.value === 'universal_custom');
    markEditingDirty();
  });
  ['vp-w', 'vp-h', 'overlay-shift-x', 'overlay-shift-y',
   'uc-yt-w', 'uc-yt-h', 'uc-rl-w', 'uc-rl-h'].forEach((id) => {
    document.getElementById(id).addEventListener('change', markEditingDirty);
  });
  document.querySelectorAll('input[name=vp-mode]').forEach((r) => {
    r.addEventListener('change', markEditingDirty);
  });

  // Recording — buttons act as toggles, mirroring the ⌃⌥⌘R / ⌃⌥⌘E hotkeys.
  let isRecording = false;
  const _statusPushOrig = pushHandlers.status;
  pushHandlers.status = (d) => {
    isRecording = (d.status === 'recording');
    _statusPushOrig(d);
    updateRecButtonLabels();
  };
  function updateRecButtonLabels() {
    document.getElementById('btn-rec').textContent =
      isRecording ? '■ Stop recording' : '● Start / stop (fresh)';
    document.getElementById('btn-rec-continue').textContent =
      isRecording ? '■ Stop recording' : '↻ Continue (append)';
  }

  // Recording requires a linked preset (so apply_viewport / capture have
  // sensible settings). If header preset is set but timeline isn't linked,
  // auto-link. Otherwise block with a clear message.
  async function ensurePresetLinkedForRecording() {
    if (!currentSeq) { alert('Load a timeline first'); return false; }
    if (currentSeq.preset_name) return true;
    if (activePresetName) {
      // Auto-link the header preset.
      currentSeq.preset_name = activePresetName;
      document.getElementById('seq-preset-link').value = activePresetName;
      // Pull preset settings into currentSeq so capture has them.
      const r = await callLua('apply_preset', { name: activePresetName }).catch(() => null);
      if (r && r.sequence) currentSeq = r.sequence;
      markTimelineDirty();
      updateActiveLabels();
      return true;
    }
    alert('Pick a preset in the header before recording (so playback + output settings exist).');
    return false;
  }

  document.getElementById('btn-rec').addEventListener('click', async () => {
    if (isRecording) return callLua('stop_record', {});
    if (!(await ensurePresetLinkedForRecording())) return;
    await callLua('start_record', { append: false });
  });

  document.getElementById('btn-rec-continue').addEventListener('click', async () => {
    if (isRecording) return callLua('stop_record', {});
    if (!(await ensurePresetLinkedForRecording())) return;
    await callLua('start_record', { append: true });
    document.getElementById('last-output').textContent = 'continuing recording (append)';
  });

  // Playback / Output — mark dirty (no auto-save).
  ['auto-path', 'click-effects', 'show-keystrokes', 'pre-delay-ms', 'post-delay-ms',
   'auto-path-pps', 'auto-path-easing',
   'auto-crop-universal', 'auto-rescale', 'rescale-w', 'rescale-h',
   'rescale-yt-w', 'rescale-yt-h', 'rescale-rl-w', 'rescale-rl-h']
    .forEach((id) => document.getElementById(id).addEventListener('change', markEditingDirty));

  // Pre/post-delay enabled checkboxes — toggle the input.
  ['pre-delay-enabled', 'post-delay-enabled'].forEach((id) => {
    document.getElementById(id).addEventListener('change', markEditingDirty);
  });

  // Resolution preset selectors → populate W/H inputs.
  function wireResolutionPreset(presetId, wId, hId) {
    document.getElementById(presetId).addEventListener('change', (e) => {
      const opt = e.target.selectedOptions[0];
      if (opt && opt.dataset.w) document.getElementById(wId).value = opt.dataset.w;
      if (opt && opt.dataset.h) document.getElementById(hId).value = opt.dataset.h;
      markEditingDirty();
    });
    document.getElementById(wId).addEventListener('input', () => {
      selectResolutionPreset(presetId,
        parseInt(document.getElementById(wId).value, 10),
        parseInt(document.getElementById(hId).value, 10));
    });
    document.getElementById(hId).addEventListener('input', () => {
      selectResolutionPreset(presetId,
        parseInt(document.getElementById(wId).value, 10),
        parseInt(document.getElementById(hId).value, 10));
    });
  }
  wireResolutionPreset('rescale-preset',    'rescale-w',    'rescale-h');
  wireResolutionPreset('rescale-yt-preset', 'rescale-yt-w', 'rescale-yt-h');
  wireResolutionPreset('rescale-rl-preset', 'rescale-rl-w', 'rescale-rl-h');

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
    markTimelineDirty();
    renderTimeline();
  });

  // For Play/Capture, use the currentSeq as-is (which carries the linked
  // preset's settings). Don't read from the preset-tab UI controls — they're
  // for editing presets, NOT for live playback overrides.
  document.getElementById('btn-play').addEventListener('click', async () => {
    if (!currentSeq) return;
    await callLua('set_active_sequence', { sequence: currentSeq });
    callLua('play', { sequence: currentSeq });
  });

  document.getElementById('btn-capture').addEventListener('click', async () => {
    if (!currentSeq) return;
    await callLua('set_active_sequence', { sequence: currentSeq });
    const r = await callLua('capture_and_play', {});
    if (r.error) alert(r.error);
    else document.getElementById('last-output').textContent = 'capturing → ' + r.output;
  });

  // ─── Tabs ──────────────────────────────────────────────────────
  document.querySelectorAll('.tab-btn').forEach((btn) => {
    btn.addEventListener('click', async () => {
      const goingTo = btn.dataset.tab;
      const currentTabBtn = document.querySelector('.tab-btn.active');
      const currentTab = currentTabBtn && currentTabBtn.dataset.tab;
      // Block leaving Preset Settings with unsaved edits.
      if (currentTab === 'preset' && goingTo !== 'preset' && !confirmDiscardDirty()) return;
      // Block leaving Timeline with unsaved events / link changes.
      if (currentTab === 'timeline' && goingTo !== 'timeline' && !confirmDiscardTimelineDirty()) return;
      document.querySelectorAll('.tab-btn').forEach(b => b.classList.toggle('active', b === btn));
      document.querySelectorAll('.tab').forEach(t => t.hidden = t.dataset.tab !== goingTo);
      if (goingTo === 'manage') await renderManagePane();
      if (goingTo === 'preset' && !editingPreset) applyEditingPresetToControls();
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
        renderTimeline(); updateActiveLabels();
        if (currentSeq.preset_name) {
          document.getElementById('preset-select').value = currentSeq.preset_name;
          activePresetName = currentSeq.preset_name;
        }
        // Preset-select-edit stays empty until user picks one to edit.
        updateDirtyBadge();
      }
    } catch (_) {}
    pollPushLoop();
  })();
})();
