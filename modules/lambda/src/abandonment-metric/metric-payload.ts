import type { RegistryEntry } from "./registry";

interface MetricDatum {
  MetricName: string;
  Value: number;
  Unit: string;
  Dimensions: { Name: string; Value: string }[];
}

interface PutMetricDataInput {
  Namespace: string;
  MetricData: MetricDatum[];
}

export function buildMetricPayload(
  entry: RegistryEntry,
  namespace: string,
  stage: string,
): PutMetricDataInput {
  return {
    Namespace: namespace,
    MetricData: [
      {
        MetricName: "SelfServiceAbandonment",
        Value: 1,
        Unit: "Count",
        Dimensions: [
          { Name: "AbandonmentPoint", Value: entry.label },
          { Name: "Stage", Value: stage },
        ],
      },
    ],
  };
}
