import {
  ConnectParticipantWithLexBotActionBuilder,
  DisconnectParticipantActionBuilder,
  FlowBuilder,
  LoopActionBuilder,
  MessageParticipantActionBuilder,
  TransferContactToQueueActionBuilder,
  UpdateContactTargetQueueActionBuilder,
} from "@fitthejob/connect-flow-builder";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

// Values are injected at generation time via environment variables so this
// script stays environment-agnostic (dev/staging/prod all call it with
// different queue IDs and a different Lex bot alias ARN).
const LEX_BOT_ALIAS_ARN = requireEnv("LEX_BOT_ALIAS_ARN");
const QUEUE_CLAIMS_ID = requireEnv("QUEUE_CLAIMS_ID");
const QUEUE_BENEFITS_ID = requireEnv("QUEUE_BENEFITS_ID");
const QUEUE_AUTHORIZATIONS_ID = requireEnv("QUEUE_AUTHORIZATIONS_ID");
const QUEUE_BILLING_ID = requireEnv("QUEUE_BILLING_ID");
const QUEUE_GENERAL_ID = requireEnv("QUEUE_GENERAL_ID");

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const greeting = new MessageParticipantActionBuilder("Greeting")
  .text(
    "Thanks for calling. For claims, press or say 1. For benefits, press or say 2. " +
      "For authorizations, press or say 3. For billing, press or say 4.",
  )
  .next("RetryLoop")
  .build();

// Native Connect Loop block: tracks the retry count for us. Two iterations
// means the caller gets two reprompts (three total attempts) before we give
// up and route to the general queue.
const retryLoop = new LoopActionBuilder("RetryLoop")
  .loopCount(2)
  .whenContinueLooping("MenuInput")
  .whenDoneLooping("SetQueueGeneral")
  .build();

const menuInput = new ConnectParticipantWithLexBotActionBuilder("MenuInput")
  .text(
    "For claims, press or say 1. For benefits, press or say 2. " +
      "For authorizations, press or say 3. For billing, press or say 4.",
  )
  .lexV2BotAliasArn(LEX_BOT_ALIAS_ARN)
  .whenIntentEquals("ClaimsIntent", "SetQueueClaims")
  .whenIntentEquals("BenefitsIntent", "SetQueueBenefits")
  .whenIntentEquals("AuthorizationsIntent", "SetQueueAuthorizations")
  .whenIntentEquals("BillingIntent", "SetQueueBilling")
  .onNoMatchingCondition("RetryPrompt")
  .onInputTimeLimitExceeded("RetryPrompt")
  .build();

const retryPrompt = new MessageParticipantActionBuilder("RetryPrompt")
  .text("We're sorry, we did not hear your choice.")
  .next("RetryLoop")
  .build();

function queueTransferPair(
  setActionId: string,
  transferActionId: string,
  queueId: string,
) {
  const setQueue = new UpdateContactTargetQueueActionBuilder(setActionId)
    .queueId(queueId)
    .next(transferActionId)
    .build();

  const transfer = new TransferContactToQueueActionBuilder(transferActionId)
    .onError("Disconnect", "QueueAtCapacity")
    .onError("Disconnect", "NoMatchingError")
    .build();

  return [setQueue, transfer];
}

const [setQueueClaims, transferClaims] = queueTransferPair(
  "SetQueueClaims",
  "TransferClaims",
  QUEUE_CLAIMS_ID,
);
const [setQueueBenefits, transferBenefits] = queueTransferPair(
  "SetQueueBenefits",
  "TransferBenefits",
  QUEUE_BENEFITS_ID,
);
const [setQueueAuthorizations, transferAuthorizations] = queueTransferPair(
  "SetQueueAuthorizations",
  "TransferAuthorizations",
  QUEUE_AUTHORIZATIONS_ID,
);
const [setQueueBilling, transferBilling] = queueTransferPair(
  "SetQueueBilling",
  "TransferBilling",
  QUEUE_BILLING_ID,
);
const [setQueueGeneral, transferGeneral] = queueTransferPair(
  "SetQueueGeneral",
  "TransferGeneral",
  QUEUE_GENERAL_ID,
);

const disconnect = new DisconnectParticipantActionBuilder("Disconnect").build();

const flow = new FlowBuilder("MainInbound")
  .startWith(greeting)
  .add(retryLoop)
  .add(menuInput)
  .add(retryPrompt)
  .add(setQueueClaims)
  .add(transferClaims)
  .add(setQueueBenefits)
  .add(transferBenefits)
  .add(setQueueAuthorizations)
  .add(transferAuthorizations)
  .add(setQueueBilling)
  .add(transferBilling)
  .add(setQueueGeneral)
  .add(transferGeneral)
  .add(disconnect)
  .build();

const outputPath = process.env.FLOW_OUTPUT_PATH
  ? resolve(process.env.FLOW_OUTPUT_PATH)
  : resolve(
      dirname(fileURLToPath(import.meta.url)),
      "../modules/connect/contact_flows/main_inbound.json",
    );

writeFileSync(outputPath, flow.toJsonString());
console.log(`Wrote ${outputPath}`);
