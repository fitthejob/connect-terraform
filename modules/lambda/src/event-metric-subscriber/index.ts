import {
  CloudWatchClient,
  PutMetricDataCommand,
} from "@aws-sdk/client-cloudwatch";

const cloudwatch = new CloudWatchClient({ region: process.env.AWS_REGION });

const NAMESPACE = "ContactCenter/Events";

// EventBridge's own envelope -- distinct from the Connect Details.Parameters
// contract used by Lambdas invoked directly from contact flows.
interface CustomEventBridgeEvent {
  "detail-type": string;
  detail: {
    contactId: string;
    channel: string;
    queue?: string;
    intent?: string;
    verificationStatus?: string;
    timestamp: string;
  };
}

// Amazon Connect's own native Contact Event shape (source: aws.connect),
// distinct from this repo's custom contact-center-events-{env} bus shape
// above -- different field names, no flat "timestamp", eventType nested
// inside detail rather than being the detail-type itself. The detail-type
// value "Amazon Connect Contact Event" is confirmed correct (matches the
// EventBridge service-event registry) -- see
// modules/eventbridge-pipeline/main.tf's rule comment for the full
// citation and a note on a misleading doc-sample naming discrepancy. Still
// worth a belt-and-braces confirmation against a live event once this is
// actually applied, not because the value is in doubt.
interface NativeContactEvent {
  "detail-type": string;
  detail: {
    eventType: string;
    contactId: string;
    channel: string;
    initiationTimestamp?: string;
    connectedToSystemTimestamp?: string;
    disconnectTimestamp?: string;
  };
}

type IncomingEvent = CustomEventBridgeEvent | NativeContactEvent;

function isNativeContactEvent(event: IncomingEvent): event is NativeContactEvent {
  return typeof (event as NativeContactEvent).detail?.eventType === "string";
}

interface MetricPlan {
  metricName: string;
  dimensionField?: keyof CustomEventBridgeEvent["detail"];
}

// One entry per EventBridge rule this Lambda is subscribed to, for the
// CUSTOM bus's event shape. The native-event shape (INITIATED/DISCONNECTED)
// is handled separately in publishNativeMetric below, since its field
// names and metric-value derivation differ structurally, not just by
// detail-type string.
const METRIC_PLANS: Record<string, MetricPlan> = {
  "contact.transferred": {
    metricName: "ContactsTransferred",
    dimensionField: "queue",
  },
  "verification.completed": {
    metricName: "VerificationOutcome",
    dimensionField: "verificationStatus",
  },
};

async function publishCustomMetric(event: CustomEventBridgeEvent): Promise<void> {
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

  const dimensionValue = plan.dimensionField ? event.detail[plan.dimensionField] : undefined;

  await cloudwatch.send(
    new PutMetricDataCommand({
      Namespace: NAMESPACE,
      MetricData: [
        {
          MetricName: plan.metricName,
          Value: 1,
          Unit: "Count",
          Timestamp: new Date(event.detail.timestamp),
          ...(dimensionValue
            ? { Dimensions: [{ Name: plan.dimensionField as string, Value: String(dimensionValue) }] }
            : {}),
        },
      ],
    }),
  );
}

// Native Contact Events replacement for the old contact.initiated /
// contact.disconnected custom events. INITIATED -> ContactsInitiated
// (Count, same metric name as before). DISCONNECTED -> ContactDurationSeconds,
// computed from connectedToSystemTimestamp/disconnectTimestamp -- this is
// NEW, working functionality: the old custom flow-based DurationSeconds
// parameter was never actually populated by any flow action (see
// scripts/main-inbound-flow.ts's removed PublishDisconnected call site).
async function publishNativeMetric(event: NativeContactEvent): Promise<void> {
  const { eventType, contactId, disconnectTimestamp, connectedToSystemTimestamp } = event.detail;

  console.log(JSON.stringify({
    contactId,
    message: `Received native contact event ${eventType}`,
    detail: event.detail,
  }));

  if (eventType === "INITIATED") {
    await cloudwatch.send(
      new PutMetricDataCommand({
        Namespace: NAMESPACE,
        MetricData: [
          {
            MetricName: "ContactsInitiated",
            Value: 1,
            Unit: "Count",
            Timestamp: new Date(event.detail.initiationTimestamp ?? Date.now()),
          },
        ],
      }),
    );
    return;
  }

  if (eventType === "DISCONNECTED") {
    if (!disconnectTimestamp || !connectedToSystemTimestamp) {
      console.error(JSON.stringify({
        contactId,
        message: "DISCONNECTED event missing disconnectTimestamp or connectedToSystemTimestamp -- cannot compute duration",
      }));
      return;
    }

    const durationSeconds =
      (new Date(disconnectTimestamp).getTime() - new Date(connectedToSystemTimestamp).getTime()) / 1000;

    if (Number.isNaN(durationSeconds) || durationSeconds < 0) {
      console.error(JSON.stringify({
        contactId,
        message: `Computed invalid duration (${durationSeconds}s) from disconnectTimestamp="${disconnectTimestamp}" connectedToSystemTimestamp="${connectedToSystemTimestamp}"`,
      }));
      return;
    }

    await cloudwatch.send(
      new PutMetricDataCommand({
        Namespace: NAMESPACE,
        MetricData: [
          {
            MetricName: "ContactDurationSeconds",
            Value: durationSeconds,
            Unit: "Seconds",
            Timestamp: new Date(disconnectTimestamp),
          },
        ],
      }),
    );
    return;
  }

  console.error(JSON.stringify({ contactId, message: `No metric plan for native eventType "${eventType}"` }));
}

export const handler = async (event: IncomingEvent): Promise<void> => {
  try {
    if (isNativeContactEvent(event)) {
      await publishNativeMetric(event);
    } else {
      await publishCustomMetric(event);
    }
  } catch (error) {
    console.error(JSON.stringify({
      contactId: event.detail.contactId,
      message: "Failed to publish metric",
      error: String(error),
    }));
    throw error; // triggers Lambda's own async-invoke retry, then its on_failure destination (see modules/lambda-event-metric-subscriber's event_invoke_config) -- EventBridge's own rule-target retry/DLQ never sees this, it only covers handoff failures
  }
};
