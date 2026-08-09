import {
  CompareActionBuilder,
  ConnectParticipantWithLexBotActionBuilder,
  DisconnectParticipantActionBuilder,
  FlowBuilder,
  InvokeFlowModuleActionBuilder,
  InvokeLambdaFunctionActionBuilder,
  LoopActionBuilder,
  MessageParticipantActionBuilder,
  SetAgentWhisperFlowActionBuilder,
  TransferContactToQueueActionBuilder,
  UpdateContactAttributesActionBuilder,
  UpdateContactTargetQueueActionBuilder,
  equalsCondition,
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
const QUEUE_CLAIMS_ARN = requireEnv("QUEUE_CLAIMS_ARN");
const QUEUE_BENEFITS_ARN = requireEnv("QUEUE_BENEFITS_ARN");
const QUEUE_AUTHORIZATIONS_ARN = requireEnv("QUEUE_AUTHORIZATIONS_ARN");
const QUEUE_BILLING_ARN = requireEnv("QUEUE_BILLING_ARN");
const QUEUE_GENERAL_ARN = requireEnv("QUEUE_GENERAL_ARN");
const CALLBACK_OFFER_MODULE_ID = requireEnv("CALLBACK_OFFER_MODULE_ID");
const CUSTOMER_LOOKUP_MODULE_ID = requireEnv("CUSTOMER_LOOKUP_MODULE_ID");
const SMS_VERIFICATION_MODULE_ID = requireEnv("SMS_VERIFICATION_MODULE_ID");
const ROUTING_DECISION_LAMBDA_ARN = requireEnv("ROUTING_DECISION_LAMBDA_ARN");
const CONTACT_EVENT_PUBLISHER_LAMBDA_ARN = requireEnv(
  "CONTACT_EVENT_PUBLISHER_LAMBDA_ARN",
);
// UpdateContactEventHooks (SetAgentWhisperFlowActionBuilder) requires the
// flow's ARN, not its bare ID -- confirmed live, InvalidContactFlowException
// ("invalid resource") on the bare ID despite it being a real, valid flow.
const AGENT_WHISPER_FLOW_ARN = requireEnv("AGENT_WHISPER_FLOW_ARN");

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

// --- Event publishing (spec: initiation, post-verification, transfer,
// disconnect) -- all 4 invoke the same contact-event-publisher Lambda with a
// different EventType, mirroring module-sms-verification's SendCode/VerifyCode
// two-invokes-one-Lambda pattern.

function publishEvent(
  id: string,
  eventType: string,
  next: string,
  extraParams?: Record<string, string>,
) {
  let builder = new InvokeLambdaFunctionActionBuilder(id)
    .lambdaArn(CONTACT_EVENT_PUBLISHER_LAMBDA_ARN)
    .timeLimitSeconds(8)
    .invocationAttribute("EventType", eventType);
  for (const [key, value] of Object.entries(extraParams ?? {})) {
    builder = builder.invocationAttribute(key, value);
  }
  // A failed event publish must never block the call itself -- same
  // fire-and-forget tolerance as customer-lookup's own event publish
  // (modules/lambda/src/customer-lookup/index.ts's publishLookupCompleted
  // catch block).
  return builder.next(next).onError(next).build();
}

const publishInitiated = publishEvent(
  "PublishInitiated",
  "contact.initiated",
  "InvokeCustomerLookup",
);

const publishPostVerification = publishEvent(
  "PublishPostVerification",
  "verification.completed",
  "InvokeRoutingDecision",
  { VerificationStatus: "$.Attributes.VerificationStatus" },
);

// --- Customer lookup (always runs, every call) ---

const invokeCustomerLookup = new InvokeFlowModuleActionBuilder(
  "InvokeCustomerLookup",
)
  .flowModuleId(CUSTOMER_LOOKUP_MODULE_ID)
  .next("Greeting")
  .onError("Greeting")
  .build();

// --- Menu capture (Lex + DTMF fallback, unchanged from the prior flow) ---

const greeting = new MessageParticipantActionBuilder("Greeting")
  .text(
    "Thanks for calling. For claims, press or say 1. For benefits, press or say 2. " +
      "For authorizations, press or say 3. For billing, press or say 4.",
  )
  .next("RetryLoop")
  .build();

const retryLoop = new LoopActionBuilder("RetryLoop")
  .loopCount(2)
  .whenContinueLooping("MenuInput")
  .whenDoneLooping("SetIntentGeneral")
  .build();

const menuInput = new ConnectParticipantWithLexBotActionBuilder("MenuInput")
  .text(
    "For claims, press or say 1. For benefits, press or say 2. " +
      "For authorizations, press or say 3. For billing, press or say 4.",
  )
  .lexV2BotAliasArn(LEX_BOT_ALIAS_ARN)
  // Confirmed live: menu DTMF entry (pressing 1-4) wasn't reliably
  // recognized -- this action previously set no LexSessionAttributes at
  // all, unlike module-sms-verification's CollectCode action, which
  // explicitly enables both audio and DTMF input. ClaimsIntent/
  // BenefitsIntent/AuthorizationsIntent/BillingIntent have no slots to
  // scope to (unlike VerificationCodeIntent:VerificationCode), so the
  // wildcard intent:slot form (*:*) is used, which AWS documents as
  // applying the setting bot-wide/default when no specific intent/slot is
  // named.
  .sessionAttribute("x-amz-lex:allow-audio-input:*:*", "true")
  .sessionAttribute("x-amz-lex:allow-dtmf-input:*:*", "true")
  .whenIntentEquals("ClaimsIntent", "SetIntentClaims")
  .whenIntentEquals("BenefitsIntent", "SetIntentBenefits")
  .whenIntentEquals("AuthorizationsIntent", "SetIntentAuthorizations")
  .whenIntentEquals("BillingIntent", "SetIntentBilling")
  .onNoMatchingCondition("RetryPrompt")
  .onInputTimeLimitExceeded("RetryPrompt")
  .build();

const retryPrompt = new MessageParticipantActionBuilder("RetryPrompt")
  .text("We're sorry, we did not hear your choice.")
  .next("RetryLoop")
  .build();

// --- Set Intent per branch (this is the caller's raw menu selection, NOT
// yet the actual destination queue -- routing-decision below can override
// it, e.g. on a suspended account), then gate on whether the SELECTED
// intent's queue requires SMS verification (spec: Claims/Benefits/
// Authorizations/Billing are sensitive; General is not). Verification runs
// on intent, before routing-decision, matching the spec's own sequence
// ("Calls module-sms-verification for any account-sensitive routing path"
// precedes "Calls routing-decision Lambda with customer attributes and
// resolved intent"). ---

function setIntent(id: string, intent: string, next: string) {
  return new UpdateContactAttributesActionBuilder(id)
    .targetCurrent()
    .attribute("Intent", intent)
    .next(next)
    .onError(next)
    .build();
}

const setIntentClaims = setIntent(
  "SetIntentClaims",
  "ClaimsIntent",
  "InvokeSmsVerification",
);
const setIntentBenefits = setIntent(
  "SetIntentBenefits",
  "BenefitsIntent",
  "InvokeSmsVerification",
);
const setIntentAuthorizations = setIntent(
  "SetIntentAuthorizations",
  "AuthorizationsIntent",
  "InvokeSmsVerification",
);
const setIntentBilling = setIntent(
  "SetIntentBilling",
  "BillingIntent",
  "InvokeSmsVerification",
);
// General is not a sensitive queue -- skips SMS verification entirely,
// going straight to the routing-decision/event-publish/transfer sequence.
const setIntentGeneral = setIntent(
  "SetIntentGeneral",
  "FallbackIntent",
  "PublishPostVerification",
);

const invokeSmsVerification = new InvokeFlowModuleActionBuilder(
  "InvokeSmsVerification",
)
  .flowModuleId(SMS_VERIFICATION_MODULE_ID)
  .next("PublishPostVerification")
  .onError("PublishPostVerification")
  .build();

// --- Routing decision (spec: "Calls routing-decision Lambda with customer
// attributes and resolved intent"). This Lambda is the real routing
// authority -- its queueArn output is resolved to a queue ID below and IS
// the actual transfer target, not the caller's raw intent selection. This
// is what makes the Lambda's SUSPENDED-account override
// (modules/lambda/src/routing-decision/index.ts:65-72, forces general +
// HIGH priority regardless of intent) actually take effect end-to-end. ---

const invokeRoutingDecision = new InvokeLambdaFunctionActionBuilder(
  "InvokeRoutingDecision",
)
  .lambdaArn(ROUTING_DECISION_LAMBDA_ARN)
  .timeLimitSeconds(8)
  .invocationAttribute("Intent", "$.Attributes.Intent")
  .invocationAttribute("CustomerStatus", "$.Attributes.CustomerStatus")
  .invocationAttribute("VerificationStatus", "$.Attributes.VerificationStatus")
  .next("SetRoutingPriority")
  // A failed routing-decision invoke must still land the caller somewhere
  // -- default to General via the same attribute-setting path a resolved
  // "general" queueArn would take, rather than dead-ending the call.
  .onError("SetQueueNameGeneral")
  .build();

const setRoutingPriority = new UpdateContactAttributesActionBuilder(
  "SetRoutingPriority",
)
  .targetCurrent()
  .attribute("RoutingPriority", "$.External.routingPriority")
  .next("ResolveQueueArn")
  .onError("ResolveQueueArn")
  .build();

// --- Resolve routing-decision's queueArn output to this flow's queue-name
// vocabulary (Claims/Benefits/Authorizations/Billing/General), which both
// sets $.Attributes.Queue for the whisper flow and determines which
// queueTransferPair branch actually runs. UpdateContactTargetQueueActionBuilder
// needs a queue ID, not ARN -- CheckQueueForTransfer below still resolves
// name -> ID via the existing per-branch queueTransferPair structure, this
// step only resolves ARN -> name. ---

const resolveQueueArn = new CompareActionBuilder("ResolveQueueArn")
  .comparisonValue("$.External.queueArn")
  .when(equalsCondition(QUEUE_CLAIMS_ARN), "SetQueueNameClaims")
  .when(equalsCondition(QUEUE_BENEFITS_ARN), "SetQueueNameBenefits")
  .when(equalsCondition(QUEUE_AUTHORIZATIONS_ARN), "SetQueueNameAuthorizations")
  .when(equalsCondition(QUEUE_BILLING_ARN), "SetQueueNameBilling")
  .when(equalsCondition(QUEUE_GENERAL_ARN), "SetQueueNameGeneral")
  .onError("SetQueueNameGeneral")
  .build();

function setQueueName(id: string, queueName: string) {
  return new UpdateContactAttributesActionBuilder(id)
    .targetCurrent()
    .attribute("Queue", queueName)
    .next("PublishTransferred")
    .onError("PublishTransferred")
    .build();
}

const setQueueNameClaims = setQueueName("SetQueueNameClaims", "Claims");
const setQueueNameBenefits = setQueueName("SetQueueNameBenefits", "Benefits");
const setQueueNameAuthorizations = setQueueName(
  "SetQueueNameAuthorizations",
  "Authorizations",
);
const setQueueNameBilling = setQueueName("SetQueueNameBilling", "Billing");
const setQueueNameGeneral = setQueueName("SetQueueNameGeneral", "General");

const publishTransferred = publishEvent(
  "PublishTransferred",
  "contact.transferred",
  "AnnounceResolvedQueue",
  { Queue: "$.Attributes.Queue", Intent: "$.Attributes.Intent" },
);

// TEMPORARY test-diagnostic checkpoint for Phase 4 manual testing (see
// docs/superpowers/plans/2026-08-09-phase4-test-guide.md) -- states the
// REAL resolved destination queue right before transfer, which is the
// single highest-value confirmation point: it directly surfaces the
// suspended-account override (Test 4.1/4.2 in the guide expect this to say
// "General" even when the caller selected Claims/Benefits). Remove once the
// full test guide passes and Phase 4 is confirmed working end-to-end --
// this should never ship as permanent caller-facing content.
const announceResolvedQueue = new MessageParticipantActionBuilder(
  "AnnounceResolvedQueue",
)
  .text("Transferring to $.Attributes.Queue.")
  .next("CheckQueueForTransfer")
  .onError("CheckQueueForTransfer")
  .build();

// --- Queue transfer, whisper flow, and callback-offer-on-capacity, per
// queue. Same queueTransferPair shape as the prior flow, plus SetWhisperFlow
// wired in ahead of the transfer itself. ---

function queueTransferPair(
  setActionId: string,
  transferActionId: string,
  queueId: string,
) {
  const setCallbackQueueId = new UpdateContactAttributesActionBuilder(
    `${transferActionId}SetCallbackQueue`,
  )
    .targetCurrent()
    .attribute("CallbackQueueId", queueId)
    .next("InvokeCallbackOffer")
    .onError("InvokeCallbackOffer")
    .build();

  const setQueue = new UpdateContactTargetQueueActionBuilder(setActionId)
    .queueId(queueId)
    .next(`${transferActionId}SetWhisper`)
    .build();

  const setWhisper = new SetAgentWhisperFlowActionBuilder(
    `${transferActionId}SetWhisper`,
  )
    .whisperFlowId(AGENT_WHISPER_FLOW_ARN)
    .next(transferActionId)
    .onError(transferActionId)
    .build();

  const transfer = new TransferContactToQueueActionBuilder(transferActionId)
    .onError(`${transferActionId}SetCallbackQueue`, "QueueAtCapacity")
    .onError("Disconnect", "NoMatchingError")
    .build();

  return [setQueue, setWhisper, transfer, setCallbackQueueId];
}

const [setQueueClaims, setWhisperClaims, transferClaims, setCallbackQueueClaims] =
  queueTransferPair("SetQueueClaims", "TransferClaims", QUEUE_CLAIMS_ID);
const [setQueueBenefits, setWhisperBenefits, transferBenefits, setCallbackQueueBenefits] =
  queueTransferPair("SetQueueBenefits", "TransferBenefits", QUEUE_BENEFITS_ID);
const [
  setQueueAuthorizations,
  setWhisperAuthorizations,
  transferAuthorizations,
  setCallbackQueueAuthorizations,
] = queueTransferPair(
  "SetQueueAuthorizations",
  "TransferAuthorizations",
  QUEUE_AUTHORIZATIONS_ID,
);
const [setQueueBilling, setWhisperBilling, transferBilling, setCallbackQueueBilling] =
  queueTransferPair("SetQueueBilling", "TransferBilling", QUEUE_BILLING_ID);
const [setQueueGeneral, setWhisperGeneral, transferGeneral, setCallbackQueueGeneral] =
  queueTransferPair("SetQueueGeneral", "TransferGeneral", QUEUE_GENERAL_ID);

const checkQueueForTransfer = new CompareActionBuilder("CheckQueueForTransfer")
  .comparisonValue("$.Attributes.Queue")
  .when(equalsCondition("Claims"), "SetQueueClaims")
  .when(equalsCondition("Benefits"), "SetQueueBenefits")
  .when(equalsCondition("Authorizations"), "SetQueueAuthorizations")
  .when(equalsCondition("Billing"), "SetQueueBilling")
  .when(equalsCondition("General"), "SetQueueGeneral")
  .onError("SetQueueGeneral")
  .build();

const disconnect = new DisconnectParticipantActionBuilder("Disconnect").build();

// contact.disconnected fires right before the flow's own terminal
// Disconnect action -- DurationSeconds isn't available as a flow system
// attribute this phase (would need a SetContactAttribute at call start
// capturing a timestamp and computing elapsed time, out of scope here) so
// it's omitted; contact-event-publisher/index.ts already treats it as
// optional (only present when EventType is contact.disconnected AND
// DurationSeconds is explicitly passed).
const publishDisconnected = publishEvent(
  "PublishDisconnected",
  "contact.disconnected",
  "Disconnect",
);

const invokeCallbackOffer = new InvokeFlowModuleActionBuilder(
  "InvokeCallbackOffer",
)
  .flowModuleId(CALLBACK_OFFER_MODULE_ID)
  .next("PublishDisconnected")
  .onError("PublishDisconnected")
  .build();

const flow = new FlowBuilder("MainInbound")
  .startWith(publishInitiated)
  .add(invokeCustomerLookup)
  .add(greeting)
  .add(retryLoop)
  .add(menuInput)
  .add(retryPrompt)
  .add(setIntentClaims)
  .add(setIntentBenefits)
  .add(setIntentAuthorizations)
  .add(setIntentBilling)
  .add(setIntentGeneral)
  .add(invokeSmsVerification)
  .add(publishPostVerification)
  .add(invokeRoutingDecision)
  .add(setRoutingPriority)
  .add(resolveQueueArn)
  .add(setQueueNameClaims)
  .add(setQueueNameBenefits)
  .add(setQueueNameAuthorizations)
  .add(setQueueNameBilling)
  .add(setQueueNameGeneral)
  .add(publishTransferred)
  .add(announceResolvedQueue)
  .add(checkQueueForTransfer)
  .add(setQueueClaims)
  .add(setWhisperClaims)
  .add(transferClaims)
  .add(setCallbackQueueClaims)
  .add(setQueueBenefits)
  .add(setWhisperBenefits)
  .add(transferBenefits)
  .add(setCallbackQueueBenefits)
  .add(setQueueAuthorizations)
  .add(setWhisperAuthorizations)
  .add(transferAuthorizations)
  .add(setCallbackQueueAuthorizations)
  .add(setQueueBilling)
  .add(setWhisperBilling)
  .add(transferBilling)
  .add(setCallbackQueueBilling)
  .add(setQueueGeneral)
  .add(setWhisperGeneral)
  .add(transferGeneral)
  .add(setCallbackQueueGeneral)
  .add(invokeCallbackOffer)
  .add(publishDisconnected)
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
