import { ConnectClient, SearchContactsCommand, DescribeContactCommand } from "@aws-sdk/client-connect";
import { CloudWatchLogsClient, FilterLogEventsCommand } from "@aws-sdk/client-cloudwatch-logs";
import { CloudWatchClient, PutMetricDataCommand, type PutMetricDataCommandInput } from "@aws-sdk/client-cloudwatch";
import { DynamoDBClient } from "@aws-sdk/client-dynamodb";
import { DynamoDBDocumentClient, GetCommand, PutCommand } from "@aws-sdk/lib-dynamodb";
import { matchRegistry } from "./registry";
import { findLastUnpairedEntry, type FlowLogEntry } from "./unpaired-block";
import { isAbandonmentCandidate } from "./ctr-filter";
import { shouldProcess } from "./dedup";
import { buildMetricPayload } from "./metric-payload";

const connect = new ConnectClient({ region: process.env.AWS_REGION });
const logs = new CloudWatchLogsClient({ region: process.env.AWS_REGION });
const cloudwatch = new CloudWatchClient({ region: process.env.AWS_REGION });
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: process.env.AWS_REGION }));

const INSTANCE_ID = process.env.INSTANCE_ID!;
const LOG_GROUP_NAME = process.env.LOG_GROUP_NAME!;
const DEDUP_TABLE_NAME = process.env.DEDUP_TABLE_NAME!;
const METRIC_NAMESPACE = process.env.METRIC_NAMESPACE!;
const STAGE = process.env.STAGE!;
const LOOKBACK_MINUTES = Number(process.env.LOOKBACK_MINUTES ?? "6");

// DynamoDB TTL is set by Terraform on the table itself (see
// modules/lambda-abandonment-metric/main.tf); this Lambda only needs to
// write a plausible expiresAt so records don't accumulate indefinitely if
// the table's TTL config is ever changed independently.
const DEDUP_TTL_SECONDS = LOOKBACK_MINUTES * 60 * 5; // 5x safety multiplier, per the design

async function alreadyProcessed(contactId: string): Promise<boolean> {
  const result = await ddb.send(
    new GetCommand({ TableName: DEDUP_TABLE_NAME, Key: { contactId } }),
  );
  return result.Item !== undefined;
}

async function markProcessed(contactId: string): Promise<void> {
  const nowSeconds = Math.floor(Date.now() / 1000);
  await ddb.send(
    new PutCommand({
      TableName: DEDUP_TABLE_NAME,
      Item: { contactId, expiresAt: nowSeconds + DEDUP_TTL_SECONDS },
    }),
  );
}

async function fetchFlowLogEntries(contactId: string): Promise<FlowLogEntry[]> {
  const result = await logs.send(
    new FilterLogEventsCommand({
      logGroupName: LOG_GROUP_NAME,
      filterPattern: `"${contactId}"`,
    }),
  );
  return (result.events ?? [])
    .map((e) => {
      try {
        return JSON.parse(e.message ?? "{}") as FlowLogEntry;
      } catch {
        return undefined;
      }
    })
    .filter((e): e is FlowLogEntry => e !== undefined);
}

export const handler = async (): Promise<void> => {
  const lookbackMs = LOOKBACK_MINUTES * 60 * 1000;
  const startTime = new Date(Date.now() - lookbackMs);

  const searchResult = await connect.send(
    new SearchContactsCommand({
      InstanceId: INSTANCE_ID,
      TimeRange: {
        Type: "DISCONNECT_TIMESTAMP",
        StartTime: startTime,
        EndTime: new Date(),
      },
    }),
  );

  for (const contact of searchResult.Contacts ?? []) {
    const contactId = contact.Id;
    if (!contactId) continue;

    if (await alreadyProcessed(contactId)) {
      continue;
    }

    const describeResult = await connect.send(
      new DescribeContactCommand({ InstanceId: INSTANCE_ID, ContactId: contactId }),
    );
    const record = {
      contactId,
      disconnectReason: describeResult.Contact?.DisconnectReason,
      disconnectTimestamp: describeResult.Contact?.DisconnectTimestamp?.toString(),
    };

    if (!isAbandonmentCandidate(record)) {
      continue;
    }

    const flowLogEntries = await fetchFlowLogEntries(contactId);
    const unpaired = findLastUnpairedEntry(flowLogEntries);

    if (unpaired) {
      const registryMatch = matchRegistry(unpaired.ContactFlowName, unpaired.Identifier);
      if (registryMatch && shouldProcess(false)) {
        // buildMetricPayload's return type deliberately keeps Unit as a
        // plain string (see metric-payload.ts) so that module stays
        // decoupled from the AWS SDK's types and independently unit
        // testable. Widen to the SDK's PutMetricDataCommandInput here at
        // the one real AWS-call boundary instead of importing SDK types
        // into the pure logic module.
        const payload = buildMetricPayload(registryMatch, METRIC_NAMESPACE, STAGE);
        await cloudwatch.send(new PutMetricDataCommand(payload as PutMetricDataCommandInput));
      }
    }

    await markProcessed(contactId);
  }
};
