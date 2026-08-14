import { describe, it, expect } from "vitest";
import { findLastUnpairedEntry } from "./unpaired-block";
import {
  ABANDONED_MID_COLLECT_CODE,
  FULLY_COMPLETED,
  ABANDONED_ON_FIRST_BLOCK,
  EMPTY_LOG,
  ABANDONED_ON_SECOND_RETRY_ATTEMPT,
  ABANDONED_ON_FIRST_RETRY_ATTEMPT,
} from "./__fixtures__/flow-log-entries";

describe("findLastUnpairedEntry", () => {
  it("finds the unpaired CollectCode entry when abandoned mid-block", () => {
    const result = findLastUnpairedEntry(ABANDONED_MID_COLLECT_CODE);
    expect(result).toBeDefined();
    expect(result?.Identifier).toBe("CollectCode");
    expect(result?.ContactFlowName).toBe("Module-SmsVerification-dev");
  });

  it("returns undefined when every block is paired (no abandonment)", () => {
    expect(findLastUnpairedEntry(FULLY_COMPLETED)).toBeUndefined();
  });

  it("finds the unpaired entry when abandoned on the very first block", () => {
    const result = findLastUnpairedEntry(ABANDONED_ON_FIRST_BLOCK);
    expect(result?.Identifier).toBe("Greeting");
  });

  it("returns undefined for an empty log", () => {
    expect(findLastUnpairedEntry(EMPTY_LOG)).toBeUndefined();
  });

  it("returns undefined for a log with a single paired entry", () => {
    const single = [
      { ContactFlowName: "Main-Inbound-dev", ContactFlowModuleType: "PlayPrompt", Identifier: "Greeting", Timestamp: "2026-08-14T16:00:00.000Z", Results: "Success" },
    ];
    expect(findLastUnpairedEntry(single)).toBeUndefined();
  });

  it("finds the unpaired second-attempt CollectCode entry when RetryLoop re-enters the same block and abandons on the later attempt", () => {
    const result = findLastUnpairedEntry(ABANDONED_ON_SECOND_RETRY_ATTEMPT);
    expect(result).toBeDefined();
    expect(result?.Timestamp).toBe("2026-08-14T17:00:10.000Z");
  });

  it("finds the earlier unpaired CollectCode entry when abandoned on the first attempt, even though a later re-entry of the same Identifier completes", () => {
    // Regression test for the nearest-match bug: a naive "any later completion
    // for this key" check would incorrectly pair the first (abandoned) start
    // entry with the second attempt's completion entry, since both share the
    // same ContactFlowName+Identifier. The correct match is nearest-neighbor:
    // the first start is only satisfied by the second start's own completion,
    // leaving the first start permanently unmatched -- that's where the
    // caller actually abandoned.
    const result = findLastUnpairedEntry(ABANDONED_ON_FIRST_RETRY_ATTEMPT);
    expect(result).toBeDefined();
    expect(result?.Timestamp).toBe("2026-08-14T18:00:00.000Z");
  });
});
