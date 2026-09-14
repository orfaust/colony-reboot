import { useEffect, useMemo, useRef, useState } from 'react';
import { Checkbox, Field, NumberInput, RefSelect, TextInput } from './fields.jsx';
import { GAME_WINDOW, WORLD_SCALE } from '../lib/game.js';
import { contrastText, isPlainObject, moveItem, objectItems, rgbToHex } from '../lib/object.js';

// The game maps world origin to the viewport centre, X right / Y down.
const round = (n) => Math.round(n * 1000) / 1000;

function useSize(ref) {
  const [size, setSize] = useState({ width: 800, height: 500 });
  useEffect(() => {
    const observer = new ResizeObserver(([entry]) => setSize({ width: entry.contentRect.width, height: entry.contentRect.height }));
    observer.observe(ref.current);
    return () => observer.disconnect();
  }, [ref]);
  return size;
}

function nextId(code, instances) {
  const taken = new Set(instances.map((b) => b?.id));
  for (let i = 1; ; i++) if (!taken.has(`${code}${i}`)) return `${code}${i}`;
}

function MapCanvas({ instances, types, texts, selected, onSelect, onMove, snap, showGrid }) {
  const wrapRef = useRef(null);
  const svgRef = useRef(null);
  const { width, height } = useSize(wrapRef);
  const [view, setView] = useState({ cx: 0, cy: 0, scale: WORLD_SCALE });
  const drag = useRef(null);

  const toScreen = (x, y) => [width / 2 + (x - view.cx) * view.scale, height / 2 + (y - view.cy) * view.scale];

  // Wheel must be non-passive to prevent page scroll while zooming around the cursor.
  useEffect(() => {
    const svg = svgRef.current;
    const onWheel = (e) => {
      e.preventDefault();
      const rect = svg.getBoundingClientRect();
      const mx = e.clientX - rect.left - rect.width / 2;
      const my = e.clientY - rect.top - rect.height / 2;
      setView((v) => {
        const scale = Math.min(400, Math.max(8, v.scale * (e.deltaY < 0 ? 1.15 : 1 / 1.15)));
        const wx = v.cx + mx / v.scale;
        const wy = v.cy + my / v.scale;
        return { scale, cx: wx - mx / scale, cy: wy - my / scale };
      });
    };
    svg.addEventListener('wheel', onWheel, { passive: false });
    return () => svg.removeEventListener('wheel', onWheel);
  }, []);

  const onPointerDown = (e, index) => {
    try {
      svgRef.current.setPointerCapture(e.pointerId);
    } catch {
      // Capture is best-effort; dragging still works while the pointer stays over the map.
    }
    if (index === undefined) {
      drag.current = { mode: 'pan', sx: e.clientX, sy: e.clientY, cx: view.cx, cy: view.cy };
      onSelect(null);
    } else {
      const p = instances[index].position ?? { x: 0, y: 0 };
      drag.current = { mode: 'move', index, sx: e.clientX, sy: e.clientY, x: p.x, y: p.y, key: `drag-${index}-${Date.now()}` };
      onSelect(index);
    }
    e.stopPropagation();
  };

  const onPointerMove = (e) => {
    const d = drag.current;
    if (!d) return;
    const dx = (e.clientX - d.sx) / view.scale;
    const dy = (e.clientY - d.sy) / view.scale;
    if (d.mode === 'pan') setView((v) => ({ ...v, cx: d.cx - dx, cy: d.cy - dy }));
    else {
      const snapTo = (n) => (snap > 0 ? Math.round(n / snap) * snap : n);
      onMove(d.index, { x: round(snapTo(d.x + dx)), y: round(snapTo(d.y + dy)) }, d.key);
    }
  };

  const endDrag = () => (drag.current = null);

  // Grid lines in world units, adapted to zoom so they never get too dense.
  const gridStep = view.scale >= 32 ? 1 : view.scale >= 12 ? 5 : 10;
  const gridLines = [];
  if (showGrid) {
    const x0 = Math.floor((view.cx - width / 2 / view.scale) / gridStep) * gridStep;
    const x1 = view.cx + width / 2 / view.scale;
    const y0 = Math.floor((view.cy - height / 2 / view.scale) / gridStep) * gridStep;
    const y1 = view.cy + height / 2 / view.scale;
    for (let x = x0; x <= x1; x += gridStep) {
      const [sx] = toScreen(x, 0);
      gridLines.push(<line key={`x${x}`} x1={sx} x2={sx} y1={0} y2={height} className={x === 0 ? 'axis' : 'grid'} />);
    }
    for (let y = y0; y <= y1; y += gridStep) {
      const [, sy] = toScreen(0, y);
      gridLines.push(<line key={`y${y}`} x1={0} x2={width} y1={sy} y2={sy} className={y === 0 ? 'axis' : 'grid'} />);
    }
  }

  // Reference frame: the default game window centred on the world origin.
  const [wx0, wy0] = toScreen(-GAME_WINDOW.width / 2 / WORLD_SCALE, -GAME_WINDOW.height / 2 / WORLD_SCALE);
  const fontSize = Math.max(9, Math.min(16, view.scale / 5));

  return (
    <div className="map-wrap" ref={wrapRef}>
      <svg
        ref={svgRef}
        width={width}
        height={height}
        className="map"
        onPointerDown={(e) => onPointerDown(e)}
        onPointerMove={onPointerMove}
        onPointerUp={endDrag}
        onPointerCancel={endDrag}
      >
        {gridLines}
        <rect
          x={wx0}
          y={wy0}
          width={(GAME_WINDOW.width / WORLD_SCALE) * view.scale}
          height={(GAME_WINDOW.height / WORLD_SCALE) * view.scale}
          className="window-frame"
        />
        <text x={wx0 + 4} y={wy0 - 4} className="window-label">
          {GAME_WINDOW.width}×{GAME_WINDOW.height} window
        </text>
        {instances.map((b, index) => {
          if (!isPlainObject(b)) return null;
          const type = types.get(b.building_id);
          const w = (type?.width > 0 ? type.width : 1) * view.scale;
          const h = (type?.height > 0 ? type.height : 1) * view.scale;
          const [sx, sy] = toScreen(b.position?.x ?? 0, b.position?.y ?? 0);
          const color = type?.color ?? { r: 255, g: 0, b: 255 };
          const isSelected = selected === index;
          return (
            <g key={index} className={`building${isSelected ? ' selected' : ''}${type ? '' : ' unknown'}`} onPointerDown={(e) => onPointerDown(e, index)}>
              <rect x={sx - w / 2} y={sy - h / 2} width={w} height={h} fill={rgbToHex(color)} opacity={0.35 + 0.65 * (b.health ?? 1)} />
              {isSelected && <rect x={sx - w / 2 - 3} y={sy - h / 2 - 3} width={w + 6} height={h + 6} className="selection" />}
              <text x={sx} y={sy} className="building-code" fill={contrastText(color)} fontSize={fontSize}>
                {b.id}
              </text>
              <text x={sx} y={sy + h / 2 + fontSize + 2} className="building-name" fontSize={fontSize}>
                {type ? (texts?.[type.name_key] ?? type.id) : `? ${b.building_id}`}
              </text>
              {b.repairing && (
                <text x={sx + w / 2 - 4} y={sy - h / 2 + fontSize + 2} className="repair-flag" fontSize={fontSize}>
                  🔧
                </text>
              )}
            </g>
          );
        })}
      </svg>
      <div className="map-hud">
        <span>zoom {Math.round((view.scale / WORLD_SCALE) * 100)}%</span>
        <button type="button" className="btn tiny" onClick={() => setView({ cx: 0, cy: 0, scale: WORLD_SCALE })}>
          Reset view
        </button>
      </div>
    </div>
  );
}

export default function LevelEditor({ data, onChange, ctx }) {
  const instances = Array.isArray(data.buildings) ? data.buildings : [];
  const types = useMemo(() => new Map(objectItems(ctx.buildings).map((t) => [t.id, t])), [ctx.buildings]);
  const typeOptions = [...types.values()].map((t) => ({ value: t.id, label: `${ctx.texts?.[t.name_key] ?? t.id} (${t.id})` }));
  const [selected, setSelected] = useState(null);
  const [snap, setSnap] = useState(0.5);
  const [showGrid, setShowGrid] = useState(true);
  const [newType, setNewType] = useState('');

  const current = selected !== null && selected < instances.length ? selected : null;
  const setInstances = (next, historyKey) => onChange({ ...data, buildings: next }, historyKey);
  const updateInstance = (index, patch, historyKey) =>
    setInstances(
      instances.map((b, i) => (i === index ? { ...b, ...patch } : b)),
      historyKey,
    );

  const addInstance = (typeId) => {
    const type = types.get(typeId);
    if (!type) return;
    const instance = { id: nextId(type.code, instances), building_id: typeId, position: { x: 0, y: 0 }, health: 1, repairing: false };
    setInstances([...instances, instance]);
    setSelected(instances.length);
  };
  const removeInstance = (index) => {
    setInstances(instances.filter((_, i) => i !== index));
    setSelected(null);
  };
  const duplicateInstance = (index) => {
    const source = instances[index];
    const type = types.get(source.building_id);
    const copy = {
      ...structuredClone(source),
      id: nextId(type?.code ?? source.id, instances),
      position: { x: (source.position?.x ?? 0) + (snap || 1), y: source.position?.y ?? 0 },
    };
    setInstances([...instances.slice(0, index + 1), copy, ...instances.slice(index + 1)]);
    setSelected(index + 1);
  };

  // Keyboard: Delete removes, arrows nudge by the snap step (ignored while typing in a field).
  useEffect(() => {
    const onKey = (e) => {
      if (current === null || e.target.closest('input, textarea, select')) return;
      const step = snap || 0.1;
      const moves = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] };
      if (e.key === 'Delete') removeInstance(current);
      else if (moves[e.key]) {
        e.preventDefault();
        const p = instances[current].position ?? { x: 0, y: 0 };
        updateInstance(current, { position: { x: round(p.x + moves[e.key][0]), y: round(p.y + moves[e.key][1]) } }, `nudge-${current}`);
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  });

  const b = current !== null ? instances[current] : null;
  const idDuplicate = b && instances.some((other, i) => i !== current && other?.id === b.id);

  return (
    <div className="level-editor">
      <div className="toolbar">
        <Field label="Version">
          <NumberInput integer value={data.version} onChange={(v) => onChange({ ...data, version: v }, 'version')} />
        </Field>
        <Field label="Level">
          <NumberInput integer value={data.level} onChange={(v) => onChange({ ...data, level: v }, 'level')} />
        </Field>
        <Field label="Snap">
          <select className="input" value={snap} onChange={(e) => setSnap(Number(e.target.value))}>
            <option value={0}>Off</option>
            <option value={0.1}>0.1</option>
            <option value={0.25}>0.25</option>
            <option value={0.5}>0.5</option>
            <option value={1}>1</option>
          </select>
        </Field>
        <Checkbox checked={showGrid} onChange={setShowGrid} label="Grid" />
        <div className="toolbar-spacer" />
        <Field label="Add building">
          <div className="inline">
            <RefSelect value={newType} options={typeOptions} onChange={setNewType} placeholder="— building type —" />
            <button type="button" className="btn primary" disabled={!types.has(newType)} onClick={() => addInstance(newType)}>
              + Place at origin
            </button>
          </div>
        </Field>
      </div>

      <div className="level-body">
        <MapCanvas
          instances={instances}
          types={types}
          texts={ctx.texts}
          selected={current}
          onSelect={setSelected}
          snap={snap}
          showGrid={showGrid}
          onMove={(index, position, key) => updateInstance(index, { position }, key)}
        />

        <aside className="panel inspector">
          {b && isPlainObject(b) ? (
            <>
              <div className="detail-header">
                <div>
                  <span className="eyebrow">Instance #{current} · draw order</span>
                  <h2>{b.id}</h2>
                </div>
              </div>
              <Field label="ID" error={idDuplicate ? 'Duplicate ID' : !b.id?.trim() ? 'Required' : null}>
                <TextInput value={b.id} onChange={(v) => updateInstance(current, { id: v }, `id-${current}`)} spellCheck={false} />
              </Field>
              <Field label="Building type (building_id)">
                <RefSelect value={b.building_id} options={typeOptions} onChange={(v) => updateInstance(current, { building_id: v })} />
              </Field>
              <div className="form-grid">
                <Field label="X" hint="World units, right">
                  <NumberInput
                    value={b.position?.x}
                    step={snap || 0.1}
                    onChange={(v) => updateInstance(current, { position: { ...b.position, x: v } }, `x-${current}`)}
                  />
                </Field>
                <Field label="Y" hint="World units, down">
                  <NumberInput
                    value={b.position?.y}
                    step={snap || 0.1}
                    onChange={(v) => updateInstance(current, { position: { ...b.position, y: v } }, `y-${current}`)}
                  />
                </Field>
              </div>
              <Field label={`Health · ${Math.round((b.health ?? 0) * 100)}%`} error={!(b.health >= 0 && b.health <= 1) ? 'Must be in [0,1]' : null}>
                <div className="inline">
                  <input
                    type="range"
                    min={0}
                    max={1}
                    step={0.01}
                    value={b.health ?? 0}
                    onChange={(e) => updateInstance(current, { health: Number(e.target.value) }, `health-${current}`)}
                  />
                  <NumberInput value={b.health} min={0} max={1} step={0.05} onChange={(v) => updateInstance(current, { health: v }, `health-${current}`)} />
                </div>
              </Field>
              <Checkbox checked={b.repairing} onChange={(v) => updateInstance(current, { repairing: v })} label="Repairing" />
              <div className="btn-row">
                <button type="button" className="btn" onClick={() => duplicateInstance(current)}>
                  Duplicate
                </button>
                <button type="button" className="btn danger" onClick={() => removeInstance(current)}>
                  Delete
                </button>
              </div>
              <p className="hint">Drag on the map to move · arrows nudge · Del removes</p>
            </>
          ) : (
            <p className="empty">Click a building on the map to edit it. Drag the background to pan, scroll to zoom.</p>
          )}

          <h3 className="section-title">Instances ({instances.length})</h3>
          <ul className="item-list compact">
            {instances.map((inst, index) => (
              <li key={index}>
                <button type="button" className={current === index ? 'active' : ''} onClick={() => setSelected(index)}>
                  <span className="swatch" style={{ background: rgbToHex(types.get(inst?.building_id)?.color) }} />
                  <span className="item-title">{inst?.id}</span>
                  <span className="item-meta">
                    {inst?.position?.x}, {inst?.position?.y}
                  </span>
                </button>
                <span className="reorder">
                  <button
                    type="button"
                    className="btn tiny ghost"
                    title="Draw earlier"
                    disabled={index === 0}
                    onClick={() => {
                      setInstances(moveItem(instances, index, index - 1));
                      if (current === index) setSelected(index - 1);
                    }}
                  >
                    ↑
                  </button>
                  <button
                    type="button"
                    className="btn tiny ghost"
                    title="Draw later"
                    disabled={index === instances.length - 1}
                    onClick={() => {
                      setInstances(moveItem(instances, index, index + 1));
                      if (current === index) setSelected(index + 1);
                    }}
                  >
                    ↓
                  </button>
                </span>
              </li>
            ))}
          </ul>
        </aside>
      </div>
    </div>
  );
}
