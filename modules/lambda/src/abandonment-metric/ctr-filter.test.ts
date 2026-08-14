import { describe, it, expect } from "vitest";
import { isAbandonmentCandidate } from "./ctr-filter";

describe("isAbandonmentCandidate", () => {
  it("returns true when DisconnectReason is CUSTOMER_DISCONNECT and DisconnectTimestamp is present", () => {
    expect(
      isAbandonmentCandidate({
        contactId: "abc-123",
        disconnectReason: "CUSTOMER_DISCONNECT",
        disconnectTimestamp: "2026-08-14T16:57:15.410000-04:00",
      }),
    ).toBe(true);
  });

  it("returns false when DisconnectReason is some other value", () => {
    expect(
      isAbandonmentCandidate({
        contactId: "abc-123",
        disconnectReason: "AGENT_DISCONNECT",
        disconnectTimestamp: "2026-08-14T16:57:15.410000-04:00",
      }),
    ).toBe(false);
  });

  it("returns false during the two-stage CTR arrival window -- DisconnectTimestamp present but DisconnectReason not yet populated", () => {
    // Confirmed real behavior (see CLAUDE.md's 2026-08-14 TODO entry): the
    // CTR record is not atomic -- DisconnectTimestamp becomes queryable
    // slightly before DisconnectReason does. Must not be treated as a match
    // until the specific field this Lambda needs is actually populated.
    expect(
      isAbandonmentCandidate({
        contactId: "abc-123",
        disconnectReason: undefined,
        disconnectTimestamp: "2026-08-14T16:57:15.410000-04:00",
      }),
    ).toBe(false);
  });

  it("returns false when neither field is populated yet", () => {
    expect(isAbandonmentCandidate({ contactId: "abc-123" })).toBe(false);
  });
});
