// Defer Google Analytics until the user interacts, the browser is idle, or a
// 5s fallback timer fires. This removes ~97ms of main-thread work (and a
// 43ms forced reflow) from the critical LCP path while still capturing
// analytics for bounce visits via the timer fallback.
(function () {
  var meta = document.querySelector('meta[name="ga-id"]');
  if (!meta) return;
  var id = meta.getAttribute("content");
  if (!id) return;

  var loaded = false;

  function loadGA() {
    if (loaded) return;
    loaded = true;

    window.dataLayer = window.dataLayer || [];
    function gtag() { window.dataLayer.push(arguments); }
    window.gtag = window.gtag || gtag;
    window.gtag("js", new Date());
    window.gtag("config", id);

    var s = document.createElement("script");
    s.async = true;
    s.src = "https://www.googletagmanager.com/gtag/js?id=" + encodeURIComponent(id);
    document.head.appendChild(s);
  }

  function scheduleLoad() {
    cleanup();
    if ("requestIdleCallback" in window) {
      window.requestIdleCallback(loadGA, { timeout: 3000 });
    } else {
      setTimeout(loadGA, 1500);
    }
  }

  var events = ["pointerdown", "keydown", "scroll", "touchstart"];
  function cleanup() {
    events.forEach(function (e) {
      window.removeEventListener(e, scheduleLoad);
    });
  }
  events.forEach(function (e) {
    window.addEventListener(e, scheduleLoad, { passive: true, once: true });
  });

  // Fallback so analytics fires even for zero-interaction bounce visits.
  setTimeout(scheduleLoad, 5000);
})();
