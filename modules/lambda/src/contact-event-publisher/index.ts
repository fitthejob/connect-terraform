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

// Only contact.transferred remains here -- contact.initiated and
// contact.disconnected were removed in favor of Amazon Connect's native
// EventBridge Contact Events (see modules/eventbridge-pipeline/main.tf's
// native_contact_events rule), which carry this data automatically with
// no flow-invoked Lambda call needed. customer.lookup.completed and
// verification.* remain published inline by customer-lookup and
// sms-verification respectively, not through this generic publisher.
type FlowEventType = "contact.transferred";
const FLOW_EVENT_TYPES: readonly FlowEventType[] = ["contact.transferred"];

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

  const detail: ContactCenterEvent["detail"] = {
    contactId,
    channel,
    timestamp: new Date().toISOString(),
    ...(params.CustomerId ? { customerId: params.CustomerId } : {}),
    ...(params.Queue ? { queue: params.Queue } : {}),
    ...(params.Intent ? { intent: params.Intent } : {}),
    ...(params.VerificationStatus ? { verificationStatus: params.VerificationStatus } : {}),
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
