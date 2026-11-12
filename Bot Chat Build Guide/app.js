(function () {
  var KEY = "botchat-guide-done";
  var done = {};
  try { done = JSON.parse(localStorage.getItem(KEY) || "{}") || {}; } catch (e) { done = {}; }

  function save() {
    try { localStorage.setItem(KEY, JSON.stringify(done)); } catch (e) { /* no storage: progress lasts for this visit */ }
  }

  function render() {
    var ticks = document.querySelectorAll("[data-tick]");
    var seen = {}, total = 0, n = 0;
    ticks.forEach(function (t) {
      var id = t.getAttribute("data-tick");
      t.parentNode.classList.toggle("is-done", !!done[id]);
      if (!seen[id]) { seen[id] = true; total++; if (done[id]) n++; }
    });
    document.querySelectorAll(".prog-text").forEach(function (el) { el.textContent = n + " / " + total + " steps"; });
    document.querySelectorAll(".prog-bar").forEach(function (el) { el.style.width = (total ? 100 * n / total : 0) + "%"; });
    document.querySelectorAll("input[data-step]").forEach(function (b) {
      b.checked = !!done[b.getAttribute("data-step")];
      b.closest(".mark").classList.toggle("is-done", b.checked);
    });
    document.querySelectorAll("[data-card]").forEach(function (c) {
      c.classList.toggle("is-done", !!done[c.getAttribute("data-card")]);
    });
  }

  document.querySelectorAll("input[data-step]").forEach(function (b) {
    b.addEventListener("change", function () {
      done[b.getAttribute("data-step")] = b.checked;
      save(); render();
    });
  });
  render();

  // Code blocks: language tag + copy button
  document.querySelectorAll("div.hl").forEach(function (block) {
    var m = block.className.match(/language-([\w-]+)/);
    if (m && m[1] !== "text" && !block.classList.contains("has-file")) {
      var tag = document.createElement("span");
      tag.className = "lang"; tag.textContent = m[1];
      block.appendChild(tag);
    }
    var btn = document.createElement("button");
    btn.type = "button"; btn.className = "copy"; btn.textContent = "Copy";
    btn.addEventListener("click", function () {
      var text = block.querySelector("pre").innerText;
      if (!navigator.clipboard) { btn.textContent = "Select and copy"; return; }
      navigator.clipboard.writeText(text).then(function () {
        btn.textContent = "Copied";
        setTimeout(function () { btn.textContent = "Copy"; }, 1400);
      }, function () { btn.textContent = "Select and copy"; });
    });
    block.appendChild(btn);
  });

  // On-this-page highlight
  var tocLinks = Array.prototype.slice.call(document.querySelectorAll(".onpage a"));
  if (tocLinks.length && "IntersectionObserver" in window) {
    var map = {};
    tocLinks.forEach(function (a) { map[a.getAttribute("href").slice(1)] = a; });
    var obs = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting && map[en.target.id]) {
          tocLinks.forEach(function (a) { a.classList.remove("active"); });
          map[en.target.id].classList.add("active");
        }
      });
    }, { rootMargin: "-15% 0px -75% 0px" });
    document.querySelectorAll("article h2[id]").forEach(function (h) { obs.observe(h); });
  }
})();
