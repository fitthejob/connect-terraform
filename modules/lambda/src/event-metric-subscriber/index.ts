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

interface MetricPlan {
  metricName: string;
  dimensionField?: keyof EventBridgeEvent["detail"];
  valueField?: keyof EventBridgeEvent["detail"];
}

// One entry per EventBridge rule this Lambda is subscribed to. All four
// rules target this single function -- it's one concern (turn an event
// into a CloudWatch metric), just branching on detail-type for which
// metric/dimension applies.
const METRIC_PLANS: Record<string, MetricPlan> = {
  "contact.initiated": {
    metricName: "ContactsInitiated",
  },
  "contact.transferred": {
    metricName: "ContactsTransferred",
    dimensionField: "queue",
  },
  "contact.disconnected": {
    metricName: "ContactDurationSeconds",
    valueField: "durationSeconds",
  },
  "verification.completed": {
    metricName: "VerificationOutcome",
    dimensionField: "verificationStatus",
  },
};

export const handler = async (event: EventBridgeEvent): Promise<void> => {
  const detailType = event["detail-type"];
  const plan = METRIC_PLANS[detailType];

  console.log(JSON.stringify({
    contactId: event.detail.contactId,
    message: `Received ${detailType}`,
    detail: event.detail,
  }));

  if (!plan) {
    console.error(JSON.stringify({ contactId: event.detail.contactId, message: `No metric plan for detail-type "${detailType}"` }));
    return;
  }

  const value = plan.valueField && typeof event.detail[plan.valueField] === "number"
    ? (event.detail[plan.valueField] as number)
    : 1;

  const dimensionValue = plan.dimensionField ? event.detail[plan.dimensionField] : undefined;

  try {
    await cloudwatch.send(
      new PutMetricDataCommand({
        Namespace: NAMESPACE,
        MetricData: [
          {
            MetricName: plan.metricName,
            Value: value,
            Unit: plan.valueField ? "Seconds" : "Count",
            Timestamp: new Date(event.detail.timestamp),
            ...(dimensionValue
              ? { Dimensions: [{ Name: plan.dimensionField as string, Value: String(dimensionValue) }] }
              : {}),
          },
        ],
      }),
    );
  } catch (error) {
    console.error(JSON.stringify({
      contactId: event.detail.contactId,
      message: `Failed to publish metric ${plan.metricName}`,
      error: String(error),
    }));
    throw error; // triggers Lambda's own async-invoke retry, then its on_failure destination (see modules/lambda-event-metric-subscriber's event_invoke_config) -- EventBridge's own rule-target retry/DLQ never sees this, it only covers handoff failures
  }
};
