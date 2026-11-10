/* Page behaviour: sticky bar that leaves the dark stage, a theme switch that
   survives reloads, and quiet reveals. No framework, no dependencies. */
(function () {
  "use strict";

  var root = document.documentElement;
  var bar = document.querySelector("[data-bar]");
  var hero = document.querySelector(".hero");

  /* ── Bar: solid once the hero is behind us ─────────────────────────────── */
  function updateBar() {
    if (!bar) return;
    var limit = hero ? hero.offsetHeight - 90 : 40;
    bar.classList.toggle("solid", window.scrollY > limit);
  }
  updateBar();
  window.addEventListener("scroll", updateBar, { passive: true });
  window.addEventListener("resize", updateBar);

  /* ── Theme ────────────────────────────────────────────────────────────── */
  var buttons = [].slice.call(document.querySelectorAll("[data-theme-set]"));

  function applyTheme(choice) {
    if (choice === "light" || choice === "dark") {
      root.setAttribute("data-theme", choice);
    } else {
      root.removeAttribute("data-theme");
    }
    buttons.forEach(function (b) {
      b.setAttribute("aria-checked", String(b.getAttribute("data-theme-set") === choice));
    });
  }

  var saved = "auto";
  try { saved = localStorage.getItem("foamwin-theme") || "auto"; } catch (e) {}
  applyTheme(saved);

  buttons.forEach(function (b) {
    b.addEventListener("click", function () {
      var choice = b.getAttribute("data-theme-set");
      applyTheme(choice);
      try { localStorage.setItem("foamwin-theme", choice); } catch (e) {}
    });
  });

  /* ── Reveal on scroll ─────────────────────────────────────────────────── */
  var targets = [
    ".plate h2", ".plate .intro-wide", ".drop", ".margin", ".stat",
    ".pull", ".step", ".shell", ".asset", ".card", ".checks li",
    ".disclaimer", ".limits p", ".bridge h2", ".bridge-copy", ".bridge-link",
    ".foot-cols > div"
  ];

  var nodes = [];
  targets.forEach(function (sel) {
    [].slice.call(document.querySelectorAll(sel)).forEach(function (el) {
      el.classList.add("reveal");
      nodes.push(el);
    });
  });

  if (!("IntersectionObserver" in window)) {
    nodes.forEach(function (n) { n.classList.add("in"); });
    return;
  }

  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (entry) {
      if (!entry.isIntersecting) return;
      var el = entry.target;
      var siblings = el.parentNode ? [].slice.call(el.parentNode.children) : [];
      var index = siblings.indexOf(el);
      var delay = Math.min(Math.max(index, 0), 6) * 55;
      el.style.transitionDelay = delay + "ms";
      el.classList.add("in");
      io.unobserve(el);
    });
  }, { rootMargin: "0px 0px -8% 0px", threshold: 0.08 });

  nodes.forEach(function (n) { io.observe(n); });

  /* ── Outbound click bookkeeping (no cookies, nothing third-party) ──────── */
  document.addEventListener("click", function (e) {
    var link = e.target.closest ? e.target.closest("[data-track]") : null;
    if (!link) return;
    var label = link.getAttribute("data-track");
    if (window.console && console.debug) console.debug("[foamwin] " + label);
  });
})();
