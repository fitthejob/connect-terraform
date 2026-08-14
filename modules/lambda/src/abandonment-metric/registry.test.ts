import { describe, it, expect } from "vitest";
import { matchRegistry, REGISTRY } from "./registry";

describe("matchRegistry", () => {
  it("matches the Main-Inbound MenuInput entry", () => {
    const result = matchRegistry("Main-Inbound-dev", "MenuInput");
    expect(result).toEqual({
      flowName: "Main-Inbound",
      identifier: "MenuInput",
      label: "menu-selection",
    });
  });

  it("matches the Module-SmsVerification CollectCode entry", () => {
    const result = matchRegistry("Module-SmsVerification-dev", "CollectCode");
    expect(result).toEqual({
      flowName: "Module-SmsVerification",
      identifier: "CollectCode",
      label: "sms-verification-code",
    });
  });

  it("matches regardless of environment suffix (-dev, -staging, -prod)", () => {
    expect(matchRegistry("Main-Inbound-staging", "MenuInput")?.label).toBe("menu-selection");
    expect(matchRegistry("Main-Inbound-prod", "MenuInput")?.label).toBe("menu-selection");
  });

  it("returns undefined for an unknown flow name", () => {
    expect(matchRegistry("Some-Other-Flow-dev", "MenuInput")).toBeUndefined();
  });

  it("returns undefined for a known flow but unknown identifier", () => {
    expect(matchRegistry("Main-Inbound-dev", "SomeOtherBlock")).toBeUndefined();
  });

  it("is case-sensitive on both flow name and identifier", () => {
    expect(matchRegistry("main-inbound-dev", "MenuInput")).toBeUndefined();
    expect(matchRegistry("Main-Inbound-dev", "menuinput")).toBeUndefined();
  });

  it("REGISTRY has exactly the two entries defined by the design", () => {
    expect(REGISTRY).toHaveLength(2);
  });
});
