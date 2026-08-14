import { describe, it, expect } from "vitest";
import { buildMetricPayload } from "./metric-payload";
import type { RegistryEntry } from "./registry";

describe("buildMetricPayload", () => {
  const entry: RegistryEntry = {
    flowName: "Module-SmsVerification",
    identifier: "CollectCode",
    label: "sms-verification-code",
  };

  it("builds a PutMetricData-shaped payload with the correct namespace, metric name, and dimensions", () => {
    const payload = buildMetricPayload(entry, "ContactCenter/SelfService", "dev");
    expect(payload.Namespace).toBe("ContactCenter/SelfService");
    expect(payload.MetricData).toHaveLength(1);
    expect(payload.MetricData[0].MetricName).toBe("SelfServiceAbandonment");
    expect(payload.MetricData[0].Value).toBe(1);
    expect(payload.MetricData[0].Unit).toBe("Count");
    expect(payload.MetricData[0].Dimensions).toEqual([
      { Name: "AbandonmentPoint", Value: "sms-verification-code" },
      { Name: "Stage", Value: "dev" },
    ]);
  });

  it("uses the registry entry's label as the AbandonmentPoint dimension for a different entry", () => {
    const menuEntry: RegistryEntry = {
      flowName: "Main-Inbound",
      identifier: "MenuInput",
      label: "menu-selection",
    };
    const payload = buildMetricPayload(menuEntry, "ContactCenter/SelfService", "prod");
    expect(payload.MetricData[0].Dimensions).toEqual([
      { Name: "AbandonmentPoint", Value: "menu-selection" },
      { Name: "Stage", Value: "prod" },
    ]);
  });
});
