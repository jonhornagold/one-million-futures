// One Million Futures: prototype front end.
(function () {
  "use strict";

  var data = window.OMF_DATA || { stories: [] };
  var stories = data.stories.slice().sort(function (a, b) { return b.date.localeCompare(a.date); });

  var TYPES = [
    { key: "all", label: "All" },
    { key: "news", label: "News" },
    { key: "official", label: "Official" },
    { key: "linkedin", label: "LinkedIn" }
  ];
  var TYPE_LABEL = { news: "News", official: "Official", linkedin: "LinkedIn" };
  var MILESTONES = { "2025-11": "Launch", "2026-05": "Interim report" };

  var state = { type: "all", theme: null, q: "" };

  // ---------- helpers ----------
  function esc(s) {
    return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
    });
  }
  function parseDate(d) { var p = d.split("-"); return new Date(+p[0], +p[1] - 1, +p[2]); }
  function fmtDate(d) { return parseDate(d).toLocaleDateString("en-GB", { day: "numeric", month: "short", year: "numeric" }); }
  function monthKey(d) { return d.slice(0, 7); }
  function fmtMonth(k) { var p = k.split("-"); return new Date(+p[0], +p[1] - 1, 1).toLocaleDateString("en-GB", { month: "long", year: "numeric" }); }
  function $(id) { return document.getElementById(id); }

  // ---------- status ----------
  (function status() {
    if (data.lastUpdated) {
      var d = new Date(data.lastUpdated);
      $("last-updated").textContent = "Updated " + d.toLocaleDateString("en-GB", { day: "numeric", month: "short" }) +
        ", " + d.toLocaleTimeString("en-GB", { hour: "2-digit", minute: "2-digit" });
    }
    var fr = data.review && data.review.finalReport;
    if (fr && fr.status === "published" && fr.url) {
      $("status-text").innerHTML = '<strong>The final report is out.</strong> <a href="' + esc(fr.url) + '" target="_blank" rel="noopener">Read it →</a>';
    } else if (fr && fr.expected) {
      $("status-text").innerHTML = '<strong>Awaiting the final report</strong> · expected ' + esc(fr.expected);
      var tl = $("tl-final-date"); if (tl) tl.textContent = fr.expected + " (expected)";
    }
  })();

  // ---------- hero ----------
  var PERSON = '<svg viewBox="0 0 22 30" aria-hidden="true"><circle cx="11" cy="6" r="5" fill="currentColor"/><path d="M2 29v-9a9 9 0 0 1 18 0v9z" fill="currentColor"/></svg>';
  Array.prototype.forEach.call(document.querySelectorAll(".people"), function (el) {
    var of = +el.dataset.of, on = +el.dataset.on, html = "";
    for (var i = 0; i < of; i++) html += PERSON;
    el.innerHTML = html;
    var svgs = el.querySelectorAll("svg");
    setTimeout(function () { for (var j = 0; j < on; j++) svgs[j].classList.add("on"); }, 400);
  });

  (function countUp() {
    var el = $("count-up"), target = +el.dataset.target;
    if (window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    var start = null, dur = 1400;
    function step(t) {
      if (!start) start = t;
      var p = Math.min((t - start) / dur, 1), eased = 1 - Math.pow(1 - p, 3);
      el.textContent = Math.round(target * eased).toLocaleString("en-GB");
      if (p < 1) requestAnimationFrame(step);
    }
    requestAnimationFrame(step);
  })();

  // ---------- featured ----------
  (function featured() {
    var f = stories.filter(function (s) { return s.featured; })[0] ||
            stories.filter(function (s) { return s.summary; })[0] || stories[0];
    if (!f) return;
    $("featured").innerHTML =
      '<article class="feature"><div>' +
        '<div class="meta"><span class="badge badge--' + esc(f.type) + '">' + esc(TYPE_LABEL[f.type]) + '</span>' +
        '<span>' + esc(f.outlet) + '</span><span>·</span><time datetime="' + esc(f.date) + '">' + fmtDate(f.date) + '</time></div>' +
        '<h3>' + esc(f.title) + '</h3><p>' + esc(f.summary) + '</p>' +
        '<a class="btn" href="' + esc(f.url) + '" target="_blank" rel="noopener">Read the full article <span aria-hidden="true">→</span></a>' +
      '</div></article>';
  })();

  // ---------- filters ----------
  function renderChips() {
    $("type-filters").innerHTML = TYPES.map(function (t) {
      var n = t.key === "all" ? stories.length : stories.filter(function (s) { return s.type === t.key; }).length;
      if (n === 0) return "";   // e.g. hide LinkedIn until the first post is added
      return '<button type="button" class="chip" data-type="' + t.key + '" aria-pressed="' + (state.type === t.key) + '">' +
        esc(t.label) + ' <span aria-hidden="true">· ' + n + '</span></button>';
    }).join("");

    var themes = {};
    stories.forEach(function (s) { (s.themes || []).forEach(function (t) { themes[t] = (themes[t] || 0) + 1; }); });
    $("theme-filters").innerHTML = Object.keys(themes).sort().map(function (t) {
      return '<button type="button" class="chip" data-theme="' + esc(t) + '" aria-pressed="' + (state.theme === t) + '">#' + esc(t) + '</button>';
    }).join("");
  }

  $("type-filters").addEventListener("click", function (e) {
    var b = e.target.closest("[data-type]"); if (!b) return;
    state.type = b.dataset.type; update();
  });
  $("theme-filters").addEventListener("click", function (e) {
    var b = e.target.closest("[data-theme]"); if (!b) return;
    state.theme = state.theme === b.dataset.theme ? null : b.dataset.theme; update();
  });
  $("search").addEventListener("input", function (e) { state.q = e.target.value.trim().toLowerCase(); update(); });
  $("reset").addEventListener("click", function () { state = { type: "all", theme: null, q: "" }; $("search").value = ""; update(); });

  // ---------- feed ----------
  function card(s) {
    var tags = (s.themes || []).map(function (t) { return '<span class="tag">#' + esc(t) + '</span>'; }).join("");
    var by = s.author ? '<span>by ' + esc(s.author) + '</span>' : "";
    var cta = s.type === "linkedin" ? "View on LinkedIn" : "Read full article";
    return '<article class="card' + (s.summary ? "" : " card--brief") + '">' +
      '<div class="meta"><span class="badge badge--' + esc(s.type) + '">' + esc(TYPE_LABEL[s.type]) + '</span>' +
      '<span class="outlet">' + esc(s.outlet) + '</span>' + by + '<span>·</span><time datetime="' + esc(s.date) + '">' + fmtDate(s.date) + '</time></div>' +
      '<h3>' + esc(s.title) + '</h3>' + (s.summary ? '<p>' + esc(s.summary) + '</p>' : "") +
      (tags ? '<div class="tags">' + tags + '</div>' : "") +
      '<a class="read" href="' + esc(s.url) + '" target="_blank" rel="noopener">' + cta + ' <span aria-hidden="true">→</span>' +
      '<span class="visually-hidden"> (opens ' + esc(s.outlet) + ' in a new tab)</span></a>' +
    '</article>';
  }

  function filtered() {
    return stories.filter(function (s) {
      if (state.type !== "all" && s.type !== state.type) return false;
      if (state.theme && (s.themes || []).indexOf(state.theme) === -1) return false;
      if (state.q) {
        var hay = (s.title + " " + s.summary + " " + s.outlet).toLowerCase();
        if (hay.indexOf(state.q) === -1) return false;
      }
      return true;
    });
  }

  var PAGE = 24, shown = PAGE;

  function update(keepPage) {
    if (!keepPage) shown = PAGE;
    renderChips();
    var all = filtered(), list = all.slice(0, shown), groups = {}, order = [];
    list.forEach(function (s) {
      var k = monthKey(s.date);
      if (!groups[k]) { groups[k] = []; order.push(k); }
      groups[k].push(s);
    });
    $("feed-list").innerHTML = order.map(function (k) {
      return '<div class="group"><h3 class="group__title">' + fmtMonth(k) + '</h3><div class="cards">' +
        groups[k].map(card).join("") + '</div></div>';
    }).join("");
    $("empty").hidden = all.length > 0;
    $("more").hidden = all.length <= shown;
    $("more").textContent = "Show more stories (" + (all.length - shown) + " more)";
    $("feed-count").textContent = all.length + " of " + stories.length + " stories";
  }
  $("more").addEventListener("click", function () { shown += PAGE; update(true); });

  // ---------- chart ----------
  (function chart() {
    if (!stories.length) return;
    var first = stories[stories.length - 1].date.slice(0, 7);
    var end = data.lastUpdated ? data.lastUpdated.slice(0, 7) : stories[0].date.slice(0, 7);
    var months = [], y = +first.slice(0, 4), m = +first.slice(5, 7);
    while (true) {
      var k = y + "-" + String(m).padStart(2, "0");
      months.push(k);
      if (k >= end) break;
      m++; if (m > 12) { m = 1; y++; }
    }
    var counts = months.map(function (k) { return stories.filter(function (s) { return monthKey(s.date) === k; }).length; });
    var max = Math.max.apply(null, counts) || 1;

    var W = 760, H = 240, pad = { t: 34, r: 8, b: 28, l: 8 };
    var bw = (W - pad.l - pad.r) / months.length, ih = H - pad.t - pad.b;
    var svg = '<svg viewBox="0 0 ' + W + ' ' + H + '" role="img" aria-label="Bar chart of stories per month">';
    months.forEach(function (k, i) {
      var c = counts[i], h = c ? Math.max(4, (c / max) * ih) : 2;
      var x = pad.l + i * bw + bw * 0.18, w = bw * 0.64, yb = pad.t + ih - h;
      var peak = c === max;
      svg += '<rect class="bar' + (peak ? " peak" : "") + '" x="' + x + '" y="' + yb + '" width="' + w + '" height="' + h + '" rx="4"><title>' +
        fmtMonth(k) + ': ' + c + ' stories</title></rect>';
      if (c) svg += '<text class="val" x="' + (x + w / 2) + '" y="' + (yb - 6) + '" text-anchor="middle">' + c + '</text>';
      if (MILESTONES[k] && c) svg += '<text class="note" x="' + (x + w / 2) + '" y="' + (yb - 20) + '" text-anchor="middle">' + MILESTONES[k] + '</text>';
      var p = k.split("-");
      var lbl = new Date(+p[0], +p[1] - 1, 1).toLocaleDateString("en-GB", { month: "short" });
      svg += '<text class="axis" x="' + (x + w / 2) + '" y="' + (H - 8) + '" text-anchor="middle">' + lbl + '</text>';
    });
    svg += "</svg>";
    $("chart").innerHTML = svg;
  })();

  update();
})();
