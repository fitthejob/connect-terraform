import type { ConnectLambdaResponse } from "@connect-terraform/shared";

type QueueKey = "claims" | "benefits" | "authorizations" | "billing" | "general";

interface ConnectEvent {
  Details: {
    ContactId: string;
    ContactData: {
      Channel: string;
    };
    Parameters?: {
      Intent?: string;
      CustomerStatus?: string;
      VerificationStatus?: string;
    };
  };
}

// Intent name -> queue this repo's existing Lex bot produces
// (modules/lex/main.tf). No "general" intent exists; FallbackIntent and any
// unrecognized intent land on general by design.
const INTENT_TO_QUEUE: Record<string, QueueKey> = {
  ClaimsIntent: "claims",
  BenefitsIntent: "benefits",
  AuthorizationsIntent: "authorizations",
  BillingIntent: "billing",
  FallbackIntent: "general",
};

// Every specific queue overflows to general (the catch-all/human-staffed
// queue); general has no further overflow target.
const OVERFLOW_QUEUE: Record<QueueKey, QueueKey | undefined> = {
  claims: "general",
  benefits: "general",
  authorizations: "general",
  billing: "general",
  general: undefined,
};

function queueArn(queueKey: QueueKey): string {
  const arn = {
    claims: process.env.QUEUE_CLAIMS_ARN,
    benefits: process.env.QUEUE_BENEFITS_ARN,
    authorizations: process.env.QUEUE_AUTHORIZATIONS_ARN,
    billing: process.env.QUEUE_BILLING_ARN,
    general: process.env.QUEUE_GENERAL_ARN,
  }[queueKey];

  if (!arn) {
    throw new Error(`Missing queue ARN env var for queue "${queueKey}"`);
  }

  return arn;
}

export const handler = async (event: ConnectEvent): Promise<ConnectLambdaResponse> => {
  const contactId = event.Details.ContactId;
  const channel = event.Details.ContactData.Channel === "CHAT" ? "CHAT" : "VOICE";
  const intent = event.Details.Parameters?.Intent;
  const customerStatus = event.Details.Parameters?.CustomerStatus;

  try {
    // Suspended accounts always route to general with elevated priority,
    // overriding whatever intent was captured.
    if (customerStatus === "SUSPENDED") {
      return {
        queueArn: queueArn("general"),
        routingPriority: "HIGH",
        overflowQueueArn: "",
        channel,
      };
    }

    const queueKey = (intent ? INTENT_TO_QUEUE[intent] : undefined) ?? "general";
    const overflowKey = OVERFLOW_QUEUE[queueKey];

    return {
      queueArn: queueArn(queueKey),
      routingPriority: "STANDARD",
      overflowQueueArn: overflowKey ? queueArn(overflowKey) : "",
      channel,
    };
  } catch (error) {
    console.error(JSON.stringify({ contactId, message: "Routing decision failed, defaulting to general", error: String(error) }));
    return {
      queueArn: queueArn("general"),
      routingPriority: "STANDARD",
      overflowQueueArn: "",
      channel,
    };
  }
};
