import { describe, it, expect } from "vitest";
import { findLastUnpairedEntry } from "./unpaired-block";
import {
  ABANDONED_MID_COLLECT_CODE,
  FULLY_COMPLETED,
  ABANDONED_ON_FIRST_BLOCK,
  EMPTY_LOG,
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
});
