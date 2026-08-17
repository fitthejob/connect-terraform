// Event schema for the contact-center-events EventBridge bus. See
// docs/superpowers/specs/contact-center-prototype-spec.md's "Event Schema"
// section -- this is the typed version of that table, kept in sync by hand
// since there is no runtime schema validation for this prototype.

export type ContactCenterDetailType =
  | "contact.transferred"
  | "customer.lookup.completed"
  | "verification.sent"
  | "verification.completed";

export type ContactChannel = "VOICE" | "CHAT";

export interface ContactCenterEventDetail {
  contactId: string;
  customerId?: string;
  channel: ContactChannel;
  queue?: string;
  intent?: string;
  verificationStatus?: string;
  timestamp: string;
}

export interface ContactCenterEvent {
  detailType: ContactCenterDetailType;
  version: "1.0";
  source: "contact-center.ivr";
  detail: ContactCenterEventDetail;
}

// Connect Lambda response contract: every value returned to a contact flow
// must be a flat string map (Connect coerces non-string values and rejects
// nested objects/arrays), matching the pattern already used by
// modules/lambda/src/eligibility-check/index.ts.
export type ConnectLambdaResponse = Record<string, string>;
