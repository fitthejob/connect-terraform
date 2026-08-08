import { randomInt } from "node:crypto";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  UpdateCommand,
} from "@aws-sdk/lib-dynamodb";
import { SNSClient, PublishCommand } from "@aws-sdk/client-sns";
import {
  EventBridgeClient,
  PutEventsCommand,
} from "@aws-sdk/client-eventbridge";
import type {
  ConnectLambdaResponse,
  ContactChannel,
  ContactCenterEvent,
} from "@connect-terraform/shared";

const MAX_ATTEMPTS = 3;
const TTL_SECONDS = 5 * 60;

const dynamo = DynamoDBDocumentClient.from(new DynamoDBClient({ region: process.env.AWS_REGION }));
const sns = new SNSClient({ region: process.env.AWS_REGION });
const eventBridge = new EventBridgeClient({ region: process.env.AWS_REGION });

interface ConnectEvent {
  Details: {
    ContactId: string;
    ContactData: {
      Channel: string;
    };
    Parameters?: {
      Action?: "send" | "verify";
      PhoneNumber?: string;
      Code?: string;
    };
  };
}

interface VerificationRecord {
  contactId: string;
  code: string;
  attempts: number;
  expiresAt: number;
}

function generateCode(): string {
  return randomInt(0, 1_000_000).toString().padStart(6, "0");
}

async function publishEvent(
  detailType: "verification.sent" | "verification.completed",
  contactId: string,
  channel: ContactChannel,
  verificationStatus?: string,
): Promise<void> {
  try {
    const detail: ContactCenterEvent["detail"] = {
      contactId,
      channel,
      timestamp: new Date().toISOString(),
      ...(verificationStatus ? { verificationStatus } : {}),
    };

    await eventBridge.send(
      new PutEventsCommand({
        Entries: [
          {
            EventBusName: process.env.EVENT_BUS_NAME,
            Source: "contact-center.ivr",
            DetailType: detailType,
            Detail: JSON.stringify(detail),
          },
        ],
      }),
    );
  } catch (error) {
    console.error(JSON.stringify({ contactId, message: `Failed to publish ${detailType}`, error: String(error) }));
  }
}

async function handleSend(
  contactId: string,
  channel: ContactChannel,
  phoneNumber: string | undefined,
): Promise<ConnectLambdaResponse> {
  if (!phoneNumber) {
    console.error(JSON.stringify({ contactId, message: "sms-verification send called without PhoneNumber parameter" }));
    return { verificationResult: "ERROR" };
  }

  const code = generateCode();
  const nowSeconds = Math.floor(Date.now() / 1000);
  const record: VerificationRecord = {
    contactId,
    code,
    attempts: 0,
    expiresAt: nowSeconds + TTL_SECONDS,
  };

  await dynamo.send(
    new PutCommand({
      TableName: process.env.VERIFICATION_TABLE_NAME,
      Item: record,
    }),
  );

  await sns.send(
    new PublishCommand({
      PhoneNumber: phoneNumber,
      Message: `Your verification code is ${code}. It expires in 5 minutes.`,
    }),
  );

  await publishEvent("verification.sent", contactId, channel);

  return { verificationResult: "SENT" };
}

async function handleVerify(
  contactId: string,
  channel: ContactChannel,
  submittedCode: string | undefined,
): Promise<ConnectLambdaResponse> {
  if (!submittedCode) {
    return { verificationResult: "FAILED", remainingAttempts: String(MAX_ATTEMPTS) };
  }

  const { Item } = await dynamo.send(
    new GetCommand({
      TableName: process.env.VERIFICATION_TABLE_NAME,
      Key: { contactId },
    }),
  );
  const record = Item as VerificationRecord | undefined;

  const nowSeconds = Math.floor(Date.now() / 1000);
  if (!record || record.expiresAt < nowSeconds) {
    await publishEvent("verification.completed", contactId, channel, "EXPIRED");
    return { verificationResult: "EXPIRED", remainingAttempts: "0" };
  }

  if (record.attempts >= MAX_ATTEMPTS) {
    await publishEvent("verification.completed", contactId, channel, "MAX_ATTEMPTS_EXCEEDED");
    return { verificationResult: "MAX_ATTEMPTS_EXCEEDED", remainingAttempts: "0" };
  }

  if (record.code === submittedCode) {
    await publishEvent("verification.completed", contactId, channel, "VERIFIED");
    return { verificationResult: "VERIFIED", remainingAttempts: String(MAX_ATTEMPTS - record.attempts) };
  }

  const { Attributes } = await dynamo.send(
    new UpdateCommand({
      TableName: process.env.VERIFICATION_TABLE_NAME,
      Key: { contactId },
      UpdateExpression: "SET attempts = attempts + :one",
      ExpressionAttributeValues: { ":one": 1 },
      ReturnValues: "ALL_NEW",
    }),
  );
  const updatedAttempts = (Attributes as VerificationRecord | undefined)?.attempts ?? record.attempts + 1;
  const remaining = Math.max(0, MAX_ATTEMPTS - updatedAttempts);

  if (remaining === 0) {
    await publishEvent("verification.completed", contactId, channel, "MAX_ATTEMPTS_EXCEEDED");
    return { verificationResult: "MAX_ATTEMPTS_EXCEEDED", remainingAttempts: "0" };
  }

  return { verificationResult: "FAILED", remainingAttempts: String(remaining) };
}

export const handler = async (event: ConnectEvent): Promise<ConnectLambdaResponse> => {
  // TEMPORARY debug logging -- investigating why DynamoDB PutCommand fails
  // with "Missing the key contactId in the item" on every real
  // Connect-triggered call despite direct aws lambda invoke succeeding
  // with an identical-looking payload shape. Remove once resolved.
  console.log(JSON.stringify({ message: "DEBUG raw event", event }));

  const contactId = event.Details.ContactId;
  const channel: ContactChannel = event.Details.ContactData.Channel === "CHAT" ? "CHAT" : "VOICE";
  const action = event.Details.Parameters?.Action;

  try {
    if (action === "send") {
      return await handleSend(contactId, channel, event.Details.Parameters?.PhoneNumber);
    }
    if (action === "verify") {
      return await handleVerify(contactId, channel, event.Details.Parameters?.Code);
    }

    console.error(JSON.stringify({ contactId, message: `sms-verification invoked with unrecognized action "${action}"` }));
    return { verificationResult: "ERROR" };
  } catch (error) {
    console.error(JSON.stringify({ contactId, message: "sms-verification failed", error: String(error) }));
    return { verificationResult: "ERROR" };
  }
};
