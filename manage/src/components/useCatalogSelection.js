import { useEffect, useState } from 'react';

// Requests identify the row by index, so malformed duplicate IDs remain repairable.
export function useCatalogSelection(request) {
  const [selected, setSelected] = useState(request?.index ?? 0);
  useEffect(() => {
    if (request) setSelected(request.index);
  }, [request]);
  return [selected, setSelected];
}
