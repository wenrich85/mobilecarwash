// Animates the hero price number when data-cents changes.
export const PriceCountUp = {
  mounted() { this.current = this.target(); this.paint(this.current); },
  updated() { this.animate(this.current ?? this.target(), this.target()); },
  target() { return parseInt(this.el.dataset.cents || "0", 10); },
  paint(c) { this.el.textContent = "$" + (c / 100).toFixed(2); },
  animate(from, to) {
    const start = performance.now(), dur = 320;
    const tick = (now) => {
      const t = Math.min((now - start) / dur, 1);
      const v = Math.round(from + (to - from) * t);
      this.paint(v);
      if (t < 1) requestAnimationFrame(tick);
      else this.current = to;
    };
    requestAnimationFrame(tick);
  },
};
