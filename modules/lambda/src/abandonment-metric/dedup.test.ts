import { describe, it, expect } from "vitest";
import { shouldProcess } from "./dedup";

describe("shouldProcess", () => {
  it("returns true when the contact has not been seen before", () => {
    expect(shouldProcess(false)).toBe(true);
  });

  it("returns false when the contact has already been processed", () => {
    expect(shouldProcess(true)).toBe(false);
  });
});
