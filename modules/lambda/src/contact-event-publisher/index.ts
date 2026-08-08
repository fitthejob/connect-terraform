import {
  EventBridgeClient,
  PutEventsCommand,
} from "@aws-sdk/client-eventbridge";
import type {
  ConnectLambdaResponse,
  ContactChannel,
  ContactCenterEvent,
} from "@connect-terraform/shared";

const eventBridge = new EventBridgeClient({ region: process.env.AWS_REGION });

// Only the flow-level lifecycle events -- customer.lookup.completed and
// verification.* are published inline by customer-lookup and
// sms-verification respectively, not through this generic publisher.
type FlowEventType = "contact.initiated" | "contact.transferred" | "contact.disconnected";
const FLOW_EVENT_TYPES: readonly FlowEventType[] = [
  "contact.initiated",
  "contact.transferred",
  "contact.disconnected",
];

interface ConnectEvent {
  Details: {
    ContactData: {
      ContactId: string;
      Channel: string;
    };
    Parameters?: {
      EventType?: string;
      CustomerId?: string;
      Queue?: string;
      Intent?: string;
      VerificationStatus?: string;
      DurationSeconds?: string;
    };
  };
}

function isFlowEventType(value: string | undefined): value is FlowEventType {
  return !!value && (FLOW_EVENT_TYPES as readonly string[]).includes(value);
}

export const handler = async (event: ConnectEvent): Promise<ConnectLambdaResponse> => {
  const contactId = event.Details.ContactData.ContactId;
  const channel: ContactChannel = event.Details.ContactData.Channel === "CHAT" ? "CHAT" : "VOICE";
  const params = event.Details.Parameters ?? {};

  if (!isFlowEventType(params.EventType)) {
    console.error(JSON.stringify({ contactId, message: `contact-event-publisher invoked with unrecognized EventType "${params.EventType}"` }));
    return { published: "false" };
  }

  const durationSeconds =
    params.EventType === "contact.disconnected" && params.DurationSeconds
      ? Number(params.DurationSeconds)
      : undefined;

  const detail: ContactCenterEvent["detail"] = {
    contactId,
    channel,
    timestamp: new Date().toISOString(),
    ...(params.CustomerId ? { customerId: params.CustomerId } : {}),
    ...(params.Queue ? { queue: params.Queue } : {}),
    ...(params.Intent ? { intent: params.Intent } : {}),
    ...(params.VerificationStatus ? { verificationStatus: params.VerificationStatus } : {}),
    ...(durationSeconds !== undefined && !Number.isNaN(durationSeconds) ? { durationSeconds } : {}),
  };

  try {
    await eventBridge.send(
      new PutEventsCommand({
        Entries: [
          {
            EventBusName: process.env.EVENT_BUS_NAME,
            Source: "contact-center.ivr",
            DetailType: params.EventType,
            Detail: JSON.stringify(detail),
          },
        ],
      }),
    );
    return { published: "true" };
  } catch (error) {
    console.error(JSON.stringify({ contactId, message: `Failed to publish ${params.EventType}`, error: String(error) }));
    return { published: "false" };
  }
};
