import {
  DisconnectParticipantActionBuilder,
  FlowBuilder,
  InvokeFlowModuleActionBuilder,
  MessageParticipantActionBuilder,
  UpdateFlowLoggingBehaviorActionBuilder,
} from "@fitthejob/connect-flow-builder";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

// Disposable manual-test harness for Phase 3's acceptance criteria --
// "manually testing each module in isolation ... using real Phase 1 Lambda
// responses, not stubbed." Connect has no native way to invoke a contact
// flow module standalone (modules only run inside a real flow), so this
// wrapper calls both new modules back-to-back and speaks each one's result
// back over the call so the branch actually taken is directly audible.
//
// NOT applied via Terraform -- pushed out-of-band to Validation-Sandbox-dev
// via UpdateContactFlowContent, same pattern as
// scripts/main-inbound-flow.ts's sandbox-validation step. Never intended to
// be committed as the sandbox's permanent content; the sandbox reverts to
// its safe stub (immediate disconnect) on the next CI run.
const MODULE_CUSTOMER_LOOKUP_ID = requireEnv("MODULE_CUSTOMER_LOOKUP_ID");
const MODULE_SMS_VERIFICATION_ID = requireEnv("MODULE_SMS_VERIFICATION_ID");

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const disconnect = new DisconnectParticipantActionBuilder("Disconnect").build();

const announceVerificationResult = new MessageParticipantActionBuilder(
  "AnnounceVerificationResult",
)
  .text(
    "Verification result: $.Attributes.VerificationStatus. " +
      "End of test.",
  )
  .next("Disconnect")
  .onError("Disconnect")
  .build();

const invokeSmsVerification = new InvokeFlowModuleActionBuilder(
  "InvokeSmsVerification",
)
  .flowModuleId(MODULE_SMS_VERIFICATION_ID)
  .next("AnnounceVerificationResult")
  .onError("AnnounceVerificationResult")
  .build();

const announceCustomerLookupResult = new MessageParticipantActionBuilder(
  "AnnounceCustomerLookupResult",
)
  .text(
    "Customer lookup result: $.Attributes.CustomerStatus. " +
      "Now testing SMS verification. Please wait for your code.",
  )
  .next("InvokeSmsVerification")
  .onError("InvokeSmsVerification")
  .build();

const invokeCustomerLookup = new InvokeFlowModuleActionBuilder(
  "InvokeCustomerLookup",
)
  .flowModuleId(MODULE_CUSTOMER_LOOKUP_ID)
  .next("AnnounceCustomerLookupResult")
  .onError("AnnounceCustomerLookupResult")
  .build();

// Flow logging is per-flow, not instance-wide -- even though
// /aws/connect/mini-connect is enabled at the instance level, a flow only
// actually emits log entries once a "Set logging behavior" block runs.
// Enabling here propagates forward to both invoked modules for the rest of
// the contact segment (AWS-documented behavior), which is what makes this
// wrapper actually useful for live action-by-action debugging.
const enableLogging = new UpdateFlowLoggingBehaviorActionBuilder(
  "EnableLogging",
)
  .enabled()
  .next("InvokeCustomerLookup")
  .build();

const flow = new FlowBuilder("ModuleTestWrapper")
  .startWith(enableLogging)
  .add(invokeCustomerLookup)
  .add(announceCustomerLookupResult)
  .add(invokeSmsVerification)
  .add(announceVerificationResult)
  .add(disconnect)
  .build();

const definition = flow.toConnectDefinition();

const outputPath = process.env.FLOW_OUTPUT_PATH
  ? resolve(process.env.FLOW_OUTPUT_PATH)
  : resolve(
      dirname(fileURLToPath(import.meta.url)),
      "../modules/connect/contact_flows/module_test_wrapper.json",
    );

writeFileSync(outputPath, JSON.stringify(definition, null, 2));
console.log(`Wrote ${outputPath}`);
