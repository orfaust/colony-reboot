/** Lists fields the Odin loader does not know (it rejects them) with a remove button. */
export default function ExtraFields({ value, schema, onChange }) {
  const extra = Object.keys(value).filter((k) => !(k in schema.fields));
  if (extra.length === 0) return null;
  return (
    <div className="callout error">
      <strong>Unknown fields (the game loader rejects them):</strong>
      {extra.map((k) => (
        <span key={k} className="chip">
          {k}
          <button
            type="button"
            className="btn tiny ghost"
            onClick={() => {
              const { [k]: _removed, ...rest } = value;
              onChange(rest);
            }}
          >
            ✕
          </button>
        </span>
      ))}
    </div>
  );
}
