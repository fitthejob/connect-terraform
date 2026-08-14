// The real "has this ContactId been seen before" lookup is a DynamoDB
// GetItem call, deliberately kept out of this file (see index.ts's
// getDedupRecord) so this decision logic stays unit-testable without
// mocking AWS. Trivial today; kept as its own function/test because the
// design's dedup rationale (overlapping poll lookback windows, not a
// within-poll race -- see the spec) is exactly the kind of thing worth
// pinning down with an explicit named function rather than an inline
// if-check that could silently drift.
export function shouldProcess(alreadySeen: boolean): boolean {
  return !alreadySeen;
}
