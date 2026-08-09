import {
  CompareActionBuilder,
  ConnectParticipantWithLexBotActionBuilder,
  EndFlowModuleExecutionActionBuilder,
  FlowBuilder,
  InvokeLambdaFunctionActionBuilder,
  LoopActionBuilder,
  MessageParticipantActionBuilder,
  UpdateContactAttributesActionBuilder,
  equalsCondition,
} from "@fitthejob/connect-flow-builder";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

// Injected at generation time -- same pattern as
// scripts/module-customer-lookup-flow.ts.
const SMS_VERIFICATION_LAMBDA_ARN = requireEnv("SMS_VERIFICATION_LAMBDA_ARN");
const LEX_BOT_ALIAS_ARN = requireEnv("LEX_BOT_ALIAS_ARN");

function requireEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}

const endModule = new EndFlowModuleExecutionActionBuilder("EndModule").build();

// sms-verification's "send" action reads PhoneNumber from Parameters and
// texts a 6-digit code to it -- the caller's own ANI is the natural source
// for a voice contact. Chat has no ANI and needs its own PhoneNumber source,
// deferred to Phase 5 (chat flow) rather than solved here.
const sendCode = new InvokeLambdaFunctionActionBuilder("SendCode")
  .lambdaArn(SMS_VERIFICATION_LAMBDA_ARN)
  .timeLimitSeconds(8)
  .invocationAttribute("Action", "send")
  .invocationAttribute("PhoneNumber", "$.CustomerEndpoint.Address")
  .next("CollectCode")
  .onError("SendFailed")
  .build();

const sendFailed = new MessageParticipantActionBuilder("SendFailed")
  .text(
    "We're sorry, we weren't able to send a verification code. " +
      "We'll continue without verifying your identity.",
  )
  .next("EndModule")
  .onError("EndModule")
  .build();

// One action, both input methods: Lex V2 natively accepts speech AND DTMF
// for the same slot within a single ConnectParticipantWithLexBot
// interaction, toggled via LexSessionAttributes rather than needing two
// separate collection actions. allow-audio-input defaults to True; DTMF is
// enabled explicitly here to be certain rather than rely on an assumed
// bot-level default. See modules/lex/main.tf's VerificationCodeIntent +
// VerificationCode slot (AMAZON.AlphaNumeric, not AMAZON.Number -- preserves
// leading zeros in the code).
const collectCode = new ConnectParticipantWithLexBotActionBuilder(
  "CollectCode",
)
  .text("Please say or enter the 6-digit code we just sent you.")
  .lexV2BotAliasArn(LEX_BOT_ALIAS_ARN)
  .sessionAttribute(
    "x-amz-lex:allow-audio-input:VerificationCodeIntent:VerificationCode",
    "true",
  )
  .sessionAttribute(
    "x-amz-lex:allow-dtmf-input:VerificationCodeIntent:VerificationCode",
    "true",
  )
  // 45s -- generous relative to a real texted-code readback, deliberately
  // sized to also allow looking the code up via DynamoDB CLI during manual
  // testing (real SMS delivery is blocked on pending toll-free carrier
  // registration -- see CLAUDE.md TODOs, 2026-08-08). LexTimeoutSeconds.Text
  // (a connect-flow-builder method) is NOT a real Connect parameter --
  // confirmed via a live InvalidContactFlowModuleException regardless of
  // value type. The real, documented mechanism is entirely via
  // LexSessionAttributes: x-amz-lex:audio:start-timeout-ms controls how
  // long Lex waits before assuming the caller isn't going to speak (voice
  // input specifically; default 4000ms, max undocumented but under the
  // related max-length-ms's 55000ms ceiling).
  .sessionAttribute(
    "x-amz-lex:audio:start-timeout-ms:VerificationCodeIntent:VerificationCode",
    "45000",
  )
  .whenIntentEquals("VerificationCodeIntent", "VerifyCode")
  .onInputTimeLimitExceeded("RetryPrompt")
  .onNoMatchingCondition("RetryPrompt")
  .build();

// RetryLoop and sms-verification's MAX_ATTEMPTS (3, in DynamoDB) are two
// independent counters -- RetryLoop fires on EVERY trip back to CollectCode,
// including a malformed/no-match/timeout turn that never reached VerifyCode
// at all (no code was submitted, so the Lambda's own attempts counter in
// DynamoDB was never touched), while MAX_ATTEMPTS only increments on an
// actual submitted-and-wrong code. Confirmed live: a loopCount of 2 let a
// single garbled/no-match turn silently consume one of the caller's two
// real tries, so MaxAttemptsExceeded fired after only 2 genuine wrong-code
// attempts instead of the intended 3 -- the caller never got the number of
// tries the Lambda's own logic promised them. Set generously high (10) so
// this loop is purely a backstop against a caller who never produces valid
// input at all; the Lambda's MAX_ATTEMPTS_EXCEEDED (via
// CheckVerificationResult) is the real, authoritative limit on wrong-code
// attempts.
const retryLoop = new LoopActionBuilder("RetryLoop")
  .loopCount(10)
  .whenContinueLooping("CollectCode")
  .whenDoneLooping("MaxAttemptsExceeded")
  .build();

const retryPrompt = new MessageParticipantActionBuilder("RetryPrompt")
  .text("We're sorry, we didn't catch that.")
  .next("RetryLoop")
  .onError("RetryLoop")
  .build();

// Distinct from RetryPrompt: a genuinely wrong code (Lex understood the
// caller fine, sms-verification's Lambda just didn't match it) is a
// different situation from "we didn't catch that" (no-match/timeout on
// collection itself) and deserves its own message -- confirmed live, both
// branches previously routed through RetryPrompt's generic text, leaving no
// way for the caller to tell "you weren't understood" apart from "you were
// understood, but that code was wrong."
//
// $.External.* only exists in scope immediately after the Lambda invoke
// that produced it (used that way by CheckVerificationResult, right after
// VerifyCode) -- this repo has no precedent for referencing it from a later
// action, and module-test-wrapper-flow.ts's working pattern for
// interpolating a value into spoken text goes through a contact attribute
// ($.Attributes.*) instead. SetRemainingAttempts captures
// $.External.remainingAttempts into an attribute right after VerifyCode so
// IncorrectCodePrompt can read it the same, already-proven way.
const setRemainingAttempts = new UpdateContactAttributesActionBuilder(
  "SetRemainingAttempts",
)
  .targetCurrent()
  .attribute("RemainingAttempts", "$.External.remainingAttempts")
  .next("IncorrectCodePrompt")
  .onError("IncorrectCodePrompt")
  .build();

const incorrectCodePrompt = new MessageParticipantActionBuilder(
  "IncorrectCodePrompt",
)
  .text(
    "That code wasn't correct. You have $.Attributes.RemainingAttempts " +
      "attempts remaining.",
  )
  .next("RetryLoop")
  .onError("RetryLoop")
  .build();

const verifyCode = new InvokeLambdaFunctionActionBuilder("VerifyCode")
  .lambdaArn(SMS_VERIFICATION_LAMBDA_ARN)
  .timeLimitSeconds(8)
  .invocationAttribute("Action", "verify")
  .invocationAttribute("Code", "$.Lex.Slots.VerificationCode")
  .next("CheckVerificationResult")
  .onError("VerificationFailed")
  .build();

const setVerified = new UpdateContactAttributesActionBuilder("SetVerified")
  .targetCurrent()
  .attribute("VerificationStatus", "VERIFIED")
  .next("EndModule")
  .onError("EndModule")
  .build();

const verificationFailed = new MessageParticipantActionBuilder(
  "VerificationFailed",
)
  .text(
    "We're sorry, we weren't able to verify your identity. " +
      "We'll continue without verification.",
  )
  .next("SetFailedAttributes")
  .onError("SetFailedAttributes")
  .build();

const setFailedAttributes = new UpdateContactAttributesActionBuilder(
  "SetFailedAttributes",
)
  .targetCurrent()
  .attribute("VerificationStatus", "FAILED")
  .next("EndModule")
  .onError("EndModule")
  .build();

const maxAttemptsExceeded = new MessageParticipantActionBuilder(
  "MaxAttemptsExceeded",
)
  .text(
    "We're sorry, we weren't able to verify your identity after several " +
      "attempts. We'll continue without verification.",
  )
  .next("SetMaxAttemptsAttributes")
  .onError("SetMaxAttemptsAttributes")
  .build();

const setMaxAttemptsAttributes = new UpdateContactAttributesActionBuilder(
  "SetMaxAttemptsAttributes",
)
  .targetCurrent()
  .attribute("VerificationStatus", "MAX_ATTEMPTS_EXCEEDED")
  .next("EndModule")
  .onError("EndModule")
  .build();

const setExpiredAttributes = new UpdateContactAttributesActionBuilder(
  "SetExpiredAttributes",
)
  .targetCurrent()
  .attribute("VerificationStatus", "EXPIRED")
  .next("EndModule")
  .onError("EndModule")
  .build();

// sms-verification's verify action returns one of VERIFIED / FAILED /
// EXPIRED / MAX_ATTEMPTS_EXCEEDED / ERROR (see
// modules/lambda/src/sms-verification/index.ts). ERROR and any unmatched
// value fall through to VerificationFailed via the NoMatchingCondition
// error, same fallback as a Lambda invoke error.
const checkVerificationResult = new CompareActionBuilder(
  "CheckVerificationResult",
)
  .comparisonValue("$.External.verificationResult")
  .when(equalsCondition("VERIFIED"), "SetVerified")
  .when(equalsCondition("FAILED"), "SetRemainingAttempts")
  .when(equalsCondition("EXPIRED"), "SetExpiredAttributes")
  .when(equalsCondition("MAX_ATTEMPTS_EXCEEDED"), "MaxAttemptsExceeded")
  .onError("VerificationFailed")
  .build();

const flow = new FlowBuilder("SmsVerification")
  .startWith(sendCode)
  .add(sendFailed)
  .add(collectCode)
  .add(retryLoop)
  .add(retryPrompt)
  .add(setRemainingAttempts)
  .add(incorrectCodePrompt)
  .add(verifyCode)
  .add(checkVerificationResult)
  .add(setVerified)
  .add(verificationFailed)
  .add(setFailedAttributes)
  .add(maxAttemptsExceeded)
  .add(setMaxAttemptsAttributes)
  .add(setExpiredAttributes)
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
      "../modules/connect/contact_flows/module_sms_verification.json",
    );

writeFileSync(outputPath, JSON.stringify(definition, null, 2));
console.log(`Wrote ${outputPath}`);
