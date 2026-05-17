// app.js — SDR webview client. Talks to Lua via sdr:// URLs intercepted by
// hs.webview navigationCallback. Lua responds via window.SDR_BRIDGE_RESPONSE().

(function () {
  const PORT = window.SDR_PORT;
  const BASE = 'http://127.0.0.1:' + PORT;

  async function callLua(handler, payload) {
    const p = encodeURIComponent(JSON.stringify(payload || {}));
    const resp = await fetch(BASE + '/call/' + handler + '?p=' + p);
    const data = await resp.json();
    if (data.ok) return data.result;
    throw new Error(typeof data.result === 'string' ? data.result : JSON.stringify(data.result));
  }

  // Long-poll for push events from Lua.
  async function pollPushLoop() {
    while (true) {
      try {
        const resp = await fetch(BASE + '/push');
        const data = await resp.json();
        (data.events || []).forEach((ev) => {
          const fn = pushHandlers[ev.name];
          if (fn) fn(ev.data || {});
        });
      } catch (e) {
        // backoff on error
        await new Promise(r => setTimeout(r, 1000));
        continue;
      }
      // small gap before re-poll
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

  // ─── Sequence list + load ──────────────────────────────────────
  async function refreshSequenceList() {
    const list = await callLua('list_sequences', {});
    const sel = document.getElementById('seq-select');
    sel.innerHTML = '<option value="">— choose —</option>';
    (list || []).forEach((name) => {
      const opt = document.createElement('option');
      opt.value = name;
      opt.textContent = name;
      sel.appendChild(opt);
    });
  }

  async function loadSequence(name) {
    if (!name) return;
    const seq = await callLua('load_sequence', { name });
    currentSeq = seq;
    document.getElementById('seq-name').value = name;
    applySeqToUI();
    renderTimeline();
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
    return currentSeq.viewport;
  }

  // ─── Timeline ──────────────────────────────────────────────────
  function totalDurationMs(seq) {
    return (seq.events || []).reduce((acc, e) => acc + (e.pause_before_ms || 0), 0);
  }

  function renderTimeline() {
    const wrap = document.getElementById('timeline');
    wrap.innerHTML = '';
    if (!currentSeq) return;
    const events = currentSeq.events || [];
    document.getElementById('timeline-meta').textContent =
      `${events.length} events · ${(totalDurationMs(currentSeq) / 1000).toFixed(2)}s total`;

    events.forEach((evt, idx) => {
      // Pause chip BEFORE the event
      const pauseChip = document.createElement('span');
      pauseChip.className = 'chip pause';
      const pauseInput = document.createElement('input');
      pauseInput.type = 'number';
      pauseInput.value = evt.pause_before_ms || 0;
      pauseInput.min = 0;
      pauseInput.title = 'pause before (ms)';
      pauseInput.addEventListener('change', () => {
        evt.pause_before_ms = parseInt(pauseInput.value, 10) || 0;
        renderTimeline();
      });
      pauseChip.appendChild(pauseInput);
      pauseChip.appendChild(document.createTextNode(' ms'));
      wrap.appendChild(pauseChip);

      // Event chip
      const evChip = document.createElement('span');
      evChip.className = 'chip event ' + (evt.type || '');
      evChip.title = JSON.stringify(evt, null, 2);
      let label = evt.type;
      if (evt.type && evt.type.startsWith('mouse_')) {
        label += ` ${evt.button || ''} @${evt.x},${evt.y}`;
      } else if (evt.type === 'key_down' || evt.type === 'key_up') {
        label += ` ${(evt.modifiers || []).map(m => m + '+').join('')}${evt.key || ''}`;
      }
      evChip.textContent = label;
      evChip.addEventListener('click', () => {
        const choice = prompt('Action: (d)elete  (c)omment  (s)kip', 'c');
        if (choice === 'd') {
          currentSeq.events.splice(idx, 1);
          renderTimeline();
        } else if (choice === 'c') {
          const c = prompt('Comment:', evt.comment || '');
          if (c !== null) { evt.comment = c; renderTimeline(); }
        }
      });
      wrap.appendChild(evChip);
    });
  }

  // ─── Bindings ──────────────────────────────────────────────────
  document.getElementById('seq-select').addEventListener('change', (e) => {
    loadSequence(e.target.value);
  });

  document.getElementById('btn-new').addEventListener('click', async () => {
    const name = document.getElementById('seq-name').value.trim();
    if (!name) return alert('enter a name');
    currentSeq = await callLua('new_sequence', { name });
    applySeqToUI();
    renderTimeline();
    refreshSequenceList();
  });

  document.getElementById('btn-load').addEventListener('click', () => {
    const name = document.getElementById('seq-name').value.trim();
    if (name) loadSequence(name);
  });

  document.getElementById('btn-save').addEventListener('click', async () => {
    if (!currentSeq) return;
    readVpFromUI();
    await callLua('save_sequence', { sequence: currentSeq });
    document.getElementById('last-output').textContent = 'saved ' + currentSeq.name;
  });

  document.getElementById('btn-ping').addEventListener('click', async () => {
    const r = await callLua('ping_companion', {});
    document.getElementById('last-output').textContent = JSON.stringify(r);
  });

  document.getElementById('vp-preset').addEventListener('change', (e) => {
    const opt = e.target.selectedOptions[0];
    if (opt.dataset.w) document.getElementById('vp-w').value = opt.dataset.w;
    if (opt.dataset.h) document.getElementById('vp-h').value = opt.dataset.h;
  });

  document.getElementById('btn-apply-vp').addEventListener('click', async () => {
    readVpFromUI();
    const result = await callLua('apply_viewport', { sequence: currentSeq });
    if (result.error) {
      document.getElementById('vp-region').textContent = 'ERROR: ' + result.error;
    } else {
      const r = result.region;
      document.getElementById('vp-region').textContent =
        `region: ${r.x},${r.y} ${r.w}×${r.h}`;
      currentSeq.viewport.region = r;
    }
  });

  document.getElementById('btn-show-overlay').addEventListener('click', () => callLua('show_overlay', {}));
  document.getElementById('btn-hide-overlay').addEventListener('click', () => callLua('hide_overlay', {}));

  document.getElementById('btn-rec').addEventListener('click', async () => {
    if (!currentSeq) return alert('load a sequence first');
    await callLua('start_record', {});
    setTimeout(() => {
      // Convenience: minimise tool window so user can click in SU. Hammerspoon
      // doesn't expose hide from JS; user can use ⌃⌥⌘V.
    }, 100);
  });

  document.getElementById('btn-play').addEventListener('click', () => {
    if (!currentSeq) return;
    callLua('play', { sequence: currentSeq, lead_ms: 500, tail_ms: 500 });
  });

  document.getElementById('btn-capture').addEventListener('click', async () => {
    if (!currentSeq) return;
    readVpFromUI();
    const r = await callLua('capture_and_play', { lead_ms: 1000, tail_ms: 1000 });
    if (r.error) alert(r.error);
    else document.getElementById('last-output').textContent = 'capturing → ' + r.output;
  });

  // ─── Init ──────────────────────────────────────────────────────
  (async () => {
    await refreshSequenceList();
    // Auto-load the persisted active sequence (set on the Lua side).
    try {
      const active = await callLua('get_active_sequence', {});
      if (active && active.name && active.sequence) {
        currentSeq = active.sequence;
        document.getElementById('seq-name').value = active.name;
        const sel = document.getElementById('seq-select');
        if ([...sel.options].some(o => o.value === active.name)) {
          sel.value = active.name;
        }
        applySeqToUI();
        renderTimeline();
      }
    } catch (_) { /* no active sequence */ }
    pollPushLoop();
  })();
})();
