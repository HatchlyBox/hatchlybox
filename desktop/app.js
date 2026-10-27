// Hatchlybox desktop: the page. Everything goes through the engine (hatchlybox <command>) via Desk.java's /api.
"use strict";

const SYSTEMS = { android: "Android", web: "Web", linux: "Linux", omarchy: "Omarchy", macos: "macOS", windows: "Windows" };
const ACTIVE = ["queued", "starting", "agent", "checking", "building", "fixing", "installing", "interrupted", "waiting"];
const $ = (id) => document.getElementById(id);
const state = { platform: null, settings: {}, agents: [], creations: [], apps: [], kind: "auto", item: null, job: null, jobSeen: 0 };

// ---- talking to the engine ----

async function call(args, opts = {}) {
  const r = await fetch("/api/run", {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Hatchlybox": "1" },
    body: JSON.stringify(Object.assign({ args, bg: !!opts.bg }, opts.input != null ? { input: opts.input } : {})),
  });
  if (r.status === 403) throw new Error("Signed out: open Hatchlybox again from its launcher.");
  const j = await r.json();
  if (j.task) return task(j.task, opts.onOut);
  return j;
}

// task: a long command's output while it runs; resolves with {code, out} when it ends.
async function task(id, onOut) {
  for (;;) {
    const r = await fetch("/api/task?id=" + encodeURIComponent(id), { headers: { "X-Hatchlybox": "1" } });
    const j = await r.json();
    if (onOut) onOut(j.out || "");
    if (j.done) return { code: j.code, out: j.out || "" };
    await sleep(1000);
  }
}

async function json(args, fallback) {
  try {
    const r = await call(args);
    return r.code === 0 ? JSON.parse(r.out) : fallback;
  } catch (e) { return fallback; }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const lastLine = (s) => (s || "").trim().split("\n").filter(Boolean).pop() || "";

// run: a command from a button: the button waits, failures are shown in words.
async function run(btn, args, opts = {}) {
  if (btn) btn.disabled = true;
  try {
    const r = await call(args, opts);
    // 75: this needs Android building, which this computer hasn't set up: offer it, then carry on.
    if (r.code === 75 && !opts.afterSetup) { if (btn) btn.disabled = false; return androidFirst(btn, args, opts); }
    if (r.code !== 0) toast(lastLine(r.out) || "That didn't work.");
    else if (opts.done) toast(typeof opts.done === "function" ? opts.done(r) : opts.done);
    return r;
  } catch (e) {
    toast(e.message);
    return { code: 1, out: e.message };
  } finally {
    if (btn) btn.disabled = false;
    pollJob(true);
    // What the action changed shows at once (installed, uninstalled, removed…), not only after leaving the page.
    if (!$("page-item").hidden || !$("page-library").hidden) loadLibrary();
  }
}

// androidFirst: Android's one-time setup, asked for when a step needs it; the step runs once it's ready.
async function androidFirst(btn, args, opts) {
  const yes = await ask({ title: "Android apps need a one-time setup", ok: "Set it up now",
    text: "This computer doesn't have Android's build tools yet: about 1 GB, 5 to 15 minutes. What you asked for starts as soon as they're ready." });
  if (!yes) return { code: 75, out: "" };
  toast("Setting up Android building: Settings › Ready to build shows its steps.");
  if (!(await setupAndroid())) return { code: 1, out: "" };
  return run(btn, args, Object.assign({}, opts, { afterSetup: true }));
}

// ask: a question in a dialog, with fields (a passphrase, a name) when given; null when cancelled, else true or
// the fields' values.
function ask({ title, text = "", ok = "OK", cancel = "Cancel", fields = [] }) {
  return new Promise((resolve) => {
    const d = $("ask-dialog");
    $("ask-title").textContent = title;
    $("ask-text").textContent = text;
    const inputs = fields.map((f) => el("input", { type: f.type || "text", placeholder: f.placeholder || "", "aria-label": f.placeholder || "",
      autocomplete: f.type === "password" ? "new-password" : "off", value: f.value || "" }));
    $("ask-fields").replaceChildren(...inputs);
    $("ask-ok").textContent = ok;
    $("ask-cancel").textContent = cancel;
    d.returnValue = "";
    d.addEventListener("close", () => resolve(d.returnValue !== "ok" ? null : fields.length ? inputs.map((i) => i.value) : true), { once: true });
    d.showModal();
    (inputs[0] || $("ask-ok")).focus();
  });
}

// passphrase: a new one, typed twice (at least 10 characters); null when cancelled.
async function passphrase(title, text) {
  for (;;) {
    const v = await ask({ title, text, ok: "Continue", fields: [{ type: "password", placeholder: "Passphrase (10 or more characters)" }, { type: "password", placeholder: "Again" }] });
    if (!v) return null;
    if (v[0].length < 10) { toast("Pick a passphrase of at least 10 characters."); continue; }
    if (v[0] !== v[1]) { toast("The two passphrases are different: type them again."); continue; }
    return v[0];
  }
}

// upload: a file the person picked, to a private place the engine can read; its path, or null.
async function upload(file) {
  if (!file) return null;
  const r = await fetch("/api/upload?name=" + encodeURIComponent(file.name), { method: "POST", headers: { "X-Hatchlybox": "1" }, body: file });
  const j = await r.json().catch(() => ({}));
  if (!j.path) { toast("Couldn't read that file" + (j.error ? ": " + j.error : ".")); return null; }
  return j.path;
}

let toastTimer;
function toast(text) {
  const t = $("toast");
  t.textContent = text; t.hidden = false;
  clearTimeout(toastTimer); toastTimer = setTimeout(() => (t.hidden = true), 5000);
}

function el(tag, attrs = {}, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") e.className = v;
    else if (k === "text") e.textContent = v;
    else if (k.startsWith("on")) e.addEventListener(k.slice(2), v);
    else if (v !== false && v != null) e.setAttribute(k, v === true ? "" : v);
  }
  for (const k of kids.flat()) if (k != null) e.append(k.nodeType ? k : document.createTextNode(k));
  return e;
}

// ---- pages ----

function show(page) {
  for (const s of document.querySelectorAll(".page")) s.hidden = s.id !== "page-" + page;
  for (const t of document.querySelectorAll(".tab")) {
    if (t.dataset.page === page || (page === "item" && t.dataset.page === "library")) t.setAttribute("aria-current", "page");
    else t.removeAttribute("aria-current");
  }
  if (page === "library") loadLibrary();
  if (page === "phone") loadPhone();
  if (page === "devices") { loadDevices(); beVisible(); lookNearby(); }
  else stopVisible();
  if (page === "settings") loadSettings();
  if (page === "tasks") loadTasks();
  if (page === "create") loadLibrary();
  window.scrollTo(0, 0);
}

// ---- create ----

function hereSystem() {
  const h = state.platform && state.platform.platform;
  return h === "macos" ? "macos" : h === "windows" ? "windows" : h === "linux" ? ((state.platform.installs || []).includes("omarchy") ? "omarchy" : "linux") : null;
}

// What can be made: the same as on the phone. This computer's own kind says so.
const KINDS = [["auto", "Auto"], ["web", "Web app"], ["android", "Android app"], ["game", "Game"], ["linux", "Linux app"],
  ["omarchy", "Omarchy app"], ["macos", "Mac app"], ["windows", "Windows app"], ["other", "Other…"]];

function fillKinds() {
  const here = hereSystem();
  $("kinds").replaceChildren(...KINDS.filter(([k]) => k !== "omarchy" || here === "omarchy").map(([k, label]) =>
    el("button", { class: "chip", role: "radio", "aria-checked": String(k === state.kind), "data-kind": k, onclick: () => setKind(k) },
      label + (k === here ? " · this computer" : ""))));
}

function setKind(kind) {
  state.kind = kind;
  for (const c of document.querySelectorAll(".kinds .chip")) c.setAttribute("aria-checked", String(c.dataset.kind === kind));
  $("kind-other").hidden = kind !== "other";
  if (kind === "other") $("kind-other").focus();
  routeHint();
}

let routeTimer;
function routeHint() {
  clearTimeout(routeTimer);
  const idea = $("idea").value.trim();
  if (state.kind !== "auto" || idea.length < 4) { $("route").textContent = ""; return; }
  routeTimer = setTimeout(async () => {
    const r = await json(["route", idea], null);
    if (r && $("idea").value.trim() === idea) {
      const name = r.system === "game" ? "a game (Godot)" : r.system === "other" ? "another system" : (SYSTEMS[r.system] || r.system) + (r.system === "web" ? " app" : " version");
      $("route").textContent = "Auto: " + name + ", because " + r.why + ".";
    }
  }, 350);
}

async function create() {
  const idea = $("idea").value.trim();
  if (!idea) { $("idea").focus(); return; }
  const agent = $("agent").value;
  if (!agent) { toast("Install an AI helper first (Settings)."); return; }
  let sys = state.kind;
  if (sys === "other") {
    const which = $("kind-other").value.trim();
    if (!which) { $("kind-other").focus(); return; }
    sys = "custom:" + which;
  }
  const r = await run($("create-btn"), ["create", sys, agent, idea]);
  if (r.code === 0) { $("idea").value = ""; $("route").textContent = ""; toast("Started: you can follow it above."); }
}

// ---- library ----

const COLORS = ["#0E8C7E", "#3E63DD", "#B6487F", "#C26A1B", "#6E56CF", "#2B8A3E", "#B54708", "#1570A6"];
function avatar(c, big) {
  const a = el("div", { class: "avatar" + (big ? " big" : "") });
  let h = 0; for (const ch of c.slug) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  a.style.background = COLORS[h % COLORS.length];
  if (c.icon) a.append(el("img", { src: "/icon/" + c.slug, alt: "" }));
  else a.textContent = (c.label || c.slug).trim().charAt(0).toUpperCase();
  return a;
}

function tone(word) {
  if (/installed|ready to open|live|with testers/.test(word)) return "ok";
  if (/fail|fix|crash|can't|stopped|didn't/.test(word)) return "bad";
  if (/update|ready|change|rebuild|finish|made|not finished/.test(word)) return "warn";
  return "";
}

function when(t) {
  if (!t) return "";
  const s = Date.now() / 1000 - t;
  if (s < 90) return "just now";
  if (s < 3600) return Math.round(s / 60) + " min ago";
  if (s < 86400) return Math.round(s / 3600) + " h ago";
  return new Date(t * 1000).toLocaleDateString();
}

function tile(c) {
  const systems = Object.entries(c.systems || {}).map(([k, v]) =>
    el("span", { class: "sys " + tone(v.word || ""), text: (SYSTEMS[k] || k) + " · " + (v.word || "") }));
  return el("button", { class: "tile", onclick: () => openItem(c.slug) },
    el("div", { class: "tile-top" }, avatar(c), el("div", {}, el("div", { class: "tile-name", text: c.label || c.slug }), el("div", { class: "tile-when", text: when(c.updated) }))),
    el("div", { class: "systems" }, systems));
}

async function loadLibrary() {
  const [creations, apps] = await Promise.all([json(["creations"], null), json(["list"], null)]);
  if (creations) state.creations = creations;
  if (apps) state.apps = apps;
  const q = $("search").value.trim().toLowerCase();
  const list = state.creations.filter((c) => !q || (c.label || c.slug).toLowerCase().includes(q) || (c.idea || "").toLowerCase().includes(q));
  $("grid").replaceChildren(...list.map(tile));
  $("empty").hidden = state.creations.length > 0;
  $("recent").replaceChildren(...state.creations.slice(0, 4).map(tile));
  if (state.item && !$("page-item").hidden) renderItem();
}

function openItem(slug) {
  state.item = slug;
  const def = state.settings.agent && state.agents.includes(state.settings.agent) ? state.settings.agent : state.agents[0];
  if (def) $("item-agent").value = def;
  for (const s of document.querySelectorAll(".page")) s.hidden = s.id !== "page-item";
  renderItem();
  window.scrollTo(0, 0);
}

// itemAgent: the AI helper picked on the creation's page (the default helper until another is picked).
function itemAgent() { return $("item-agent").value || state.settings.agent || state.agents[0] || "opencode"; }

// versionActions: the buttons for one version, from what it is and what the engine says can be done next.
function versionActions(c, sys, v) {
  const b = (label, fn, cls = "ghost small") => el("button", { class: cls, onclick: (e) => fn(e.currentTarget) }, label);
  const out = [];
  if (sys === "android") {
    const app = state.apps.find((a) => a.slug === c.slug) || {};
    const actions = (app.state && app.state.actions) || [];
    if (actions.includes("review")) {
      out.push(b("Keep the change", (x) => run(x, ["accept", c.slug], { done: "Kept." }), "primary small"));
      out.push(b("Undo it", (x) => run(x, ["discard", c.slug], { done: "Undone." })));
    }
    if (actions.includes("android-setup")) out.push(b("Build it for Android", async (x) => { if (await setupAndroid()) run(x, ["build", c.slug], { done: "Building it for Android." }); }, "primary small"));
    if (actions.includes("retry")) out.push(b("Try again", (x) => run(x, ["retry", c.slug, itemAgent()])));
    if (actions.includes("rebuild")) out.push(b("Rebuild", (x) => run(x, ["build", c.slug], { done: "Built." })));
    if (v.built) {
      // A computer sends it with a code to scan; it installs it directly only on a phone connected over wireless debugging.
      if (state.phone) out.push(b("Install on phone", (x) => run(x, ["install", c.slug], { done: "Installed on the phone." }), "primary small"));
      out.push(b("Send to phone", (x) => sendToPhone(x, c), state.phone ? "ghost small" : "primary small"));
      if (state.phone) out.push(b("Check it starts", (x) => run(x, ["verify", c.slug], { done: "It starts on the phone." })));
    }
    if (actions.includes("confirm")) out.push(b("It's installed", (x) => run(x, ["installed", c.slug], { done: "Marked as installed." }).then(loadLibrary)));
    if (app.state && app.state.detail) out.unshift(el("span", { class: "hint", text: app.state.detail }));
    return out;
  }
  const here = (state.platform.installs || []).includes(sys);
  if (sys === "web" && v.built) {
    out.push(el("a", { class: "primary small", href: "/web/" + c.slug + "/", target: "_blank", rel: "noopener", text: "Open" }));
    if (!c.systems.android) out.push(b("Put on phone", (x) => run(x, ["wrap", c.slug], { done: "It's an Android app now: install it from its Android version." })));
  }
  if (here && v.built) {
    if (!v.installed || v.update) out.push(b(v.update ? "Update" : "Install", (x) => run(x, ["here", "install", c.slug, sys], { done: "Installed." }), "primary small"));
    if (v.installed) {
      out.push(b("Open", (x) => run(x, ["here", "open", c.slug, sys])));
      out.push(b("Uninstall", (x) => run(x, ["here", "uninstall", c.slug, sys], { done: "Uninstalled." })));
    }
  }
  if (v.word === "not finished") out.push(b("Carry on", (x) => run(x, ["make", c.slug, sys, itemAgent()])));
  if (v.built || sys !== "web") out.push(b("Show folder", (x) => reveal(x, c.slug, sys)));
  out.push(b("Remove…", async (x) => {
    if (await ask({ title: `Remove the ${SYSTEMS[sys] || sys} version?`, ok: "Remove", text: (v.installed ? "It's uninstalled from this computer first. " : "") +
      "The creation's other versions stay. Hatchlybox keeps a copy in its trash folder." })) run(x, ["remove", c.slug, sys], { done: "Removed." });
  }, "ghost small danger"));
  return out;
}

function renderItem() {
  const c = state.creations.find((x) => x.slug === state.item);
  if (!c) { show("library"); return; }
  $("item-avatar").replaceWith(Object.assign(avatar(c, true), { id: "item-avatar" }));
  $("item-title").textContent = c.label || c.slug;
  $("item-idea").textContent = c.idea || "";
  const rows = Object.entries(c.systems || {}).map(([sys, v]) =>
    el("div", { class: "version" },
      el("div", { class: "version-name", text: (SYSTEMS[sys] || sys) + (sys === "android" && state.platform.platform !== "hatchlybox" ? " (your phone)" : "") }),
      el("div", { class: "version-word" }, v.word || "", v.older ? el("span", { class: "older", text: " · older than " + (SYSTEMS[v.older] || v.older) }) : null),
      el("div", { class: "version-actions" }, versionActions(c, sys, v))));
  $("versions").replaceChildren(...rows);
  const have = Object.keys(c.systems || {});
  const missing = ["web", "android", "linux", "omarchy", "macos", "windows"].filter((s) => !have.includes(s) && (s !== "omarchy" || hereSystem() === "omarchy"));
  $("make-system").replaceChildren(...missing.map((s) => el("option", { value: s, text: SYSTEMS[s] })), el("option", { value: "other", text: "Another system…" }));
  $("make-other").hidden = true;
  renderExtras(c);
  $("change-system").replaceChildren(...have.map((s) => el("option", { value: s, text: SYSTEMS[s] || s })));
  $("delete-zone").hidden = !have.includes("android");
}

// renderExtras: an Android version's code, publishing and backup, as on the phone.
async function renderExtras(c) {
  const box = $("item-extra");
  if (!c.systems || !c.systems.android) { box.replaceChildren(); return; }
  const app = state.apps.find((a) => a.slug === c.slug) || {};
  const b = (label, fn, cls = "ghost small") => el("button", { class: cls, onclick: (e) => fn(e.currentTarget) }, label);
  const gh = app.github || {};
  const github = el("div", { class: "card extra" }, el("h3", { text: "Code on GitHub" }));
  if (gh.repo) {
    github.append(el("p", { class: "hint" }, "Its code is at ", el("a", { href: "https://github.com/" + gh.repo, target: "_blank", rel: "noopener", text: gh.repo }),
      gh.visibility ? ` (${gh.visibility}).` : "."), el("div", { class: "row" },
      b(gh.visibility === "public" ? "Make it private" : "Make it public", (x) => setVisibility(x, c, gh.visibility === "public" ? "private" : "public")),
      b("Privacy check", (x) => run(x, ["github", "check", c.slug], { done: (r) => lastLine(r.out) }))));
    if (gh.blocked) github.append(el("p", { class: "hint", text: "Not sent to GitHub: " + gh.blocked }));
  } else {
    github.append(el("p", { class: "hint", text: "Keep its code on GitHub, private unless you say otherwise. Hatchlybox checks nothing private is in it first." }),
      el("div", { class: "row" }, b("Publish its code (private)", (x) => run(x, ["github", "publish", c.slug, "private"], { done: "On GitHub, private." }).then(loadLibrary), "primary small"),
        b("Privacy check", (x) => run(x, ["github", "check", c.slug], { done: (r) => lastLine(r.out) }))));
  }
  const play = el("div", { class: "card extra" }, el("h3", { text: "Google Play" }));
  const tracks = Object.keys((app.play && app.play.tracks) || {});
  play.append(el("p", { class: "hint", text: tracks.length ? `On Google Play: ${tracks.join(", ")}${app.play.vn ? ", version " + app.play.vn : ""}.`
    : "Prepare a release (store listing, graphics, a signed bundle), then upload it to a test track or production. Settings › Google Play connects your account first." }),
    el("div", { class: "row" },
      b("Prepare a release", (x) => run(x, ["play", "prepare", c.slug, itemAgent()], { done: "Preparing the release: you can follow it above." }), "primary small"),
      b("Upload…", (x) => playUpload(x, c)),
      b("Check on Google Play", (x) => run(x, ["play", "check", c.slug], { done: (r) => lastLine(r.out) })),
      b("Back up its upload key…", (x) => keyBackup(x, c))));
  const backup = el("div", { class: "card extra" }, el("h3", { text: "Backup" }),
    el("p", { class: "hint", text: "Its code, signing key and app files in one file, locked with a passphrase you choose." }),
    el("div", { class: "row" }, b("Back up…", (x) => backupApp(x, c))));
  box.replaceChildren(github, play, backup);
}

async function setVisibility(btn, c, to) {
  if (to === "public" && !(await ask({ title: "Make its code public?", ok: "Make it public",
    text: "Anyone can see it then. Hatchlybox checks again that nothing private is in it, and stops if something is." }))) return;
  run(btn, ["github", "visibility", c.slug, to], { done: to === "public" ? "Its code is public." : "Its code is private." }).then(loadLibrary);
}

async function playUpload(btn, c) {
  const v = await ask({ title: "Upload to Google Play", ok: "Upload",
    text: "Which track? internal (you and up to 100 testers), closed (a testers' group), or production (everyone).",
    fields: [{ placeholder: "internal, closed or production", value: "internal" }] });
  if (!v) return;
  const track = v[0].trim().toLowerCase();
  if (!["internal", "closed", "production"].includes(track)) { toast("The track is internal, closed or production."); return; }
  if (track === "production" && !(await ask({ title: "Release to everyone?", ok: "Release", text: "Production puts this version on Google Play for everyone." }))) return;
  run(btn, ["play", "upload", c.slug, track], { done: `Uploading to ${track}: you can follow it above.` });
}

async function keyBackup(btn, c) {
  const pass = await passphrase("Back up the upload key", "Google Play only accepts updates signed with this key: keep its backup and passphrase safe. The file goes to your browser's downloads.");
  if (!pass) return;
  const r = await run(btn, ["play", "backup", c.slug], { input: pass });
  // The encrypted key is offered to the browser for two minutes: this opens its download.
  const url = (r.out || "").match(/https?:\/\/\S+/);
  if (r.code === 0 && url) { window.open(url[0], "_blank", "noopener"); toast("Keep the downloaded file and the passphrase apart, both safe."); }
}

async function backupApp(btn, c) {
  const pass = await passphrase("Back up " + (c.label || c.slug), "The backup opens only with this passphrase: Hatchlybox doesn't keep it.");
  if (!pass) return;
  run(btn, ["backup", c.slug], { input: pass, done: (r) => lastLine(r.out).replace(/^Backup: /, "Backed up to ") });
}

// ---- tasks ----

async function loadTasks() {
  const list = await json(["history"], []);
  const what = { app: "Make", port: "Make", change: "Change", build: "Build", install: "Install", wrap: "Put on phone", "play-prepare": "Prepare release", "play-upload": "Upload to Google Play" };
  $("tasks").replaceChildren(...(list.length ? list.slice(0, 60).map((j) => {
    const c = state.creations.find((x) => x.slug === j.slug);
    return el("button", { class: "task" + (j.phase === "failed" ? " failed" : ""), onclick: () => showTaskLog(j) },
      el("span", { class: "task-what", text: `${what[j.kind] || j.kind}: ${c ? c.label : j.slug || ""}${j.arg ? " (" + (SYSTEMS[j.arg] || j.arg) + ")" : ""}` }),
      el("span", { class: "task-when", text: when(j.started) }),
      el("span", { class: "task-msg", text: j.msg || j.phase }));
  }) : [el("p", { class: "hint", text: "Nothing yet: what you make shows up here." })]));
}

async function showTaskLog(j) {
  const r = await fetch("/api/joblog?id=" + encodeURIComponent(j.id), { headers: { "X-Hatchlybox": "1" } });
  const l = $("task-log");
  l.textContent = ((await r.json()).log || "").trim() || "This task left no log.";
  l.hidden = false; l.scrollIntoView({ behavior: "smooth", block: "nearest" }); l.scrollTop = 1e9;
}

// ---- GitHub, Google Play, skills, backups (Settings) ----

async function loadGithub() {
  const box = $("github");
  const g = await json(["github", "status"], null);
  state.github = g;
  if (!g) { box.replaceChildren(el("p", { class: "hint", text: "Couldn't check GitHub. Open Settings again to retry." })); return; }
  if (g.state === "missing") {
    box.replaceChildren(el("p", { class: "hint", text: "GitHub's command-line tool (gh) isn't installed. Install it with your system's package manager (on Omarchy: sudo pacman -S github-cli), then open Settings again." }));
    return;
  }
  const rows = (g.accounts || []).map((a) => {
    const forNew = g.account === a.login, syncing = (g.allowed || []).includes(a.login);
    return el("div", { class: "line ok" }, el("span", { class: "grow" }, el("b", { text: a.login }), forNew ? " · new creations go here" : syncing ? " · keeps its creations in sync" : " · not used"),
      forNew ? null : el("button", { class: "ghost small", onclick: (e) => run(e.currentTarget, ["github", "use", a.login], { done: `New creations go to ${a.login}.` }).then(loadGithub) }, "Use for new creations"),
      syncing ? el("button", { class: "ghost small", onclick: (e) => run(e.currentTarget, ["github", "logout", a.login], { done: `${a.login} is no longer used.` }).then(loadGithub) }, "Stop using it")
        : el("button", { class: "ghost small", onclick: (e) => run(e.currentTarget, ["github", "resume", a.login], { done: `${a.login} syncs again.` }).then(loadGithub) }, "Sync again"),
      el("button", { class: "ghost small danger", onclick: async (e) => { if (await ask({ title: `Sign out of ${a.login}?`, ok: "Sign out", text: "This computer forgets that GitHub login. Its creations stay on GitHub." })) run(e.currentTarget, ["github", "signout", a.login], { done: "Signed out." }).then(loadGithub); } }, "Sign out"));
  });
  const auto = el("input", { type: "checkbox", class: "switch", id: "gh-auto" });
  auto.checked = g.auto === true;
  auto.addEventListener("change", () => run(null, ["github", "auto", auto.checked ? "on" : "off"], { done: auto.checked ? "New creations go to GitHub, private." : "New creations stay on this computer." }));
  box.replaceChildren(...(rows.length ? rows : [el("p", { class: "hint", text: "Not connected. Connect an account to keep your creations' code on GitHub (private unless you say otherwise)." })]),
    g.msg ? el("p", { class: "hint", text: g.msg }) : null,
    el("div", { class: "setting" }, el("label", { for: "gh-auto", text: "Put new creations on GitHub (private)" }), auto),
    el("div", { class: "row wrap" },
      el("button", { class: rows.length ? "ghost" : "primary", onclick: (e) => connectGithub(e.currentTarget) }, rows.length ? "Add another account" : "Connect GitHub"),
      rows.length ? el("button", { class: "ghost", onclick: (e) => run(e.currentTarget, ["github", "sync"], { done: "In sync with GitHub." }) }, "Sync now") : null));
}

async function connectGithub(btn) {
  const before = ((state.github && state.github.accounts) || []).length;
  const r = await run(btn, ["terminal", "github-add"]);
  if (r.code !== 0) return;
  toast("A terminal window opened: sign in to GitHub there (it opens your browser), then come back.");
  for (let i = 0; i < 60 && !$("page-settings").hidden; i++) {
    await sleep(5000);
    const g = await json(["github", "status"], null);
    if (g && (g.accounts || []).length > before) { toast("GitHub is connected."); loadGithub(); return; }
  }
}

async function loadPlay() {
  const box = $("play");
  const [p, keys] = await Promise.all([json(["play", "status"], null), call(["keys-state"]).catch(() => ({ out: "" }))]);
  const locked = lastLine(keys.out) === "locked";
  const b = (label, fn, cls = "ghost") => el("button", { class: cls, onclick: (e) => fn(e.currentTarget) }, label);
  const term = (what, words) => async (x) => { const r = await run(x, ["terminal", what]); if (r.code === 0) toast(words); };
  if (!p || p.state === "none") {
    const pick = el("input", { type: "file", accept: ".json,application/json", hidden: true });
    pick.addEventListener("change", async () => {
      const path = await upload(pick.files[0]);
      if (path) run(null, ["play", "key", path], { done: "Google Play is connected." }).then(loadPlay);
    });
    box.replaceChildren(el("p", { class: "hint", text: "Not connected. Google Play takes uploads from a service account: in Google Cloud, a project with the Google Play Android Developer API on, a service account and its JSON key, invited in Play Console with release rights." }),
      el("div", { class: "row wrap" }, locked ? b("Connect in a terminal", term("play-connect", "A terminal window opened: your keys are locked, so connecting asks for the passphrase there."), "primary")
        : el("label", { class: "primary file-pick" }, "Connect with the key file…", pick)));
    return;
  }
  box.replaceChildren(
    el("p", { class: "hint", text: p.state === "error" ? "Google Play didn't accept the key: " + (p.msg || "") : `Connected${p.email ? " as " + p.email : ""}.` + (locked ? " Your keys are locked with a passphrase." : "") }),
    el("div", { class: "row wrap" },
      locked ? b("Unlock (in a terminal)", term("unlock", "A terminal window opened: type the passphrase there.")) : b("Lock the keys with a passphrase", term("lock", "A terminal window opened: pick the passphrase there.")),
      b("Disconnect", async (x) => { if (await ask({ title: "Disconnect Google Play?", ok: "Disconnect", text: "This computer forgets the account's key. Your apps' upload keys stay." })) run(x, ["play", "disconnect"], { done: "Disconnected." }).then(loadPlay); })));
}

async function loadSkills() {
  const list = await json(["skills"], []);
  $("skills").replaceChildren(...list.map((k) => {
    const sw = el("input", { type: "checkbox", class: "switch", id: "skill-" + k.name, "aria-label": k.title || k.name });
    sw.checked = k.on !== false;
    sw.addEventListener("change", () => run(null, ["skill", k.name, sw.checked ? "on" : "off"], { done: `${k.title || k.name}: ${sw.checked ? "on" : "off"}.` }));
    return el("div", { class: "setting" }, el("label", { for: "skill-" + k.name }, el("b", { text: k.title || k.name }), k.blurb ? el("span", { class: "hint", text: " " + k.blurb }) : null), sw);
  }));
}

async function restoreBackup(file) {
  const path = await upload(file);
  if (!path) return;
  const v = await ask({ title: "Restore a backup", ok: "Restore", text: "It comes back as a new creation, under the name you give it.",
    fields: [{ placeholder: "Name for it (lowercase, like my-app)" }, { type: "password", placeholder: "The backup's passphrase" }] });
  if (!v) return;
  run(null, ["restore", v[0].trim(), path], { input: v[1], done: "Restored." }).then(loadLibrary);
}

async function sendToPhone(btn, c) {
  const r = await run(btn, ["download", c.slug]);
  if (r.code !== 0) return;
  const url = lastLine(r.out);
  qr(url, "Scan to install " + (c.label || c.slug));
}

// qrSvg: a QR code from rows of 1 (dark) and 0, with its quiet zone.
function qrSvg(rows) {
  const n = rows.length, q = 4, ns = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(ns, "svg");
  svg.setAttribute("viewBox", `0 0 ${n + 2 * q} ${n + 2 * q}`);
  svg.setAttribute("shape-rendering", "crispEdges");
  svg.setAttribute("role", "img"); svg.setAttribute("aria-label", "QR code");
  let d = "";
  rows.forEach((row, y) => { for (let x = 0; x < row.length; x++) if (row[x] === "1") d += `M${x + q} ${y + q}h1v1h-1z`; });
  const p = document.createElementNS(ns, "path"); p.setAttribute("d", d); p.setAttribute("fill", "#101828"); svg.append(p);
  return svg;
}

async function qr(text, title) {
  const r = await call(["qr", text]);
  const rows = (r.out || "").trim().split("\n").filter((l) => /^[01]+$/.test(l));
  if (!rows.length) { toast("Open on the phone: " + text); return; }
  const n = rows.length, q = 4, ns = "http://www.w3.org/2000/svg";
  const svg = document.createElementNS(ns, "svg");
  svg.setAttribute("viewBox", `0 0 ${n + 2 * q} ${n + 2 * q}`);
  svg.setAttribute("shape-rendering", "crispEdges");
  let d = "";
  rows.forEach((row, y) => { for (let x = 0; x < row.length; x++) if (row[x] === "1") d += `M${x + q} ${y + q}h1v1h-1z`; });
  const p = document.createElementNS(ns, "path"); p.setAttribute("d", d); p.setAttribute("fill", "#101828"); svg.append(p);
  $("qr").replaceChildren(svg);
  $("qr-title").textContent = title;
  $("qr-link").textContent = text; $("qr-link").href = text;
  $("qr-dialog").showModal();
}

async function reveal(btn, slug, sys) {
  btn.disabled = true;
  try {
    const r = await fetch(`/api/reveal?slug=${encodeURIComponent(slug)}&system=${encodeURIComponent(sys)}`, { headers: { "X-Hatchlybox": "1" } });
    const j = await r.json();
    toast(j.path ? "Opened " + j.path : "It has no folder yet.");
  } finally { btn.disabled = false; }
}

// ---- the current job ----

let jobTimer;
async function pollJob(soon) {
  clearTimeout(jobTimer);
  if (soon) await sleep(600);
  try {
    const r = await fetch("/api/job?lines=60", { headers: { "X-Hatchlybox": "1" } });
    if (r.ok) renderJob(await r.json());
  } catch (e) { /* the server restarts: try again */ }
  const active = state.job && ACTIVE.includes(state.job.phase);
  jobTimer = setTimeout(() => pollJob(false), active ? 2000 : 8000);
}

function renderJob({ job, log }) {
  const was = state.job;
  state.job = job;
  const box = $("job");
  if (!job || !job.phase) { box.hidden = true; return; }
  const active = ACTIVE.includes(job.phase);
  const recent = Date.now() / 1000 - (job.updated || 0) < 600;
  box.hidden = !(active || (recent && job.id !== state.jobDismissed));
  const c = state.creations.find((x) => x.slug === job.slug);
  const name = c ? c.label : job.slug || "";
  const what = { app: "Making", port: "Making", change: "Changing", build: "Building", install: "Installing", wrap: "Wrapping" }[job.kind] || "Working on";
  $("job-title").textContent = active ? `${what} ${name}` : `${name}: ${job.phase === "failed" ? "didn't finish" : job.phase}`;
  $("job-msg").textContent = job.msg || "";
  $("job-spin").classList.toggle("still", !active);
  box.classList.toggle("failed", job.phase === "failed");
  box.classList.toggle("done", !active && job.phase !== "failed");
  $("job-cancel").hidden = !active;
  $("job-dismiss").hidden = active;
  if (!$("job-log").hidden) { $("job-log").textContent = log; $("job-log").scrollTop = 1e9; }
  // When a job ends, the library shows what it made.
  if (was && ACTIVE.includes(was.phase) && !active) loadLibrary();
}

// ---- phone ----

async function loadPhone() {
  $("adb-state").textContent = "Checking…";
  const r = await call(["adb"]).catch(() => ({ out: "" }));
  const s = lastLine(r.out);
  const ok = s.startsWith("connected");
  $("adb-dot").className = "dot " + (ok ? "ok" : "bad");
  $("adb-state").textContent = ok ? "Connected: " + s.slice(10) : "No phone connected. Android versions can still be sent with a code to scan.";
}

function outTo(pre) {
  pre.hidden = false;
  return (o) => { pre.textContent = o; pre.scrollTop = 1e9; };
}

// ---- devices ----

async function loadDevices() {
  const list = await json(["sync", "devices"], []);
  state.paired = list;
  $("devices-list").replaceChildren(...(list.length ? list.map((d) =>
    el("div", { class: "line ok" }, el("span", { class: "grow" }, el("b", { text: d.name || d.id }), " · ", d.last ? "synced " + when(d.last) : "not synced yet"),
      el("button", { class: "ghost small danger", onclick: async (e) => { if (await ask({ title: `Unpair ${d.name || "this device"}?`, ok: "Unpair", text: "They stop syncing. What each has stays." })) run(e.currentTarget, ["sync", "forget", d.id], { done: "Unpaired." }).then(loadDevices); } }, "Unpair")))
    : [el("p", { class: "hint", text: "None yet: pair with a nearby device, or with a code." })]));
}

// ---- pairing: nearby (no code), or with a code; the engine's events, one JSON line each ----

// follow: a long command started as a task; each JSON line it prints goes to onEvent as it arrives.
async function follow(args, onEvent) {
  const r = await fetch("/api/run", { method: "POST", headers: { "Content-Type": "application/json", "X-Hatchlybox": "1" }, body: JSON.stringify({ args, bg: true }) });
  const j = await r.json().catch(() => ({}));
  if (!j.task) { onEvent({ state: "failed", msg: "Couldn't start it." }); return null; }
  const t = { id: j.task, seen: 0, done: false };
  (async () => {
    while (!t.done) {
      const q = await fetch("/api/task?id=" + encodeURIComponent(t.id), { headers: { "X-Hatchlybox": "1" } }).then((x) => x.json()).catch(() => null);
      if (!q) { await sleep(1000); continue; }
      const lines = (q.out || "").split("\n");
      for (; t.seen < lines.length - (q.done ? 0 : 1); t.seen++) {
        const l = lines[t.seen].trim();
        if (l.startsWith("{")) { try { onEvent(JSON.parse(l)); } catch (e) { /* not an event */ } }
      }
      if (q.done) { t.done = true; onEvent({ state: "ended", code: q.code }); break; }
      await sleep(700);
    }
  })();
  return t;
}
const say = (t, answer) => t && fetch(`/api/say?id=${encodeURIComponent(t.id)}&answer=${answer}`, { method: "POST", headers: { "X-Hatchlybox": "1" } });

// pairingBox: the progress box at the top of Devices (null text: hidden).
function pairingBox(text, busy = true) {
  $("pairing").hidden = text == null;
  $("pairing-text").textContent = text || "";
  $("pairing-spin").classList.toggle("still", !busy);
  if (text == null) $("code-box").hidden = true;
}
const STEPS = { connected: (e) => `Connected to ${e.device}.`, packing: () => "Getting ready to sync…", merging: () => "Putting the library together…",
  sending: (e) => `Sending: ${Math.round(100 * e.bytes / Math.max(1, e.total))}%`, receiving: (e) => `Receiving: ${Math.round(100 * e.bytes / Math.max(1, e.total))}%`,
  finding: () => "Looking for the device showing that code…", asking: (e) => `Waiting for ${e.device} to accept…` };

// pairingEvent: what every pairing has in common: the steps, the six digits, the end.
async function pairingEvent(t, e, after) {
  if (STEPS[e.state]) pairingBox(STEPS[e.state](e));
  else if (e.state === "confirm") {
    $("code-box").hidden = true;
    pairingBox(`Check the six digits with ${e.device}.`);
    const yes = await askDigits(e.sas, e.device);
    say(t, yes ? "yes" : "no");
    pairingBox(yes ? `Waiting for ${e.device} to confirm…` : "Not paired.", yes);
  } else if (e.state === "done") {
    const got = (e.result && (e.result.added || []).length) || 0;
    pairingBox(`Paired with ${e.device} and synced${got ? `: ${got} new here` : ""}.`, false);
    toast(`Paired with ${e.device}.`); loadDevices(); loadLibrary();
  } else if (e.state === "failed") pairingBox(e.msg || "It didn't work.", false);
  else if (e.state === "ended") { $("pairing-cancel").hidden = true; if (after) after(e); }
}

function askDigits(sas, device) {
  return ask({ title: "Do the numbers match?", ok: "They match", cancel: "They don't",
    text: `${device} shows six digits too. Pair only if they're exactly these: ${sas.slice(0, 3)} ${sas.slice(3)}` });
}

// beVisible: while Devices is open, nearby devices can ask to pair with this one; its person says yes first.
function beVisible() {
  if (state.visible) return;
  state.visible = follow(["sync", "visible"], async (e) => {
    const t = await state.visible;
    if (e.state === "asked") {
      const yes = await ask({ title: `${e.device} wants to pair`, ok: "Pair", cancel: "Not now",
        text: `Pair this computer with ${e.device}? Its library and this one's will be shared between the two.` });
      say(t, yes ? "yes" : "no");
      if (yes) { $("pairing-cancel").hidden = true; pairingBox(`Pairing with ${e.device}…`); }
    } else if (e.state === "visible") $("near-hint").textContent = `While this page is open, this computer is visible as "${e.name}" to Hatchlybox on your other devices (same Wi-Fi). Open sync there too (on a phone: Library › Sync): they show up here.`;
    else pairingEvent(t, e, (end) => {
      state.visible = null;
      // Visible again after a pairing, unless another window already is.
      if (!$("page-devices").hidden && !/another window/.test($("pairing-text").textContent)) setTimeout(beVisible, 1500);
    });
  });
}
async function stopVisible() { const t = await state.visible; state.visible = null; if (t) say(t, "stop"); }

// lookNearby: the visible devices on this Wi-Fi, while Devices is open.
async function lookNearby() {
  if (state.looking) return;
  state.looking = true;
  try {
    while (!$("page-devices").hidden) {
      const list = await json(["sync", "nearby"], []);
      const paired = (state.paired || []).map((d) => d.id);
      $("nearby").replaceChildren(...(list.length ? list.map((d) => el("div", { class: "line ok" },
        el("span", { class: "grow" }, el("b", { text: d.name }), paired.includes(d.id) ? " · paired" : ""),
        paired.includes(d.id) ? null : el("button", { class: "primary small", onclick: () => pairNearby(d) }, "Pair")))
        : [el("p", { class: "hint", text: "Looking for nearby devices… (open Devices on the other one)" })]));
      await sleep(4000);
    }
  } finally { state.looking = false; }
}

async function pairNearby(d) {
  $("pairing-cancel").hidden = false;
  pairingBox(`Asking ${d.name}…`);
  const t = await (state.pairing = follow(["sync", "ask", d.at, "--peer", d.name], async (e) => pairingEvent(await state.pairing, e)));
}

async function showCode() {
  $("pairing-cancel").hidden = false;
  pairingBox("Making a code…");
  state.pairing = follow(["sync", "send"], async (e) => {
    const t = await state.pairing;
    if (e.state === "waiting") {
      pairingBox("Waiting for the other device…");
      $("code-words").textContent = e.code.replace(/-/g, " ");
      $("code-qr").replaceChildren(qrSvg(e.qr || []));
      $("code-box").hidden = false;
    } else pairingEvent(t, e);
  });
}

async function useCode() {
  const code = $("sync-code").value.trim();
  if (!code) { $("sync-code").focus(); return; }
  $("pairing-cancel").hidden = false;
  pairingBox("Looking for the device showing that code…");
  state.pairing = follow(["sync", "receive", code], async (e) => pairingEvent(await state.pairing, e));
}

// ---- settings ----

async function loadSettings() {
  const [settings, missing, setup, iso, renderer, version] = await Promise.all([
    json(["settings"], {}), checkReady(), json(["setup-state"], null), call(["isolation"]).catch(() => ({ out: "" })),
    call(["renderer"]).catch(() => ({ out: "" })), call(["version"]).catch(() => ({ out: "" })),
  ]);
  state.settings = settings || {};
  if (!state.settingUp) renderSetup(setup);
  if (setup && setup.state === "running") watchSetup();
  $("doctor").replaceChildren(...(missing.length ? missing.map((l) => el("div", { class: "line bad", text: l.slice(8) }))
    : [el("div", { class: "line ok", text: "Everything is ready." })]));
  const sandbox = missing.find((l) => l.startsWith("missing sandbox: "));
  renderRenderer(lastLine(renderer.out));
  const i = lastLine(iso.out);
  $("isolation").textContent = { isolated: "in a sandbox", compatible: "without a sandbox", blocked: "blocked: no sandbox works here" }[i] || i;
  $("set-isolation").checked = (state.settings.agentIsolation || (state.platform.platform === "hatchlybox" ? "compatible" : "required")) === "required";
  $("isolation-hint").textContent = sandbox ? sandbox.slice("missing sandbox: ".length) : i === "isolated" ? "Each AI helper sees only the creation it works on: not your files, keys or other creations." : "";
  fillAgents();
  loadHelpers();
  loadGithub();
  loadPlay();
  loadSkills();
  $("set-fallback").checked = state.settings.fallback !== "off";
  $("set-fixRounds").value = state.settings.fixRounds ?? 3;
  $("set-agentTimeout").value = state.settings.agentTimeout ?? 45;
  $("about-version").textContent = "Engine " + lastLine(version.out);
  $("about-platform").textContent = state.platform.name;
}

// renderRenderer: the game renderer (hatchlybox renderer): ready, or what it is and the command that adds it. Hatchlybox
// never runs sudo: a computer's packages are for the user to install.
function renderRenderer(r) {
  const hint = $("renderer-hint");
  $("renderer").textContent = r === "renderer ready" ? "ready" : "not set up";
  if (r === "renderer ready") { hint.replaceChildren(); return; }
  if (r.startsWith("sudo ")) {
    const copy = el("button", { class: "ghost small", onclick: () => navigator.clipboard.writeText(r).then(() => toast("Copied: paste it in a terminal.")) }, "Copy");
    hint.replaceChildren("AI helpers take screenshots of a game to check how it looks. That needs a few system packages, which only you can install. " +
      "Run this in a terminal (it asks for your password), then open Settings again:", el("div", { class: "row" }, el("code", { text: r }), copy));
  } else hint.replaceChildren("AI helpers take screenshots of a game to check how it looks: " + (r === "not installed" ? "install Godot first." : r));
}

// ---- AI helpers ----

// loadHelpers: each AI helper (hatchlybox agents status): installed, signed in, a Sign in button and its models.
async function loadHelpers() {
  const list = await json(["agents", "status"], null);
  if (!list) { $("helpers").replaceChildren(el("p", { class: "hint", text: "Couldn't check the AI helpers. Open Settings again to retry." })); return null; }
  $("helpers").replaceChildren(...list.map(helperRow));
  return list;
}

function helperRow(h) {
  const ok = h.installed && h.signedIn !== false;
  let words;
  if (!h.installed) words = "Not installed on this computer. Install it, then open Settings again.";
  else if (h.signedIn === true) words = "Signed in.";
  else if (h.signedIn === null) words = "Installed. Hatchlybox can't tell whether it's signed in: if a creation says it isn't, sign in.";
  else if (h.id === "opencode") words = "Not signed in: its free models work without an account. Sign in to use others.";
  else words = "Not signed in: sign in before it can make anything.";
  const row = el("div", { class: "helper" },
    el("div", { class: "helper-name" }, el("span", { class: "dot " + (ok ? "ok" : "bad") }), h.name),
    el("div", { class: "helper-state", text: words }));
  if (h.installed) {
    row.append(el("button", { class: h.signedIn === false ? "primary small" : "ghost small", onclick: (e) => signIn(e.currentTarget, h) },
      h.signedIn === true ? "Sign in again" : "Sign in"));
    // Only what the helper offers: its default, its models, and a model chosen earlier that it no longer lists.
    const sel = el("select", { "aria-label": h.name + " model" }, el("option", { value: "", text: "Its default" }),
      h.models.map((m) => el("option", { value: m.id, text: m.name === m.id ? m.id : `${m.name} (${m.id})` })));
    if (h.model && !h.models.some((m) => m.id === h.model)) sel.append(el("option", { value: h.model, text: h.model + " (chosen earlier)" }));
    sel.value = h.model || "";
    sel.addEventListener("change", () => setting(h.id + "Model", sel.value, sel.value ? `${h.name} uses ${sel.value}.` : `${h.name} uses its default model.`));
    row.append(el("label", { class: "helper-model" }, "Model", sel,
      h.models.length ? null : el("span", { class: "hint", text: h.signedIn ? "It lists no models: it uses its default." : "Its models show up once it's signed in." })));
  }
  return row;
}

// signIn: the helper's own login, in a terminal window; Settings shows it signed in once that ends.
async function signIn(btn, h) {
  const r = await run(btn, ["agents", "login", h.id]);
  if (r.code !== 0) return;
  toast(`A terminal window opened: sign in to ${h.name} there, then come back.`);
  if (h.signedIn === true) return;
  for (let i = 0; i < 100 && !$("page-settings").hidden; i++) {
    await sleep(3000);
    const list = await json(["agents", "status"], null);
    const now = list && list.find((x) => x.id === h.id);
    if (now && now.signedIn === true && h.signedIn !== true) { toast(`Signed in to ${h.name}.`); loadHelpers(); return; }
  }
  loadHelpers();
}

// ---- ready to build ----

// checkReady: what's missing to build (hatchlybox doctor), shown in the banner on every page; returns its lines.
async function checkReady() {
  const doctor = await call(["doctor"]).catch(() => ({ out: "" }));
  const missing = (doctor.out || "").split("\n").filter((l) => l.startsWith("missing "));
  const busy = "missing Android building: being set up now ";
  const b = $("banner");
  if (!missing.length) { b.hidden = true; return missing; }
  const link = el("a", { href: "#", onclick: (e) => { e.preventDefault(); show("settings"); } }, "Settings › Ready to build");
  if (missing.length === 1 && missing[0].startsWith(busy)) {
    b.replaceChildren(el("b", { text: "Getting ready. " }), "Android building is being set up " + missing[0].slice(busy.length) + ". You can follow it in ", link, ".");
  } else {
    b.replaceChildren(el("b", { text: "Not ready to build yet. " }), missing.length + " thing" + (missing.length > 1 ? "s" : "") + " to set up: ", link);
  }
  b.hidden = false;
  return missing;
}

// renderSetup: Android building's own setup (setup.json): its step while it runs, here or started by the installer;
// what failed, in words, with the setup log's last lines.
function renderSetup(s) {
  const box = $("setup-status"), running = !!s && s.state === "running";
  const failed = !!s && (s.state === "failed" || s.state === "stopped");
  $("setup-btn").disabled = running;
  box.hidden = !(running || failed);
  box.classList.toggle("failed", failed);
  $("setup-spin").hidden = !running;
  $("setup-progress").hidden = !running;
  $("setup-log").hidden = !failed || !(s.log || []).length;
  if (running) {
    $("setup-text").textContent = s.step ? `Setting up Android building: step ${s.step} of ${s.steps}, ${s.msg}.` : "Setting up Android building: starting…";
    $("setup-progress").max = s.steps || 1;
    $("setup-progress").value = Math.max(0, (s.step || 1) - 1);
  } else if (failed) {
    $("setup-text").textContent = s.state === "stopped"
      ? "The last setup stopped before it finished (the computer restarted, or it was closed). Set up Android building tries again."
      : `Setting up Android building didn't finish: ${s.msg}. The setup log's last lines below say why; Set up Android building tries again.`;
    $("setup-log").textContent = (s.log || []).join("\n");
    $("setup-log").scrollTop = 1e9;
  }
}

// watchSetup: follows a setup this page didn't start (the installer's) until it ends.
let setupWatched = false;
async function watchSetup() {
  if (setupWatched || state.settingUp) return;
  setupWatched = true;
  try {
    for (;;) {
      await sleep(2000);
      const s = await json(["setup-state"], null);
      if (!s || state.settingUp) break;
      renderSetup(s);
      if (s.state !== "running") {
        toast(s.state === "done" ? "Android building is ready." : "Setting up Android building didn't finish: Settings says why.");
        if ($("page-settings").hidden) checkReady(); else loadSettings();
        break;
      }
    }
  } finally { setupWatched = false; }
}

// setupAndroid: the button. A setup already running is followed instead; this one's steps show while it runs.
async function setupAndroid() {
  const now = await json(["setup-state"], null);
  if (now && now.ready) return true;
  if (now && now.state === "running") {
    renderSetup(now); watchSetup();
    for (;;) { await sleep(3000); const s = await json(["setup-state"], null); if (!s || s.state !== "running") return !!(s && s.ready); }
  }
  // Google's SDK licence: the person reads and accepts it here first (Hatchlybox never accepts it for them).
  if ((await call(["license", "check", "android-sdk"]).catch(() => ({ code: 1 }))).code !== 0) {
    if (!await ask({ title: "Google's Android SDK licence", ok: "Accept and set up", cancel: "Not now",
      text: "Android building downloads Google's Android SDK (about 300 MB). To use it, you accept Google's Android Software " +
        "Development Kit License Agreement: https://developer.android.com/studio/terms" })) return false;
    await call(["license", "accept", "android-sdk"]);
  }
  state.settingUp = true;
  renderSetup({ state: "running", step: 0 });
  let done = false;
  const r = call(["setup"]).catch((e) => ({ code: 1, out: e.message })).finally(() => { done = true; });
  while (!done) {
    await sleep(1500);
    const s = await json(["setup-state"], null);
    if (!done && s && s.state === "running") renderSetup(s);
  }
  const res = await r;
  state.settingUp = false;
  const s = await json(["setup-state"], null);
  if (res.code === 0) toast("Android building is ready.");
  else if (s && s.state === "failed") toast(`Setting up Android building didn't finish: ${s.msg}. Settings shows why.`);
  else toast(lastLine(res.out) || "Setting up Android building didn't finish: try again.");
  if (!$("page-settings").hidden) loadSettings(); else checkReady();
  return res.code === 0;
}

function fillAgents() {
  const names = { claude: "Claude", codex: "Codex", opencode: "OpenCode (free models)" };
  const opts = () => state.agents.map((a) => el("option", { value: a, text: names[a] || a }));
  for (const id of ["agent", "set-agent", "item-agent"]) {
    const s = $(id), keep = s.value;
    s.replaceChildren(...opts());
    s.value = state.agents.includes(keep) ? keep : state.agents.includes(state.settings.agent) ? state.settings.agent : state.agents[0] || "";
  }
  $("create-hint").textContent = state.agents.length ? "" : "No AI helper is installed yet: install Claude Code, Codex or OpenCode, then come back.";
}

async function setting(key, value, label) {
  const r = await call(["set", key, String(value)]);
  toast(r.code === 0 ? label || "Saved." : lastLine(r.out));
  state.settings[key] = value;
}

// ---- start ----

async function start() {
  state.platform = await json(["platform"], { platform: "linux", name: "Hatchlybox", installs: [] });
  $("platform-name").textContent = state.platform.name;
  fillKinds();
  state.settings = await json(["settings"], {});
  const agents = await call(["agents"]).catch(() => ({ out: "" }));
  state.agents = (agents.out || "").trim().split(/\s+/).filter(Boolean);
  fillAgents();
  const missing = await checkReady();
  if (missing.some((l) => l.startsWith("missing Android building: being set up now"))) watchSetup();
  // Icons an app is missing (its file gone, or drawn before) are drawn again, then the library shows them.
  call(["icons"]).then(loadLibrary).catch(() => {});
  loadLibrary();
  pollJob(false);
  phoneState();
}

// phoneState: whether a phone is connected over wireless debugging (Install on phone needs one).
async function phoneState() {
  const r = await call(["adb"]).catch(() => ({ out: "" }));
  state.phone = lastLine(r.out).startsWith("connected");
}

function wire() {
  for (const t of document.querySelectorAll(".tab")) t.addEventListener("click", () => show(t.dataset.page));
  for (const b of document.querySelectorAll("[data-goto]")) b.addEventListener("click", () => show(b.dataset.goto));
  for (const c of document.querySelectorAll(".kinds .chip")) c.addEventListener("click", () => setKind(c.dataset.kind));
  $("idea").addEventListener("input", routeHint);
  $("idea").addEventListener("keydown", (e) => { if (e.key === "Enter" && (e.ctrlKey || e.metaKey)) create(); });
  $("create-btn").addEventListener("click", create);
  $("search").addEventListener("input", loadLibrary);
  $("job-log-btn").addEventListener("click", () => { const l = $("job-log"); l.hidden = !l.hidden; $("job-log-btn").textContent = l.hidden ? "Show log" : "Hide log"; pollJob(false); });
  $("job-cancel").addEventListener("click", (e) => run(e.currentTarget, ["cancel"], { done: "Stopped." }));
  $("job-dismiss").addEventListener("click", () => { state.jobDismissed = state.job && state.job.id; $("job").hidden = true; });
  $("make-system").addEventListener("change", () => { $("make-other").hidden = $("make-system").value !== "other"; if (!$("make-other").hidden) $("make-other").focus(); });
  $("make-btn").addEventListener("click", (e) => {
    let sys = $("make-system").value;
    if (sys === "other") { const w = $("make-other").value.trim(); if (!w) { $("make-other").focus(); return; } sys = "custom:" + w; }
    run(e.currentTarget, ["make", state.item, sys, itemAgent()], { done: "Started." });
  });
  $("backups-folder").addEventListener("click", async () => {
    const r = await fetch("/api/reveal?backups=1", { headers: { "X-Hatchlybox": "1" } });
    const j = await r.json().catch(() => ({}));
    toast(j.path ? "Opened " + j.path : "Couldn't open the backups folder.");
  });
  $("restore-file").addEventListener("change", (e) => { restoreBackup(e.target.files[0]); e.target.value = ""; });
  $("change-btn").addEventListener("click", (e) => {
    const text = $("change-text").value.trim(), sys = $("change-system").value, agent = itemAgent();
    if (!text) { $("change-text").focus(); return; }
    run(e.currentTarget, sys === "android" ? ["change", state.item, agent, text] : ["make", state.item, sys, agent, text], { done: "Started." })
      .then((r) => { if (r.code === 0) $("change-text").value = ""; });
  });
  $("delete-btn").addEventListener("click", (e) => {
    if (confirm("Delete the Android project and its app file? Versions for other systems stay.")) run(e.currentTarget, ["delete", state.item], { done: "Deleted." }).then(() => show("library"));
  });
  $("adb-refresh").addEventListener("click", loadPhone);
  $("pair-btn").addEventListener("click", (e) => run(e.currentTarget, ["pair", $("pair-addr").value.trim(), $("pair-code").value.trim()], { onOut: outTo($("phone-out")), done: "Paired: now connect." }));
  $("conn-btn").addEventListener("click", (e) => run(e.currentTarget, ["connect", $("conn-addr").value.trim()], { onOut: outTo($("phone-out")), done: "Connected." }).then(loadPhone));
  $("sync-send").addEventListener("click", showCode);
  $("pairing-cancel").addEventListener("click", async () => { const t = await state.pairing; if (t) say(t, "stop"); pairingBox("Stopped.", false); });
  $("sync-recv").addEventListener("click", useCode);
  $("setup-btn").addEventListener("click", setupAndroid);
  $("godot-btn").addEventListener("click", (e) => run(e.currentTarget, ["godot"], { onOut: outTo($("setup-out")),
    done: (r) => /^optional: /m.test(r.out) ? "Godot is ready. Game screenshots are optional: Settings says how to add them." : "Godot is ready." }).then(loadSettings));
  $("set-agent").addEventListener("change", (e) => setting("agent", e.target.value).then(fillAgents));
  $("set-fallback").addEventListener("change", (e) => setting("fallback", e.target.checked ? "on" : "off"));
  $("set-isolation").addEventListener("change", (e) => setting("agentIsolation", e.target.checked ? "required" : "compatible").then(loadSettings));
  $("set-fixRounds").addEventListener("change", (e) => setting("fixRounds", e.target.value));
  $("set-agentTimeout").addEventListener("change", (e) => setting("agentTimeout", e.target.value));
}

wire();
start().catch((e) => toast(e.message));
