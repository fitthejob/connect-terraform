import {
  CreateCallbackContactActionBuilder,
  EndFlowModuleExecutionActionBuilder,
  FlowBuilder,
  GetParticipantInputActionBuilder,
  MessageParticipantActionBuilder,
  equalsCondition,
} from "@fitthejob/connect-flow-builder";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

// The queue ID this module schedules the callback against is read from a
// contact attribute set by the invoking flow immediately before
// InvokeFlowModule — this module never receives its own queue ID as a
// build-time value, since it is shared across every queue that can be at
// capacity. Keep this key in sync with scripts/main-inbound-flow.ts's
// UpdateContactAttributesActionBuilder call.
const CALLBACK_QUEUE_ID_ATTRIBUTE = "CallbackQueueId";

const endModule = new EndFlowModuleExecutionActionBuilder("EndModule").build();

const scheduleCallback = new CreateCallbackContactActionBuilder(
  "ScheduleCallback",
)
  .queueId(`$.Attributes.${CALLBACK_QUEUE_ID_ATTRIBUTE}`)
  .initialCallDelaySeconds(1)
  .maximumConnectionAttempts(3)
  .retryDelaySeconds(60)
  .next("EndModule")
  .onError("EndModule")
  .build();

const getCallbackChoice = new GetParticipantInputActionBuilder(
  "GetCallbackChoice",
)
  .text("Press 1 for a callback, or stay on the line to continue holding.")
  .inputTimeLimitSeconds(10)
  .when(equalsCondition("1"), "ScheduleCallback")
  .next("EndModule")
  .onError("EndModule", "NoMatchingCondition")
  .onError("EndModule", "InputTimeLimitExceeded")
  .onError("EndModule")
  .build();

const offerCallback = new MessageParticipantActionBuilder("OfferCallback")
  .text(
    "All agents are currently busy. Press 1 to receive a callback instead " +
      "of waiting, or stay on the line to continue holding.",
  )
  .next("GetCallbackChoice")
  .onError("GetCallbackChoice")
  .build();

const flow = new FlowBuilder("CallbackOffer")
  .startWith(offerCallback)
  .add(getCallbackChoice)
  .add(scheduleCallback)
  .add(endModule)
  .build();

// CONTACT_FLOW_MODULE content requires a Settings block with Success/Error
// transition declarations. Connect rejects the content without it even
// though it's not needed at runtime. Mirrors the same patch in
// connect-flow-builder's render-flow-catalog.ts.
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
      "../modules/connect/contact_flows/callback_offer.json",
    );

writeFileSync(outputPath, JSON.stringify(definition, null, 2));
console.log(`Wrote ${outputPath}`);
