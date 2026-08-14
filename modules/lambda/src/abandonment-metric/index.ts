import {
  ConnectClient,
  SearchContactsCommand,
  DescribeContactCommand,
  type ContactSearchSummary,
} from "@aws-sdk/client-connect";
import { CloudWatchLogsClient, FilterLogEventsCommand, type FilteredLogEvent } from "@aws-sdk/client-cloudwatch-logs";
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
// the table's TTL config is ever changed independently. Sourced from the
// DEDUP_TTL_SECONDS env var (set by Terraform from var.dedup_ttl_seconds)
// rather than derived here, so the dedup TTL is configurable in one place
// instead of hardcoded independently of the Terraform variable that already
// exists for it. Fallback of 1800 matches the Terraform variable's own
// default in case the env var is ever absent.
const DEDUP_TTL_SECONDS = Number(process.env.DEDUP_TTL_SECONDS ?? "1800");

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

// Bounds for the flow-log scan window around a contact's disconnect time.
// A generous window that covers the full flow log for a contact (from
// initiation through disconnect) while still bounding FilterLogEvents to a
// narrow slice of the log group instead of its entire retention period.
const FLOW_LOG_WINDOW_BEFORE_MS = 30 * 60 * 1000;
const FLOW_LOG_WINDOW_AFTER_MS = 60 * 1000;

async function fetchFlowLogEntries(contactId: string, disconnectTime: Date): Promise<FlowLogEntry[]> {
  // DescribeContact's DisconnectTimestamp is typed as a Date by the SDK, but
  // is not guaranteed to actually be a Date instance at runtime in every
  // path that constructs a ContactRecord (e.g. it can round-trip through a
  // plain object) -- normalize defensively via `new Date(...)` rather than
  // assuming `.getTime()` is always safe to call directly.
  const disconnectMs = new Date(disconnectTime).getTime();
  const startTime = disconnectMs - FLOW_LOG_WINDOW_BEFORE_MS;
  const endTime = disconnectMs + FLOW_LOG_WINDOW_AFTER_MS;

  const events: FilteredLogEvent[] = [];
  let nextToken: string | undefined;
  do {
    const result = await logs.send(
      new FilterLogEventsCommand({
        logGroupName: LOG_GROUP_NAME,
        filterPattern: `"${contactId}"`,
        startTime,
        endTime,
        nextToken,
      }),
    );
    events.push(...(result.events ?? []));
    nextToken = result.nextToken;
  } while (nextToken !== undefined);

  return events
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

  const contacts: ContactSearchSummary[] = [];
  let searchNextToken: string | undefined;
  do {
    const searchResult = await connect.send(
      new SearchContactsCommand({
        InstanceId: INSTANCE_ID,
        TimeRange: {
          Type: "DISCONNECT_TIMESTAMP",
          StartTime: startTime,
          EndTime: new Date(),
        },
        NextToken: searchNextToken,
      }),
    );
    contacts.push(...(searchResult.Contacts ?? []));
    searchNextToken = searchResult.NextToken;
  } while (searchNextToken !== undefined);

  for (const contact of contacts) {
    const contactId = contact.Id;
    if (!contactId) continue;

    if (await alreadyProcessed(contactId)) {
      continue;
    }

    const describeResult = await connect.send(
      new DescribeContactCommand({ InstanceId: INSTANCE_ID, ContactId: contactId }),
    );
    const disconnectTimestamp = describeResult.Contact?.DisconnectTimestamp;
    const record = {
      contactId,
      disconnectReason: describeResult.Contact?.DisconnectReason,
      disconnectTimestamp: disconnectTimestamp?.toString(),
    };

    if (!isAbandonmentCandidate(record) || disconnectTimestamp === undefined) {
      continue;
    }

    const flowLogEntries = await fetchFlowLogEntries(contactId, disconnectTimestamp);
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
