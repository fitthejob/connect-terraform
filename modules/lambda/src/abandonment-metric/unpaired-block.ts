export interface FlowLogEntry {
  ContactFlowName: string;
  ContactFlowModuleType: string;
  Identifier: string;
  Timestamp: string;
  Results?: string;
}

export function findLastUnpairedEntry(entries: FlowLogEntry[]): FlowLogEntry | undefined {
  // A block can be re-entered multiple times in one contact (e.g.
  // RetryLoop re-entering CollectCode), each producing its own
  // start/completion pair that shares the same ContactFlowName+Identifier
  // key. So a start entry must only be considered "paired" by the NEAREST
  // later completion entry for that key, not just any later one -- an
  // earlier attempt's start must not be satisfied by a later attempt's
  // completion, and vice versa.
  //
  // Walk forward keeping a list of currently-open (unmatched) start
  // entries per key. A completion entry closes out the MOST RECENTLY
  // opened still-open start for its key (nearest-match), leaving any
  // earlier still-open starts for that same key untouched -- they remain
  // candidate abandonment points in their own right. A new start entry is
  // simply appended as another open entry for its key.
  //
  // At the end, every entry still open (across all keys) is an unpaired
  // start. The one that appears LAST in the original array is the actual
  // abandonment point (the most recent thing that happened in the
  // contact with no completion after it).
  const openByKey = new Map<string, FlowLogEntry[]>();
  const stillOpen = new Set<FlowLogEntry>();

  const keyOf = (e: FlowLogEntry) => `${e.ContactFlowName} ${e.Identifier}`;

  for (const entry of entries) {
    const key = keyOf(entry);
    if (entry.Results !== undefined) {
      const open = openByKey.get(key);
      if (open && open.length > 0) {
        const nearest = open.pop()!;
        stillOpen.delete(nearest);
      }
    } else {
      if (!openByKey.has(key)) {
        openByKey.set(key, []);
      }
      openByKey.get(key)!.push(entry);
      stillOpen.add(entry);
    }
  }

  for (let i = entries.length - 1; i >= 0; i--) {
    if (stillOpen.has(entries[i])) {
      return entries[i];
    }
  }
  return undefined;
}
