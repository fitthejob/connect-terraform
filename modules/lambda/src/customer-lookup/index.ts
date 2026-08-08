import {
  CustomerProfilesClient,
  SearchProfilesCommand,
} from "@aws-sdk/client-customer-profiles";
import {
  EventBridgeClient,
  PutEventsCommand,
} from "@aws-sdk/client-eventbridge";
import type {
  ConnectLambdaResponse,
  ContactChannel,
  ContactCenterEvent,
} from "@connect-terraform/shared";

const customerProfiles = new CustomerProfilesClient({ region: process.env.AWS_REGION });
const eventBridge = new EventBridgeClient({ region: process.env.AWS_REGION });

interface ConnectEvent {
  Details: {
    ContactId: string;
    ContactData: {
      Channel: string;
      CustomerEndpoint?: { Address?: string };
    };
    Parameters?: { CustomerIdentifier?: string };
  };
}

async function publishLookupCompleted(
  contactId: string,
  channel: ContactChannel,
  customerId: string | undefined,
): Promise<void> {
  const detail: ContactCenterEvent["detail"] = {
    contactId,
    channel,
    timestamp: new Date().toISOString(),
    ...(customerId ? { customerId } : {}),
  };

  await eventBridge.send(
    new PutEventsCommand({
      Entries: [
        {
          EventBusName: process.env.EVENT_BUS_NAME,
          Source: "contact-center.ivr",
          DetailType: "customer.lookup.completed",
          Detail: JSON.stringify(detail),
        },
      ],
    }),
  );
}

export const handler = async (event: ConnectEvent): Promise<ConnectLambdaResponse> => {
  const contactId = event.Details.ContactId;
  const channel: ContactChannel = event.Details.ContactData.Channel === "CHAT" ? "CHAT" : "VOICE";

  // Voice looks up by the caller's ANI; chat has no phone number, so it
  // relies on an identifier the chat flow already collected and passed as
  // a contact flow parameter.
  const identifier =
    channel === "VOICE"
      ? event.Details.ContactData.CustomerEndpoint?.Address
      : event.Details.Parameters?.CustomerIdentifier;

  const domainName = process.env.CUSTOMER_PROFILES_DOMAIN;

  let result: ConnectLambdaResponse;
  let customerId: string | undefined;

  try {
    if (!identifier) {
      throw new Error("No customer identifier available on the contact");
    }

    // "PhoneNumber" and "_customerId" are not valid SearchProfiles KeyName
    // values -- Customer Profiles only recognizes a fixed set of predefined
    // keys (_phone, _email, _account, _profileId, _fullName, etc; confirmed
    // against a live domain, which rejects arbitrary field names with
    // "KeyName ... is not defined in the domain"). Voice's ANI maps to
    // _phone. Chat's key is still TODO -- no chat flow exists yet to confirm
    // what CustomerIdentifier actually holds or which predefined key it
    // should map to (see CLAUDE.md TODOs, 2026-08-08).
    if (channel === "CHAT") {
      throw new Error("Chat customer lookup KeyName not yet determined -- see CLAUDE.md TODOs");
    }

    const response = await customerProfiles.send(
      new SearchProfilesCommand({
        DomainName: domainName,
        KeyName: "_phone",
        Values: [identifier],
      }),
    );

    const profile = response.Items?.[0];

    if (!profile) {
      result = { customerStatus: "UNKNOWN" };
    } else if (profile.Attributes?.["accountStatus"] === "SUSPENDED") {
      customerId = profile.ProfileId;
      result = {
        customerStatus: "SUSPENDED",
        customerId: profile.ProfileId ?? "",
        customerTier: profile.Attributes?.["customerTier"] ?? "STANDARD",
      };
    } else {
      customerId = profile.ProfileId;
      result = {
        customerStatus: "KNOWN",
        customerId: profile.ProfileId ?? "",
        customerTier: profile.Attributes?.["customerTier"] ?? "STANDARD",
      };
    }
  } catch (error) {
    console.error(JSON.stringify({ contactId, message: "Customer lookup failed", error: String(error) }));
    result = { customerStatus: "UNKNOWN" };
  }

  try {
    await publishLookupCompleted(contactId, channel, customerId);
  } catch (error) {
    // Event publish failure should never fail the customer-facing lookup.
    console.error(JSON.stringify({ contactId, message: "Failed to publish customer.lookup.completed", error: String(error) }));
  }

  return result;
};
