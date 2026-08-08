import {
  CompareActionBuilder,
  EndFlowModuleExecutionActionBuilder,
  FlowBuilder,
  InvokeLambdaFunctionActionBuilder,
  UpdateContactAttributesActionBuilder,
  equalsCondition,
} from "@fitthejob/connect-flow-builder";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

// Injected at generation time -- dev/staging/prod each pass their own
// customer-lookup Lambda alias ARN, same pattern as
// scripts/main-inbound-flow.ts's LEX_BOT_ALIAS_ARN.
const CUSTOMER_LOOKUP_LAMBDA_ARN = requireEnv("CUSTOMER_LOOKUP_LAMBDA_ARN");

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const endModule = new EndFlowModuleExecutionActionBuilder("EndModule").build();

// customer-lookup's response lands under Connect's $.External namespace --
// customerStatus is always present (UNKNOWN/KNOWN/SUSPENDED); customerId
// and customerTier are only present on KNOWN/SUSPENDED (see
// modules/lambda/src/customer-lookup/index.ts).
const setKnownAttributes = new UpdateContactAttributesActionBuilder(
  "SetKnownAttributes",
)
  .targetCurrent()
  .attribute("CustomerStatus", "KNOWN")
  .attribute("CustomerId", "$.External.customerId")
  .attribute("CustomerTier", "$.External.customerTier")
  .next("EndModule")
  .onError("EndModule")
  .build();

const setSuspendedAttributes = new UpdateContactAttributesActionBuilder(
  "SetSuspendedAttributes",
)
  .targetCurrent()
  .attribute("CustomerStatus", "SUSPENDED")
  .attribute("CustomerId", "$.External.customerId")
  .attribute("CustomerTier", "$.External.customerTier")
  .next("EndModule")
  .onError("EndModule")
  .build();

const setUnknownAttributes = new UpdateContactAttributesActionBuilder(
  "SetUnknownAttributes",
)
  .targetCurrent()
  .attribute("CustomerStatus", "UNKNOWN")
  .next("EndModule")
  .onError("EndModule")
  .build();

const checkCustomerStatus = new CompareActionBuilder("CheckCustomerStatus")
  .comparisonValue("$.External.customerStatus")
  .when(equalsCondition("KNOWN"), "SetKnownAttributes")
  .when(equalsCondition("SUSPENDED"), "SetSuspendedAttributes")
  .when(equalsCondition("UNKNOWN"), "SetUnknownAttributes")
  .onError("SetUnknownAttributes")
  .build();

const invokeCustomerLookup = new InvokeLambdaFunctionActionBuilder(
  "InvokeCustomerLookup",
)
  .lambdaArn(CUSTOMER_LOOKUP_LAMBDA_ARN)
  .timeLimitSeconds(8)
  .next("CheckCustomerStatus")
  // A Lambda-invoke failure (throttle, timeout, unhandled exception) is
  // treated the same as an UNKNOWN lookup -- the flow degrades gracefully
  // rather than dead-ending the call.
  .onError("SetUnknownAttributes")
  .build();

const flow = new FlowBuilder("CustomerLookup")
  .startWith(invokeCustomerLookup)
  .add(checkCustomerStatus)
  .add(setKnownAttributes)
  .add(setSuspendedAttributes)
  .add(setUnknownAttributes)
  .add(endModule)
  .build();

// CONTACT_FLOW_MODULE content requires a Settings block with Success/Error
// transition declarations -- same patch as scripts/callback-offer-flow.ts.
const definition = flow.toConnectDefinition() as unknown as Record<string, unknown>;
if (!definition.Settings) {
  definition.Settings = {
    InputParameters: [],
    OutputParameters: [],
    Transitions: [
      { DisplayName: "Success", ReferenceName: "Success", Description: "" },
      { DisplayName: "Error", ReferenceName: "Error", Description: "" },
    ],
  };
}

const outputPath = process.env.FLOW_OUTPUT_PATH
  ? resolve(process.env.FLOW_OUTPUT_PATH)
  : resolve(
      dirname(fileURLToPath(import.meta.url)),
      "../modules/connect/contact_flows/module_customer_lookup.json",
    );

writeFileSync(outputPath, JSON.stringify(definition, null, 2));
console.log(`Wrote ${outputPath}`);
