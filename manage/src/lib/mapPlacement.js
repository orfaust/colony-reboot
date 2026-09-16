// Convert viewport pointer coordinates to the same centered world space as the map.
export function placementPosition(clientX, clientY, rect, view, snap) {
  const align = (n) => {
    const value = snap > 0 ? Math.round(n / snap) * snap : n;
    return Math.round(value * 1000) / 1000;
  };
  return {
    x: align(view.cx + (clientX - rect.left - rect.width / 2) / view.scale),
    y: align(view.cy + (clientY - rect.top - rect.height / 2) / view.scale),
  };
}
