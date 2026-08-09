import {
  CompareActionBuilder,
  DisconnectParticipantActionBuilder,
  FlowBuilder,
  MessageParticipantActionBuilder,
  equalsCondition,
} from "@fitthejob/connect-flow-builder";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

// Agent-facing whisper: plays only to the agent the instant a transferred
// call connects, never heard by the caller. One shared flow branching on
// contact attributes (rather than one flow per queue) -- less Terraform/CI
// surface, single place to maintain the whisper copy. Attributes read here
// are all set earlier in the call by main-inbound-flow.ts (Queue) and the
// module-customer-lookup / module-sms-verification flow modules
// (CustomerStatus, CustomerTier, VerificationStatus).

const disconnect = new DisconnectParticipantActionBuilder("Disconnect").build();

function whisperMessage(id: string, text: string, next: string) {
  return new MessageParticipantActionBuilder(id)
    .text(text)
    .next(next)
    .onError(next)
    .build();
}

// VerificationStatus branch -- only reachable for sensitive queues, since
// General never invokes module-sms-verification (see main-inbound-flow.ts).
// Absent entirely for General calls, so CheckVerification's onError/no-match
// path covers that case too, not just a genuine Lambda/module failure.
const sayVerified = whisperMessage(
  "SayVerified",
  "Identity verified.",
  "CheckCustomerStatus",
);
const sayNotVerified = whisperMessage(
  "SayNotVerified",
  "Caller was not able to verify their identity -- proceed with standard authentication.",
  "CheckCustomerStatus",
);

const checkVerification = new CompareActionBuilder("CheckVerification")
  .comparisonValue("$.Attributes.VerificationStatus")
  .when(equalsCondition("VERIFIED"), "SayVerified")
  .when(equalsCondition("FAILED"), "SayNotVerified")
  .when(equalsCondition("EXPIRED"), "SayNotVerified")
  .when(equalsCondition("MAX_ATTEMPTS_EXCEEDED"), "SayNotVerified")
  // No VerificationStatus at all (General queue, sms-verification never
  // invoked) lands here too -- same as a real absence of verification.
  .onError("CheckCustomerStatus")
  .build();

const sayKnownTier = whisperMessage(
  "SayKnownTier",
  "Returning customer, tier: $.Attributes.CustomerTier.",
  "CheckQueue",
);
const saySuspended = whisperMessage(
  "SaySuspended",
  "Caller's account is flagged suspended -- handle per suspended-account procedure.",
  "CheckQueue",
);
const sayUnknownCustomer = whisperMessage(
  "SayUnknownCustomer",
  "New or unrecognized caller.",
  "CheckQueue",
);

const checkCustomerStatus = new CompareActionBuilder("CheckCustomerStatus")
  .comparisonValue("$.Attributes.CustomerStatus")
  .when(equalsCondition("KNOWN"), "SayKnownTier")
  .when(equalsCondition("SUSPENDED"), "SaySuspended")
  .when(equalsCondition("UNKNOWN"), "SayUnknownCustomer")
  .onError("SayUnknownCustomer")
  .build();

const sayClaims = whisperMessage("SayClaims", "Claims call.", "Disconnect");
const sayBenefits = whisperMessage("SayBenefits", "Benefits call.", "Disconnect");
const sayAuthorizations = whisperMessage(
  "SayAuthorizations",
  "Authorizations call.",
  "Disconnect",
);
const sayBilling = whisperMessage("SayBilling", "Billing call.", "Disconnect");
const sayGeneral = whisperMessage("SayGeneral", "General inquiry.", "Disconnect");

const checkQueue = new CompareActionBuilder("CheckQueue")
  .comparisonValue("$.Attributes.Queue")
  .when(equalsCondition("Claims"), "SayClaims")
  .when(equalsCondition("Benefits"), "SayBenefits")
  .when(equalsCondition("Authorizations"), "SayAuthorizations")
  .when(equalsCondition("Billing"), "SayBilling")
  .when(equalsCondition("General"), "SayGeneral")
  .onError("SayGeneral")
  .build();

const flow = new FlowBuilder("AgentWhisper")
  .startWith(checkVerification)
  .add(sayVerified)
  .add(sayNotVerified)
  .add(checkCustomerStatus)
  .add(sayKnownTier)
  .add(saySuspended)
  .add(sayUnknownCustomer)
  .add(checkQueue)
  .add(sayClaims)
  .add(sayBenefits)
  .add(sayAuthorizations)
  .add(sayBilling)
  .add(sayGeneral)
  .add(disconnect)
  .build();

const outputPath = process.env.FLOW_OUTPUT_PATH
  ? resolve(process.env.FLOW_OUTPUT_PATH)
  : resolve(
      dirname(fileURLToPath(import.meta.url)),
      "../modules/connect/contact_flows/agent_whisper.json",
    );

writeFileSync(outputPath, flow.toJsonString());
console.log(`Wrote ${outputPath}`);
