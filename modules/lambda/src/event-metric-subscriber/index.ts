import {
  CloudWatchClient,
  PutMetricDataCommand,
} from "@aws-sdk/client-cloudwatch";

const cloudwatch = new CloudWatchClient({ region: process.env.AWS_REGION });

const NAMESPACE = "ContactCenter/Events";

// EventBridge's own envelope -- distinct from the Connect Details.Parameters
// contract used by Lambdas invoked directly from contact flows.
interface EventBridgeEvent {
  "detail-type": string;
  detail: {
    contactId: string;
    channel: string;
    queue?: string;
    intent?: string;
    verificationStatus?: string;
    durationSeconds?: number;
    timestamp: string;
  };
}

export const handler = async (event: EventBridgeEvent): Promise<void> => {
  const metricName = process.env.METRIC_NAME;
  const dimensionField = process.env.DIMENSION_FIELD as keyof EventBridgeEvent["detail"] | undefined;
  const valueField = process.env.VALUE_FIELD as keyof EventBridgeEvent["detail"] | undefined;

  if (!metricName) {
    console.error(JSON.stringify({ message: "METRIC_NAME not configured", event }));
    return;
  }

  console.log(JSON.stringify({
    contactId: event.detail.contactId,
    message: `Received ${event["detail-type"]}`,
    detail: event.detail,
  }));

  const value = valueField && typeof event.detail[valueField] === "number"
    ? (event.detail[valueField] as number)
    : 1;

  const dimensionValue = dimensionField ? event.detail[dimensionField] : undefined;

  try {
    await cloudwatch.send(
      new PutMetricDataCommand({
        Namespace: NAMESPACE,
        MetricData: [
          {
            MetricName: metricName,
            Value: value,
            Unit: valueField ? "Seconds" : "Count",
            Timestamp: new Date(event.detail.timestamp),
            ...(dimensionValue
              ? { Dimensions: [{ Name: dimensionField as string, Value: String(dimensionValue) }] }
              : {}),
          },
        ],
      }),
    );
  } catch (error) {
    console.error(JSON.stringify({
      contactId: event.detail.contactId,
      message: `Failed to publish metric ${metricName}`,
      error: String(error),
    }));
    throw error; // let this land in the DLQ per the rule's retry policy
  }
};
