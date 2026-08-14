export interface FlowLogEntry {
  ContactFlowName: string;
  ContactFlowModuleType: string;
  Identifier: string;
  Timestamp: string;
  Results?: string;
}

export function findLastUnpairedEntry(entries: FlowLogEntry[]): FlowLogEntry | undefined {
  // Walk from the end: the last "start" entry (no Results field) that has
  // no later paired "Results" entry for the same ContactFlowName+Identifier
  // is the block execution stopped on.
  for (let i = entries.length - 1; i >= 0; i--) {
    const candidate = entries[i];
    if (candidate.Results !== undefined) {
      // This is itself a completion entry, not a start -- skip.
      continue;
    }
    const hasCompletion = entries.some(
      (e) =>
        e.Results !== undefined &&
        e.ContactFlowName === candidate.ContactFlowName &&
        e.Identifier === candidate.Identifier &&
        e.Timestamp >= candidate.Timestamp,
    );
    if (!hasCompletion) {
      return candidate;
    }
  }
  return undefined;
}
