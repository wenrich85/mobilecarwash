(function () {
  var meta = document.querySelector('meta[name="ga-id"]');
  if (!meta) return;
  var id = meta.getAttribute("content");
  if (!id) return;
  window.dataLayer = window.dataLayer || [];
  function gtag() { window.dataLayer.push(arguments); }
  window.gtag = window.gtag || gtag;
  window.gtag("js", new Date());
  window.gtag("config", id);
})();
