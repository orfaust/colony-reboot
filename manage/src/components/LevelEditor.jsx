import { useEffect, useId, useMemo, useRef, useState } from 'react';
import { Checkbox, CommitInput, Field, NumberInput, RefSelect } from './fields.jsx';
import { GAME_WINDOW, WORLD_SCALE } from '../lib/game.js';
import { placementPosition } from '../lib/mapPlacement.js';
import { CONTROL_UNIT_ID } from '../lib/schema.js';
import { contrastText, isPlainObject, objectItems, rgbToHex } from '../lib/object.js';
import { storageCapacities, storedInSync, syncStored } from '../lib/stored.js';
import LevelStationEditor from './LevelStationEditor.jsx';
import { buildingReferences, renameLevelBuilding, removeLevelBuilding, reorderLevelBuildings } from '../lib/level.js';

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

/** residents_amount aligned with the type: kept (or 0) when the type has residents, null otherwise. */
const residentsAmountFor = (amount, type) => (isPlainObject(type?.residents) ? (typeof amount === 'number' ? amount : 0) : null);

/** How many residents live in the instance: only for building types with residents, null otherwise. */
function ResidentsAmountField({ instance, type, onChange }) {
  if (!type) return null;
  const residents = isPlainObject(type.residents) ? type.residents : null;
  const amount = instance.residents_amount;
  if (!residents)
    return amount === null ? null : (
      <div className="callout error">
        <span>residents_amount must be null: this building type has no residents.</span>
        <button type="button" className="btn tiny" onClick={() => onChange(null)}>
          Set to null
        </button>
      </div>
    );
  const invalid = !(Number.isInteger(amount) && amount >= 0 && amount <= residents.capacity);
  return (
    <Field label="Residents amount" hint={`${residents.type} living here, out of ${residents.capacity}`} error={invalid ? `Must be a whole number in [0, ${Math.floor(residents.capacity)}]` : null}>
      <NumberInput integer value={amount} min={0} max={Math.floor(residents.capacity)} onChange={(v) => onChange(v, 'residents-amount')} />
    </Field>
  );
}

/** Units the instance holds per needed or produced resource; each amount is bounded by its capacity. */
function StoredFields({ instance, type, ctx, onChange }) {
  if (!type) return null;
  const inSync = storedInSync(instance.stored, type);
  const capacities = storageCapacities(type);
  if (capacities.size === 0 && inSync) return <p className="hint">Stored: this building type has no needs, products, or storage.</p>;
  const stored = Array.isArray(instance.stored) ? instance.stored : [];
  const resources = objectItems(ctx.resources);
  const resourceOf = (id) => resources.find((r) => r.id === id);
  const synced = syncStored(instance.stored, type);
  return (
    <fieldset className="recipe stored-fields">
      <legend>Stored</legend>
      {synced.map(({ resource_id }) => {
        const capacity = capacities.get(resource_id);
        const amount = stored.find((s) => s?.resource_id === resource_id)?.amount;
        const invalid = !(typeof amount === 'number' && amount >= 0 && amount <= capacity);
        return (
          <label key={resource_id} className="stored-row">
            <span>{ctx.texts?.[resourceOf(resource_id)?.name_key] ?? resource_id}</span>
            <NumberInput
              value={amount}
              min={0}
              max={capacity}
              disabled={!inSync}
              className={inSync && invalid ? 'invalid' : ''}
              onChange={(v) => onChange(stored.map((s) => (s?.resource_id === resource_id ? { ...s, amount: v } : s)), `stored-${resource_id}`)}
            />
            <span className="unit-label">
              / {capacity} {ctx.texts?.[resourceOf(resource_id)?.unit_type_key] ?? ''}
            </span>
          </label>
        );
      })}
      {!inSync && (
        <div className="callout error">
          <span>stored does not match the resources this building type needs, produces, and stores.</span>
          <button type="button" className="btn tiny" onClick={() => onChange(synced)}>
            Sync with the building type
          </button>
        </div>
      )}
    </fieldset>
  );
}

function MapCanvas({ instances, types, texts, selected, onSelect, onMove, onKeyDown, placing, onPlace, snap, showGrid }) {
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
    if (e.button !== 0) return;
    svgRef.current.focus();
    if (placing) { e.stopPropagation(); return; }
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
        className={`map${placing ? ' placing' : ''}`}
        onClick={(e) => {
          if (placing && e.button === 0) onPlace(placementPosition(e.clientX, e.clientY, svgRef.current.getBoundingClientRect(), view, snap));
        }}
        tabIndex={0}
        role="group"
        aria-label={placing ? 'Level map. Click to place a building. Escape exits placement mode.' : 'Level map. Select a building, then use arrows to move or Delete to remove.'}
        onKeyDown={onKeyDown}
        onLostPointerCapture={endDrag}
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
          // Catalog dimensions are pixels; the map works in world units (64 px each).
          const w = (type?.width > 0 ? type.width / WORLD_SCALE : 1) * view.scale;
          const h = (type?.height > 0 ? type.height / WORLD_SCALE : 1) * view.scale;
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

/** Subjects of the level; residence and initial_assignment pick building instance ids of this level. */
export default function LevelEditor(props) {
  if (!isPlainObject(props.data)) return <p className="callout error">Expected a level object. Repair it in the JSON tab.</p>;
  if (!Array.isArray(props.data.buildings)) return <p className="callout error">Expected a buildings array. Repair it in the JSON tab.</p>;
  return <LevelForm {...props} />;
}

function LevelForm({ data, onChange, ctx }) {
  const [levelTab, setLevelTab] = useState('map');
  const tabId = useId();
  const tabs = [{ id: 'map', label: 'Map' }, { id: 'station', label: 'Space station' }];
  const tabButtons = useRef([]);
  const onTabKey = (event, index) => {
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? tabs.length - 1
      : event.key === 'ArrowRight' ? (index + 1) % tabs.length
        : event.key === 'ArrowLeft' ? (index + tabs.length - 1) % tabs.length : null;
    if (next === null) return;
    event.preventDefault();
    setLevelTab(tabs[next].id);
    tabButtons.current[next]?.focus();
  };
  const [actionError, setActionError] = useState('');
  const instances = Array.isArray(data.buildings) ? data.buildings : [];
  const types = useMemo(() => new Map(objectItems(ctx.buildings).map((t) => [t.id, t])), [ctx.buildings]);
  const typeOptions = [...types.values()].map((t) => ({ value: t.id, label: `${ctx.texts?.[t.name_key] ?? t.id} (${t.id})` }));
  const [selected, setSelected] = useState(null);
  const [snap, setSnap] = useState(0.5);
  const [showGrid, setShowGrid] = useState(true);
  const [newType, setNewType] = useState('');
  const [placeMode, setPlaceMode] = useState(false);
  const placing = placeMode && types.has(newType);

  const current = selected !== null && selected < instances.length ? selected : null;
  const setInstances = (next, historyKey) => onChange({ ...data, buildings: next }, historyKey);
  const updateInstance = (index, patch, historyKey) =>
    setInstances(
      instances.map((b, i) => (i === index ? { ...b, ...patch } : b)),
      historyKey,
    );

  const addInstance = (typeId, position) => {
    const type = types.get(typeId);
    if (!type) return;
    const instance = {
      id: nextId(type.code, instances),
      building_id: typeId,
      position,
      health: 1,
      repairing: false,
      enable_at_start: typeId === CONTROL_UNIT_ID || type.always_on === true,
      stored: syncStored([], type),
      residents_amount: residentsAmountFor(null, type),
    };
    setInstances([...instances, instance]);
    setSelected(instances.length);
  };
  const removeInstance = (index) => {
    const refs = buildingReferences(data, instances[index]?.id);
    if (refs.residents.length) {
      setActionError(`Move ${refs.residents.length} resident(s) to another residence before deleting this building.`);
      return;
    }
    if (!confirm(`Delete building "${instances[index]?.id}"?${refs.workers.length ? ` ${refs.workers.length} initial assignment(s) will become unassigned.` : ''}`)) return;
    const next = removeLevelBuilding(data, index);
    if (!next) return;
    onChange(next);
    setSelected(null);
    setActionError('');
  };
  const moveInstance = (from, to) => {
    const next = reorderLevelBuildings(data, current, from, to);
    onChange(next.data);
    setSelected(next.selected);
  };
  const renameInstance = (nextId) => {
    const next = renameLevelBuilding(data, current, nextId);
    if (!next) { setActionError('Building ID must be nonempty, without NUL characters, and unique.'); return false; }
    onChange(next);
    setActionError('');
    return true;
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

  // Only the focused map owns these shortcuts, never menus or other editors.
  const onMapKey = (e) => {
      if (e.key === 'Escape') { setPlaceMode(false); e.preventDefault(); return; }
      if (placing) return;
      if (e.defaultPrevented || e.ctrlKey || e.metaKey || e.altKey || current === null || !isPlainObject(instances[current])) return;
      const step = snap || 0.1;
      const moves = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] };
      if (e.key === 'Delete') { e.preventDefault(); removeInstance(current); }
      else if (moves[e.key]) {
        e.preventDefault();
        const p = instances[current].position ?? { x: 0, y: 0 };
        updateInstance(current, { position: { x: round(p.x + moves[e.key][0]), y: round(p.y + moves[e.key][1]) } }, `nudge-${current}`);
      }
  };

  const b = current !== null ? instances[current] : null;
  const idDuplicate = b && instances.some((other, i) => i !== current && other?.id === b.id);
  const outOfSync = instances.filter(
    (inst) =>
      isPlainObject(inst) &&
      types.has(inst.building_id) &&
      (!storedInSync(inst.stored, types.get(inst.building_id)) ||
        inst.residents_amount !== residentsAmountFor(inst.residents_amount, types.get(inst.building_id)) ||
        (types.get(inst.building_id).always_on === true && inst.enable_at_start !== true)),
  );
  const syncAll = () =>
    setInstances(
      instances.map((inst) =>
        isPlainObject(inst) && types.has(inst.building_id)
          ? {
              ...inst,
              stored: syncStored(inst.stored, types.get(inst.building_id)),
              residents_amount: residentsAmountFor(inst.residents_amount, types.get(inst.building_id)),
              ...(types.get(inst.building_id).always_on === true ? { enable_at_start: true } : {}),
            }
          : inst,
      ),
    );

  return (
    <div className="level-editor">
      <div className="tabs level-tabs" role="tablist" aria-label="Level editor sections">
        {tabs.map((tab, index) => <button key={tab.id} ref={(node) => { tabButtons.current[index] = node; }}
          type="button" role="tab" id={`${tabId}-${tab.id}-tab`} aria-controls={`${tabId}-${tab.id}-panel`}
          aria-selected={levelTab === tab.id} tabIndex={levelTab === tab.id ? 0 : -1}
          className={levelTab === tab.id ? 'active' : ''} onClick={() => setLevelTab(tab.id)}
          onKeyDown={(event) => onTabKey(event, index)}>{tab.label}</button>)}
      </div>
      <div className="level-map-panel" role="tabpanel" id={`${tabId}-map-panel`} aria-labelledby={`${tabId}-map-tab`} hidden={levelTab !== 'map'}>
      {actionError && <div className="callout error" role="alert">{actionError}<button type="button" className="btn tiny" onClick={() => setActionError('')}>Dismiss</button></div>}
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
        {outOfSync.length > 0 && (
          <button type="button" className="btn" title="Align stored, residents_amount, and enable_at_start (always_on types) with each building type" onClick={syncAll}>
            Sync stored ({outOfSync.length})
          </button>
        )}
        <div className="toolbar-spacer" />
        <Field label="Add building">
          <div className="inline">
            <RefSelect value={newType} options={typeOptions} onChange={setNewType} placeholder="— building type —" />
            <button type="button" className={`btn${placing ? ' primary' : ''}`} aria-label="Place buildings on map" aria-pressed={placing}
              title="Toggle placement mode; click the map to place. Escape exits."
              disabled={!types.has(newType)} onClick={() => setPlaceMode(!placing)}>
              <span aria-hidden="true">+</span>
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
          onKeyDown={onMapKey}
          placing={placing}
          onPlace={(position) => addInstance(newType, position)}
          snap={snap}
          showGrid={showGrid}
          onMove={(index, position, key) => updateInstance(index, { position }, key)}
        />

        <aside className="panel inspector" tabIndex={0} aria-label="Building properties and instance list">
          {b && isPlainObject(b) ? (
            <>
              <div className="detail-header">
                <div>
                  <span className="eyebrow">Instance #{current} · draw order</span>
                  <h2>{b.id}</h2>
                </div>
              </div>
              <Field label="ID" error={idDuplicate ? 'Duplicate ID' : typeof b.id !== 'string' || !b.id.trim() ? 'Required' : null}>
                <CommitInput value={typeof b.id === 'string' ? b.id : ''} onCommit={renameInstance} spellCheck={false} />
              </Field>
              <Field label="Building type (building_id)">
                <RefSelect
                  value={b.building_id}
                  options={typeOptions}
                  onChange={(v) =>
                    updateInstance(current, {
                      building_id: v,
                      stored: syncStored(b.stored, types.get(v)),
                      residents_amount: residentsAmountFor(b.residents_amount, types.get(v)),
                      ...(types.get(v)?.always_on === true ? { enable_at_start: true } : {}),
                    })
                  }
                />
              </Field>
              <div className="form-grid">
                <Field label="X" hint="World units, right">
                  <NumberInput
                    value={b.position?.x}
                    onChange={(v) => updateInstance(current, { position: { ...b.position, x: v } }, `x-${current}`)}
                  />
                </Field>
                <Field label="Y" hint="World units, down">
                  <NumberInput
                    value={b.position?.y}
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
                  <NumberInput value={b.health} min={0} max={1} onChange={(v) => updateInstance(current, { health: v }, `health-${current}`)} />
                </div>
              </Field>
              <Checkbox checked={b.repairing} onChange={(v) => updateInstance(current, { repairing: v })} label="Repairing" />
              <Checkbox
                checked={b.enable_at_start}
                // always_on types must start enabled, so the box cannot be cleared for them.
                onChange={(v) => updateInstance(current, { enable_at_start: v || types.get(b.building_id)?.always_on === true })}
                label="Enable at start"
              />
              {types.get(b.building_id)?.always_on === true &&
                (b.enable_at_start === true ? (
                  <p className="hint">This building type is always on: it must start enabled.</p>
                ) : (
                  <div className="callout error">
                    <span>This building type is always_on: enable_at_start must be true.</span>
                    <button type="button" className="btn tiny" onClick={() => updateInstance(current, { enable_at_start: true })}>
                      Enable at start
                    </button>
                  </div>
                ))}
              {b.building_id === CONTROL_UNIT_ID && <p className="hint">Control Units are always active.</p>}
              {b.enable_at_start && b.building_id !== CONTROL_UNIT_ID && b.health < types.get(b.building_id)?.min_operative_health && (
                <div className="callout error">
                  Health is below min_operative_health ({types.get(b.building_id).min_operative_health}): this building cannot start active.
                </div>
              )}
              <StoredFields
                instance={b}
                type={types.get(b.building_id)}
                ctx={ctx}
                onChange={(stored, key) => updateInstance(current, { stored }, key && `${key}-${current}`)}
              />
              <ResidentsAmountField
                instance={b}
                type={types.get(b.building_id)}
                onChange={(residents_amount, key) => updateInstance(current, { residents_amount }, key && `${key}-${current}`)}
              />
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
                      moveInstance(index, index - 1);
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
                      moveInstance(index, index + 1);
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
      <div className="level-station-panel" role="tabpanel" id={`${tabId}-station-panel`} aria-labelledby={`${tabId}-station-tab`} hidden={levelTab !== 'station'}>
        <LevelStationEditor value={data.space_station} onChange={(next, key) => onChange({ ...data, space_station: next }, key)} ctx={ctx} />
      </div>
    </div>
  );
}
