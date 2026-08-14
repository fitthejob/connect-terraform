import type { FlowLogEntry } from "../unpaired-block";

// Modeled on real captured entries from live hangup tests (see CLAUDE.md's
// 2026-08-14 TODO entries) -- a completed MenuInput selection followed by
// an abandoned CollectCode (no paired Results entry after it).
export const ABANDONED_MID_COLLECT_CODE: FlowLogEntry[] = [
  { ContactFlowName: "Main-Inbound-dev", ContactFlowModuleType: "PlayPrompt", Identifier: "Greeting", Timestamp: "2026-08-14T16:21:19.261Z" },
  { ContactFlowName: "Main-Inbound-dev", ContactFlowModuleType: "PlayPrompt", Identifier: "Greeting", Timestamp: "2026-08-14T16:21:21.855Z", Results: "Success" },
  { ContactFlowName: "Main-Inbound-dev", ContactFlowModuleType: "GetUserInput", Identifier: "MenuInput", Timestamp: "2026-08-14T16:21:43.241Z" },
  { ContactFlowName: "Main-Inbound-dev", ContactFlowModuleType: "GetUserInput", Identifier: "MenuInput", Timestamp: "2026-08-14T16:21:57.102Z", Results: "Claimsintent" },
  { ContactFlowName: "Module-SmsVerification-dev", ContactFlowModuleType: "InvokeExternalResource", Identifier: "SendCode", Timestamp: "2026-08-14T16:21:59.721Z" },
  { ContactFlowName: "Module-SmsVerification-dev", ContactFlowModuleType: "GetUserInput", Identifier: "CollectCode", Timestamp: "2026-08-14T16:21:59.867Z" },
];

// A caller who completed the whole flow -- every block paired, no
// abandonment. findLastUnpairedEntry must return undefined for this case.
export const FULLY_COMPLETED: FlowLogEntry[] = [
  { ContactFlowName: "Main-Inbound-dev", ContactFlowModuleType: "PlayPrompt", Identifier: "Greeting", Timestamp: "2026-08-14T16:00:00.000Z" },
  { ContactFlowName: "Main-Inbound-dev", ContactFlowModuleType: "PlayPrompt", Identifier: "Greeting", Timestamp: "2026-08-14T16:00:02.000Z", Results: "Success" },
  { ContactFlowName: "Main-Inbound-dev", ContactFlowModuleType: "GetUserInput", Identifier: "MenuInput", Timestamp: "2026-08-14T16:00:03.000Z" },
  { ContactFlowName: "Main-Inbound-dev", ContactFlowModuleType: "GetUserInput", Identifier: "MenuInput", Timestamp: "2026-08-14T16:00:10.000Z", Results: "Claimsintent" },
];

// Abandoned on the very first block -- no prior paired entries at all.
export const ABANDONED_ON_FIRST_BLOCK: FlowLogEntry[] = [
  { ContactFlowName: "Main-Inbound-dev", ContactFlowModuleType: "PlayPrompt", Identifier: "Greeting", Timestamp: "2026-08-14T16:00:00.000Z" },
];

export const EMPTY_LOG: FlowLogEntry[] = [];

// RetryLoop re-enters CollectCode with the same ContactFlowName+Identifier
// on each attempt. Abandoned on the SECOND attempt: attempt 1 starts and
// completes (no match, looped back), attempt 2 starts and is never
// completed. The nearest-match algorithm must not let attempt 1's
// completion satisfy attempt 2's start.
export const ABANDONED_ON_SECOND_RETRY_ATTEMPT: FlowLogEntry[] = [
  { ContactFlowName: "Module-SmsVerification-dev", ContactFlowModuleType: "GetUserInput", Identifier: "CollectCode", Timestamp: "2026-08-14T17:00:00.000Z" },
  { ContactFlowName: "Module-SmsVerification-dev", ContactFlowModuleType: "GetUserInput", Identifier: "CollectCode", Timestamp: "2026-08-14T17:00:05.000Z", Results: "NoMatchingCondition" },
  { ContactFlowName: "Module-SmsVerification-dev", ContactFlowModuleType: "GetUserInput", Identifier: "CollectCode", Timestamp: "2026-08-14T17:00:10.000Z" },
];

// The specific bug scenario: abandoned on the FIRST attempt at CollectCode
// (start@T1, no completion for that attempt), while a LATER, separate
// invocation of the same block (start@T2, completion@T3) does complete.
// A naive "any later completion for this key" check would wrongly treat
// T1 as paired by T3. The correct answer is the T1 start entry -- that's
// where the caller actually stopped responding; the later invocation
// belongs to a different retry attempt entirely (e.g. a second, unrelated
// contact leg or a re-entry the algorithm must not conflate with the first).
export const ABANDONED_ON_FIRST_RETRY_ATTEMPT: FlowLogEntry[] = [
  { ContactFlowName: "Module-SmsVerification-dev", ContactFlowModuleType: "GetUserInput", Identifier: "CollectCode", Timestamp: "2026-08-14T18:00:00.000Z" },
  { ContactFlowName: "Module-SmsVerification-dev", ContactFlowModuleType: "GetUserInput", Identifier: "CollectCode", Timestamp: "2026-08-14T18:00:05.000Z" },
  { ContactFlowName: "Module-SmsVerification-dev", ContactFlowModuleType: "GetUserInput", Identifier: "CollectCode", Timestamp: "2026-08-14T18:00:10.000Z", Results: "Success" },
];
