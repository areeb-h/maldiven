/* Drift Station server panel. Polls /api/status (served by tools/host_station.py)
 * twice a second and sends commands to /api/command. No dependencies; the QR
 * code comes from qr.js. Roles are never in the status during a round, so
 * nothing here can reveal them; the result card shows the reveal afterwards. */
(function () {
  "use strict";

  const POLL_MS = 500;
  const LOST_AFTER = 4; // failed polls before the "lost contact" screen
  const PHASES = ["lobby", "briefing", "stabilise", "extraction", "result"];
  const PHASE_TITLE = { lobby: "Lobby", briefing: "Briefing", stabilise: "Restore power", extraction: "Extraction", result: "Round over" };
  const HOLDING = { cell: ["i-cell", "Cell"], core: ["i-core", "Core"], gun: ["i-gun", "Gun"] };

  const $ = (id) => document.getElementById(id);
  const ui = {
    name: $("room-name"), version: $("version"), pill: $("status-pill"), pillText: $("status-text"),
    address: $("address"), addressMore: $("address-more"), publicAddress: $("public-address"),
    qr: $("qr"), qrFigure: $("qr-figure"), copyAddress: $("copy-address"),
    roundTitle: $("round-title"), roundEyebrow: $("round-eyebrow"), clock: $("round-clock"), clockValue: $("round-time"),
    phases: $("phases"), lobby: $("round-lobby"), live: $("round-live"), result: $("round-result"),
    lobbyLead: $("lobby-lead"), start: $("start-round"), startReason: $("start-reason"),
    meter: $("round-meter"), cells: $("cells"), standing: $("standing"), countdowns: $("countdowns"),
    lobbyLive: $("lobby-live"), lobbyResult: $("lobby-result"), lobbyCountdown: $("lobby-countdown"),
    verdict: $("verdict"), verdictIcon: $("verdict-icon"), verdictTitle: $("verdict-title"), verdictReason: $("verdict-reason"),
    reveal: $("reveal"), timeline: $("timeline"), timelineBox: $("timeline-box"),
    crew: $("crew"), crewCount: $("crew-count"),
    feed: $("feed"), feedEmpty: $("feed-empty"), uptime: $("uptime"), ports: $("footer-ports"),
    overlay: $("overlay"), overlayTitle: $("overlay-title"), overlayText: $("overlay-text"), overlayLog: $("overlay-log"),
    overlayIcon: $("overlay-icon-use"), restart: $("restart"), restartLabel: $("restart-label"),
    help: $("help"), helpOpen: $("help-open"), helpClose: $("help-close"), scrim: $("help-scrim"),
    firewallText: $("firewall-text"), firewallCode: $("firewall-code"), firewallCommand: $("firewall-command"),
    firewallNotes: $("firewall-notes"), copyFirewall: $("copy-firewall"), tipFirewall: $("tip-firewall"), helpAddress: $("help-address"),
    stop: $("stop-server"), confirm: $("confirm"), confirmTitle: $("confirm-title"), confirmText: $("confirm-text"), confirmOk: $("confirm-ok"),
    toasts: $("toasts"),
  };

  let snap = null;
  let receivedAt = 0;
  let failures = 0;
  let shownAddress = null;
  let nameEditing = false;
  const members = new Map(); // id -> <li>
  const feedSeen = new Set();
  let firstRender = true;

  // --- Helpers ------------------------------------------------------------------

  function el(tag, cls, text) {
    const node = document.createElement(tag);
    if (cls) node.className = cls;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function icon(id, cls = "icon") {
    const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    svg.setAttribute("class", cls);
    svg.setAttribute("aria-hidden", "true");
    const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
    use.setAttribute("href", "#" + id);
    svg.appendChild(use);
    return svg;
  }

  function tag(cls, iconId, text) {
    const node = el("span", "tag " + cls);
    if (iconId) node.appendChild(icon(iconId));
    node.appendChild(el("span", "", text));
    return node;
  }

  /** Keyed tags: update text in place so their entrance animation plays once. */
  function syncTags(container, wanted) {
    const keep = new Set(wanted.map((t) => t.key));
    for (const child of [...container.children]) if (!keep.has(child.dataset.key)) child.remove();
    wanted.forEach((t, index) => {
      let node = container.querySelector(`[data-key="${t.key}"]`);
      if (!node || node.dataset.cls !== t.cls) {
        node?.remove();
        node = tag(t.cls, t.icon, t.text);
        node.dataset.key = t.key;
        node.dataset.cls = t.cls;
      } else if (node.lastChild.textContent !== t.text) {
        node.lastChild.textContent = t.text;
      }
      if (container.children[index] !== node) container.insertBefore(node, container.children[index] || null);
    });
  }

  function clock(seconds) {
    const s = Math.max(0, Math.ceil(seconds));
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
  }

  function initials(name) {
    const words = String(name).trim().split(/\s+/).filter(Boolean);
    if (!words.length) return "?";
    const first = [...words[0]][0] || "?";
    const second = words.length > 1 ? [...words[1]][0] || "" : [...words[0]][1] || "";
    return (first + second).toUpperCase();
  }

  function plural(n, one, many) {
    return `${n} ${n === 1 ? one : many}`;
  }

  /** Seconds that passed since this status arrived: keeps timers smooth between polls. */
  function since() {
    return (performance.now() - receivedAt) / 1000;
  }

  function toast(text, kind = "info") {
    const node = el("div", `toast toast--${kind}`);
    node.appendChild(icon(kind === "error" ? "i-warning" : kind === "good" ? "i-check" : "i-info"));
    node.appendChild(el("span", "", text));
    ui.toasts.appendChild(node);
    setTimeout(() => {
      node.classList.add("is-leaving");
      node.addEventListener("animationend", () => node.remove(), { once: true });
    }, kind === "error" ? 5200 : 3200);
  }

  async function copy(text, button) {
    try {
      await navigator.clipboard.writeText(text);
    } catch {
      const area = el("textarea");
      area.value = text;
      area.setAttribute("readonly", "");
      area.className = "visually-hidden";
      document.body.appendChild(area);
      area.select();
      document.execCommand("copy");
      area.remove();
    }
    if (button) {
      const use = button.querySelector("use");
      button.classList.add("is-done");
      use.setAttribute("href", "#i-check");
      setTimeout(() => {
        button.classList.remove("is-done");
        use.setAttribute("href", "#i-copy");
      }, 1600);
    }
    toast("Copied " + text, "good");
  }

  async function post(path, body) {
    try {
      const response = await fetch(path, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-Drift-Panel": "1" },
        body: JSON.stringify(body || {}),
      });
      return await response.json();
    } catch {
      return { ok: false, error: "The launcher isn't answering." };
    }
  }

  async function command(cmd, args, button) {
    button?.classList.add("is-busy");
    const reply = await post("/api/command", { cmd, args: args || {} });
    button?.classList.remove("is-busy");
    if (!reply.ok) toast(reply.error || "That didn't work.", "error");
    poll.soon();
    return reply;
  }

  function confirmAction(title, text, okLabel) {
    return new Promise((resolve) => {
      ui.confirmTitle.textContent = title;
      ui.confirmText.textContent = text;
      ui.confirmOk.textContent = okLabel;
      ui.confirm.returnValue = "cancel";
      ui.confirm.addEventListener("close", () => resolve(ui.confirm.returnValue === "ok"), { once: true });
      ui.confirm.showModal();
      $("confirm-cancel").focus();
    });
  }

  // --- Rendering --------------------------------------------------------------------

  function render(data) {
    snap = data;
    receivedAt = performance.now();
    const launcher = data.launcher || {};
    const server = data.server;
    renderOverlay(launcher, server);
    renderFirewall(launcher);
    if (server) {
      renderHeader(server, launcher);
      renderJoin(server, launcher);
      renderRound(server);
      renderCrew(server);
      renderFeed(server.feed || []);
      ui.ports.textContent = `UDP ${server.port} play · UDP ${server.discovery_port} discovery`;
      ui.uptime.textContent = "Up " + duration(server.uptime);
    }
    if (firstRender) {
      firstRender = false;
      document.body.classList.remove("is-booting");
    }
  }

  function duration(seconds) {
    const m = Math.floor((seconds || 0) / 60);
    if (m < 1) return "less than a minute";
    if (m < 60) return plural(m, "min", "min");
    return `${Math.floor(m / 60)} h ${m % 60} min`;
  }

  function renderOverlay(launcher, server) {
    const state = launcher.state;
    let view = null;
    if (state === "starting" || (state === "running" && !server)) {
      view = { kind: "wait", icon: "i-refresh", title: "Starting the station", text: "Loading the station on this computer. This takes a few seconds." };
    } else if (state === "stopping") {
      view = { kind: "wait", icon: "i-refresh", title: "Closing the station", text: "Telling the phones the station is closing…" };
    } else if (state === "unresponsive") {
      view = { kind: "wait", icon: "i-refresh", title: "The server isn't responding", text: "Waiting for it to catch up. If this lasts, restart it.", button: "Restart server" };
    } else if (state === "stopped") {
      view = { kind: "info", icon: "i-power", title: "The station is closed", text: "Everyone was sent back to their home screen. Start it again whenever you're ready.", button: "Start server" };
    } else if (state === "crashed") {
      view = { kind: "error", icon: "i-warning", title: "The server stopped", text: launcher.error || "The game server exited unexpectedly.", button: "Restart server", log: launcher.log_tail };
    }
    if (!view) {
      ui.overlay.hidden = true;
      return;
    }
    showOverlay(view);
  }

  function showOverlay(view) {
    ui.overlay.hidden = false;
    ui.overlay.className = "overlay is-" + view.kind;
    const color = { wait: "var(--accent)", info: "var(--accent)", error: "var(--danger)" }[view.kind];
    ui.overlay.style.setProperty("--c", color);
    ui.overlayIcon.setAttribute("href", "#" + view.icon);
    ui.overlayTitle.textContent = view.title;
    ui.overlayText.textContent = view.text;
    const log = (view.log || []).join("\n");
    ui.overlayLog.hidden = !log;
    ui.overlayLog.textContent = log;
    ui.restart.hidden = !view.button;
    if (view.button) ui.restartLabel.textContent = view.button;
  }

  function renderLost() {
    showOverlay({
      kind: "error", icon: "i-warning", title: "Lost contact with the launcher",
      text: "The terminal running host_station.py was closed or stopped. Start it again (python tools/host_station.py); this page reconnects by itself.",
    });
    ui.pill.className = "pill pill--down";
    ui.pillText.textContent = "Offline";
    document.title = "Drift Station Server · offline";
  }

  function renderHeader(server, launcher) {
    if (!nameEditing && document.activeElement !== ui.name) ui.name.value = server.room_name;
    ui.version.textContent = "v" + server.version;
    const n = server.players.length;
    let cls = "pill--live";
    let text = `Lobby · ${plural(n, "player", "players")}`;
    if (server.stopping) {
      cls = "pill--down";
      text = "Closing";
    } else if (server.state === "result") {
      cls = "pill--round";
      text = "Round over";
    } else if (server.state !== "lobby") {
      cls = "pill--round";
      text = `In round · ${PHASE_TITLE[server.state]}`;
    }
    ui.pill.className = "pill " + cls;
    ui.pillText.textContent = text;
    document.title = `${server.room_name} · ${server.state === "lobby" ? `Lobby (${n})` : PHASE_TITLE[server.state]}`;
  }

  function renderJoin(server, launcher) {
    const addresses = [...(server.addresses || [])];
    const best = launcher.primary_address;
    if (best && addresses.includes(best)) {
      addresses.splice(addresses.indexOf(best), 1);
      addresses.unshift(best);
    }
    const address = addresses[0] || null;
    ui.address.textContent = address || "No Wi-Fi address";
    ui.address.classList.toggle("is-none", !address);
    ui.copyAddress.hidden = !address;
    ui.qrFigure.hidden = !address;
    ui.helpAddress.textContent = address || "this computer's IP address";
    const more = addresses.slice(1, 4);
    ui.addressMore.hidden = !more.length;
    ui.addressMore.textContent = more.length ? "Other networks: " + more.join(", ") : "";
    ui.publicAddress.hidden = !launcher.public_address;
    ui.publicAddress.textContent = launcher.public_address ? `Internet (tunnel): ${launcher.public_address}` : "";
    if (address !== shownAddress) {
      shownAddress = address;
      if (address && window.DriftQR) {
        const code = window.DriftQR.encode(address);
        const quiet = 0;
        ui.qr.setAttribute("viewBox", `${-quiet} ${-quiet} ${code.size + quiet * 2} ${code.size + quiet * 2}`);
        ui.qr.replaceChildren();
        const path = document.createElementNS("http://www.w3.org/2000/svg", "path");
        path.setAttribute("d", window.DriftQR.toSvgPath(code));
        ui.qr.appendChild(path);
        ui.qr.setAttribute("aria-label", "QR code of " + address);
      }
    }
  }

  function renderRound(server) {
    const state = server.state;
    const round = server.round || {};
    const index = PHASES.indexOf(state);
    [...ui.phases.children].forEach((li, i) => {
      li.classList.toggle("is-done", i < index);
      li.classList.toggle("is-current", i === index);
      if (i === index) li.setAttribute("aria-current", "step");
      else li.removeAttribute("aria-current");
    });
    ui.roundTitle.textContent = PHASE_TITLE[state] || "Lobby";
    ui.roundEyebrow.textContent = state === "lobby" ? "Round" : state === "result" ? "Result" : "Round in progress";
    ui.lobby.hidden = state !== "lobby";
    ui.live.hidden = state === "lobby" || state === "result";
    ui.result.hidden = state !== "result";
    ui.clock.hidden = state === "lobby" || state === "result";

    if (state === "lobby") {
      const n = server.players.length;
      const need = server.min_players || 2;
      const names = server.players.map((p) => p.name);
      if (n === 0) ui.lobbyLead.textContent = "Waiting for the crew. Phones on this Wi-Fi can see the station now.";
      else if (n < need) ui.lobbyLead.textContent = `${names[0]} is aboard. One more player and you can start.`;
      else ui.lobbyLead.textContent = `${plural(n, "crewmate", "crewmates")} aboard. One of them will secretly be the infiltrator.`;
      const ready = n >= need && !server.stopping;
      ui.start.disabled = !ready;
      ui.startReason.replaceChildren();
      if (!ready) {
        ui.startReason.appendChild(icon("i-info"));
        ui.startReason.appendChild(el("span", "", `Needs at least ${need} players · ${n} connected`));
      } else {
        ui.startReason.appendChild(el("span", "", "Phones that join after the start wait for the next round."));
      }
    } else if (state === "result") {
      const result = round.result || {};
      const winner = result.winner;
      ui.verdict.className = "verdict" + (winner === "infiltrator" ? " verdict--infiltrator" : winner === "crew" ? "" : " verdict--none");
      ui.verdictIcon.setAttribute("href", winner === "infiltrator" ? "#i-mask" : winner === "crew" ? "#i-shield" : "#i-info");
      ui.verdictTitle.textContent = winner === "infiltrator" ? "Infiltrator wins" : winner === "crew" ? "Crew win" : "No winner";
      ui.verdictReason.textContent = result.reason || "";
      ui.reveal.replaceChildren();
      if (result.infiltrator && result.infiltrator !== "nobody") {
        ui.reveal.append("The infiltrator was ", el("strong", "", result.infiltrator), ".");
      }
      const lines = result.timeline || [];
      if (ui.timeline.childElementCount !== lines.length) {
        ui.timeline.replaceChildren(...lines.map((line) => el("li", "", line)));
      }
      ui.timelineBox.hidden = !lines.length;
    }
    tick();
  }

  /** Timers and countdowns, interpolated between polls (runs every animation frame). */
  function tick() {
    const server = snap && snap.server;
    if (!server || !server.round) return;
    const round = server.round;
    const dt = since();
    if (server.state === "result") {
      const left = round.lobby_in - dt;
      ui.lobbyCountdown.textContent = round.lobby_in >= 0 ? `Everyone returns to the lobby in ${Math.max(0, Math.ceil(left))} s` : "";
      return;
    }
    if (server.state === "lobby") return;
    const left = Math.max(0, round.left - dt);
    ui.clockValue.textContent = clock(left);
    ui.clock.classList.toggle("is-low", left < 60);
    ui.meter.style.width = `${(left / round.total) * 100}%`;
    ui.meter.parentElement.classList.toggle("is-low", left < 60);
    if (ui.cells.childElementCount !== round.cells_total) {
      ui.cells.replaceChildren(...Array.from({ length: round.cells_total }, () => el("span")));
    }
    [...ui.cells.children].forEach((cell, i) => cell.classList.toggle("is-on", i < round.cells));
    ui.cells.setAttribute("aria-label", `${round.cells} of ${round.cells_total} power cells online`);
    const alive = server.players.filter((p) => p.state === "ok" || p.state === "downed").length;
    const inRound = server.players.filter((p) => p.state !== "waiting").length;
    ui.standing.textContent = `${alive} / ${inRound}`;
    const wanted = [];
    if (server.state === "briefing") wanted.push({ key: "briefing", cls: "tag--quiet", icon: "i-info", text: `Briefing ${clock(round.briefing_left - dt)}` });
    if (round.shuttle_left >= 0) wanted.push({ key: "shuttle", cls: "tag--crew", icon: "i-shuttle", text: `Shuttle ${clock(round.shuttle_left - dt)}` });
    if (round.pod_left >= 0) wanted.push({ key: "pod", cls: "tag--danger", icon: "i-pod", text: `Cargo pod ${clock(round.pod_left - dt)}` });
    if (round.blackout_left > 0) wanted.push({ key: "blackout", cls: "tag--amber", icon: "i-moon", text: `Blackout ${clock(round.blackout_left - dt)}` });
    if (round.airlock === "warning") wanted.push({ key: "airlock", cls: "tag--amber", icon: "i-airlock", text: "Airlock cycling" });
    syncTags(ui.countdowns, wanted);
  }

  function renderCrew(server) {
    const players = server.players;
    ui.crewCount.replaceChildren(el("b", "", String(players.length)), ` / ${server.max_players}`);
    const live = new Set(players.map((p) => p.id));
    for (const [id, node] of members) {
      if (!live.has(id) && !node.classList.contains("is-leaving")) {
        node.classList.add("is-leaving");
        node.addEventListener("animationend", () => {
          node.remove();
          members.delete(id);
        }, { once: true });
      }
    }
    players.forEach((p, index) => {
      let node = members.get(p.id);
      if (!node || node.classList.contains("is-leaving")) {
        node?.remove();
        node = memberNode(p);
        members.set(p.id, node);
      }
      updateMember(node, p, server.state);
      const target = ui.crew.children[index];
      if (target !== node) ui.crew.insertBefore(node, target || null);
    });
    // Open seats after the players (leaving cards finish their exit in place).
    const empties = [...ui.crew.querySelectorAll(".member--empty")];
    const wantEmpty = Math.max(0, Math.min(server.max_players, 8) - players.length);
    while (empties.length > wantEmpty) empties.pop().remove();
    while (empties.length < wantEmpty) {
      const seat = el("li", "member member--empty");
      const face = el("span", "member__face");
      face.appendChild(icon("i-user"));
      seat.append(face, el("span", "member__name", "Open seat"));
      empties.push(seat);
    }
    empties.forEach((seat) => ui.crew.appendChild(seat));
  }

  function memberNode(p) {
    const li = el("li", "member");
    li.dataset.id = p.id;
    const face = el("span", "member__face");
    const body = el("div", "member__body");
    const name = el("span", "member__name");
    const chips = el("span", "member__chips");
    body.append(name, chips);
    const kick = el("button", "icon-btn");
    kick.type = "button";
    kick.appendChild(icon("i-kick"));
    kick.addEventListener("click", async () => {
      const who = li.dataset.name;
      const ok = await confirmAction(`Remove ${who}?`, `${who}'s phone goes back to its home screen with a message. They can join again later.`, "Remove");
      if (ok) {
        const reply = await command("kick", { id: Number(li.dataset.id) }, kick);
        if (reply.ok) toast(`${who} was removed`, "good");
      }
    });
    li.append(face, body, kick);
    li._parts = { face, name, chips, kick };
    return li;
  }

  function updateMember(li, p, phase) {
    const parts = li._parts;
    li.style.setProperty("--c", p.color);
    li.dataset.name = p.name;
    if (parts.name.textContent !== p.name) {
      parts.name.textContent = p.name;
      parts.face.textContent = initials(p.name);
      parts.kick.setAttribute("aria-label", `Remove ${p.name}`);
      parts.kick.title = `Remove ${p.name}`;
    }
    li.classList.toggle("is-dead", p.state === "dead");
    const wanted = [];
    switch (p.state) {
      case "lobby": wanted.push({ key: "state", cls: "tag--good", icon: "i-check", text: "Connected" }); break;
      case "ok": wanted.push({ key: "state", cls: "tag--crew", icon: "i-user", text: "Active" }); break;
      case "downed": wanted.push({ key: "state", cls: "tag--amber", icon: "i-down", text: p.down_left > 0 ? `Downed ${clock(p.down_left - since())}` : "Downed" }); break;
      case "dead": wanted.push({ key: "state", cls: "tag--ghost", icon: "i-ghost", text: "Spaced" }); break;
      case "waiting": wanted.push({ key: "state", cls: "tag--quiet", icon: "i-info", text: "Next round" }); break;
    }
    if (p.holding && HOLDING[p.holding]) wanted.push({ key: "hold", cls: "tag--quiet", icon: HOLDING[p.holding][0], text: HOLDING[p.holding][1] });
    if (p.carrying_body) wanted.push({ key: "body", cls: "tag--quiet", icon: "i-carry", text: "Carrying" });
    syncTags(parts.chips, wanted);
    let ping = parts.chips.parentElement.querySelector(".ping");
    if (p.ping_ms > 0) {
      if (!ping) {
        ping = el("span", "ping");
        const bars = el("i");
        bars.append(el("b"), el("b"), el("b"));
        ping.append(bars, el("span"));
        parts.chips.parentElement.appendChild(ping);
      }
      ping.className = "ping " + (p.ping_ms < 60 ? "is-good" : p.ping_ms < 150 ? "is-ok" : "is-bad");
      ping.lastChild.textContent = `${p.ping_ms} ms`;
    } else if (ping) {
      ping.remove();
    }
  }

  function renderFeed(feed) {
    ui.feedEmpty.hidden = feed.length > 0;
    const fresh = feed.filter((entry) => !feedSeen.has(entry.id));
    for (const entry of fresh) {
      feedSeen.add(entry.id);
      const li = el("li", "k-" + (entry.kind || "info"));
      const when = new Date(entry.t * 1000);
      const time = el("time", "", when.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" }));
      time.dateTime = when.toISOString();
      li.append(time, el("span", "dot"), el("span", "", entry.text));
      if (firstRender) li.style.animation = "none";
      ui.feed.prepend(li);
    }
    while (ui.feed.childElementCount > 60) ui.feed.lastChild.remove();
  }

  function renderFirewall(launcher) {
    const fw = launcher.firewall || {};
    const os = launcher.os;
    const texts = {
      allowed: "Windows Firewall already allows the game ports on this computer.",
      off: "The firewall is off for this network, so it isn't blocking the phones.",
      likely_blocked: "Windows Firewall will probably block the phones. Run this once in a terminal opened with “Run as administrator”:",
      blocked: "A Windows Firewall rule blocks Godot (someone pressed Cancel on the Windows prompt). Remove it in Windows Security › Firewall & network protection › Allow an app, then run this as administrator:",
      prompt: "macOS may ask whether Godot may accept incoming connections. Click Allow.",
    };
    ui.firewallText.textContent = texts[fw.state] || (os === "Windows"
      ? "The computer must accept incoming UDP on ports 24600 (game) and 24601 (Nearby stations). If phones can't connect, run this once as administrator:"
      : "The computer must accept incoming UDP on ports 24600 (game) and 24601 (Nearby stations).");
    const command = fw.command && fw.state !== "allowed" && fw.state !== "off" ? fw.command : null;
    ui.firewallCode.hidden = !command;
    ui.firewallCommand.textContent = command || "";
    ui.tipFirewall.classList.toggle("is-warn", fw.state === "likely_blocked" || fw.state === "blocked");
    const notes = fw.notes || [];
    if (ui.firewallNotes.childElementCount !== notes.length) ui.firewallNotes.replaceChildren(...notes.map((n) => el("li", "", n)));
    ui.helpOpen.classList.toggle("has-alert", fw.state === "likely_blocked" || fw.state === "blocked");
    let hint = $("firewall-hint");
    const warn = fw.state === "likely_blocked" || fw.state === "blocked";
    if (warn && !hint) {
      hint = el("button", "hint");
      hint.id = "firewall-hint";
      hint.type = "button";
      hint.append(icon("i-shield"), el("span", "", "Windows Firewall may block the phones. "), el("u", "", "How to fix"));
      hint.addEventListener("click", openHelp);
      document.querySelector(".card--join").appendChild(hint);
    } else if (!warn && hint) {
      hint.remove();
    }
  }

  // --- Polling --------------------------------------------------------------------

  let pollTimer = 0;
  async function poll() {
    clearTimeout(pollTimer);
    try {
      const response = await fetch("/api/status", { cache: "no-store" });
      if (!response.ok) throw new Error(String(response.status));
      const data = await response.json();
      failures = 0;
      render(data);
    } catch {
      failures++;
      if (failures >= LOST_AFTER) renderLost();
    }
    pollTimer = setTimeout(poll, POLL_MS);
  }
  poll.soon = () => {
    clearTimeout(pollTimer);
    pollTimer = setTimeout(poll, 80);
  };

  function frame() {
    tick();
    const server = snap && snap.server;
    if (server && server.state !== "lobby") {
      for (const p of server.players) {
        if (p.state === "downed" && members.has(p.id)) updateMember(members.get(p.id), p, server.state);
      }
    }
    setTimeout(() => requestAnimationFrame(frame), 250);
  }

  // --- Wiring --------------------------------------------------------------------------

  function openHelp() {
    ui.scrim.hidden = false;
    ui.help.classList.add("is-open");
    ui.help.setAttribute("aria-hidden", "false");
    ui.helpOpen.setAttribute("aria-expanded", "true");
    setTimeout(() => ui.helpClose.focus(), 50);
  }
  function closeHelp() {
    ui.scrim.hidden = true;
    ui.help.classList.remove("is-open");
    ui.help.setAttribute("aria-hidden", "true");
    ui.helpOpen.setAttribute("aria-expanded", "false");
    ui.helpOpen.focus();
  }
  ui.helpOpen.addEventListener("click", openHelp);
  ui.helpClose.addEventListener("click", closeHelp);
  ui.scrim.addEventListener("click", closeHelp);
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && ui.help.classList.contains("is-open")) closeHelp();
  });

  ui.copyAddress.addEventListener("click", () => shownAddress && copy(shownAddress, ui.copyAddress));
  ui.copyFirewall.addEventListener("click", () => copy(ui.firewallCommand.textContent, ui.copyFirewall));

  ui.name.addEventListener("focus", () => {
    nameEditing = true;
    ui.name.select();
  });
  ui.name.addEventListener("keydown", (event) => {
    if (event.key === "Enter") ui.name.blur();
    if (event.key === "Escape") {
      ui.name.value = snap?.server?.room_name || ui.name.value;
      ui.name.blur();
    }
  });
  ui.name.addEventListener("blur", async () => {
    nameEditing = false;
    const next = ui.name.value.replace(/\s+/g, " ").trim();
    const current = snap?.server?.room_name;
    if (!next) {
      ui.name.value = current || "";
      return;
    }
    if (next === current) return;
    const reply = await command("set_room_name", { name: next });
    if (reply.ok) {
      const label = ui.name.parentElement;
      label.classList.add("is-saved");
      setTimeout(() => label.classList.remove("is-saved"), 1400);
      toast("Station renamed. Phones see the new name now.", "good");
    } else {
      ui.name.value = current || "";
    }
  });

  ui.start.addEventListener("click", async () => {
    const reply = await command("start_round", {}, ui.start);
    if (reply.ok) toast("Round starting. Roles are on the phones.", "good");
  });
  ui.lobbyLive.addEventListener("click", async () => {
    const ok = await confirmAction("End the round?", "Everyone goes back to the lobby and this round ends without a winner.", "End round");
    if (ok) command("back_to_lobby", {}, ui.lobbyLive);
  });
  ui.lobbyResult.addEventListener("click", () => command("back_to_lobby", {}, ui.lobbyResult));
  ui.stop.addEventListener("click", async () => {
    const ok = await confirmAction("Stop the server?", "Everyone on the station goes back to their home screen. You can start it again from this page.", "Stop server");
    if (ok) {
      await command("stop", {}, ui.stop);
      poll.soon();
    }
  });
  ui.restart.addEventListener("click", async () => {
    ui.restart.classList.add("is-busy");
    const reply = await post("/api/restart", {});
    ui.restart.classList.remove("is-busy");
    if (!reply.ok) toast(reply.error || "Couldn't restart the server.", "error");
    poll.soon();
  });

  poll();
  requestAnimationFrame(frame);
})();
