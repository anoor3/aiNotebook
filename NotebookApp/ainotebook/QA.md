# Manual QA and Performance Checklist

Use this checklist to validate the custom drawing stack after major changes.

## Functional matrix
- Stylus vs. finger input:
  - Draw with Apple Pencil at normal zoom, verify pressure-based width changes.
  - Draw with finger, confirm input is ignored or handled per policy.
- Zoomed drawing:
  - Zoom to 2–3x, draw strokes, then pan; ensure ink stays aligned and crisp.
- Eraser fidelity:
  - Toggle eraser, scrub over strokes, verify overlay highlights and final erase.
  - Undo/redo after erasing to confirm reversibility.
- Undo/redo stress:
  - Draw 30–50 strokes, spam undo/redo to ensure state matches expectations.
- Persistence and migration:
  - Open notebooks with legacy `.drawing` files, confirm they render and rewrite to new format.
  - Kill and relaunch; drawings should persist.
- Autosave timing:
  - Draw, wait ~1s idle, kill app; relaunch to confirm strokes saved.

## Profiling passes (Instruments)
- **Core Animation / FPS**: Verify steady 120 Hz while drawing long strokes on iPad Pro.
- **Time Profiler**: Capture 30–60s drawing session; watch `StrokeRenderer.render` and `CustomInkView.update` for hot spots.
- **Memory Leaks**: Run a 5–10 minute drawing test, ensure no retain cycles in canvas/renderer.

## Regression checks
- Page navigation and indicators still track the active page after drawing.
- Tool/palette updates propagate across pages (color, width, eraser).
- Zoom reset after pinch below 1.0 behaves as before.
