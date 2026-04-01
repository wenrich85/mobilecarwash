/**
 * DiagramScroll Hook
 * Auto-pans the viewport to center the bucket diagram when animations trigger
 */
export const DiagramScroll = {
  mounted() {
    // Save reference to container for easy access
    this.container = this.el;

    // Listen for changes to animating_flows via updated hook
    this.handleAnimationStart = this.handleAnimationStart.bind(this);
  },

  updated() {
    // Check if animating_flows has changed and contains active flows
    const animatingFlows = this.el.getAttribute('data-animating-flows');

    // If there are animating flows, scroll to center the diagram
    if (animatingFlows && animatingFlows !== '[]') {
      this.scrollToDiagram();
    }
  },

  scrollToDiagram() {
    // Smooth scroll the diagram into view with a centered position
    const containerRect = this.container.getBoundingClientRect();
    const pageHeight = window.innerHeight;

    // Calculate scroll position to center diagram in viewport
    const scrollPosition = window.pageYOffset + containerRect.top - (pageHeight / 3);

    // Smooth scroll with easing
    window.scrollTo({
      top: Math.max(0, scrollPosition),
      behavior: 'smooth',
      duration: 300
    });
  }
};
