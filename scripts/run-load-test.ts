import {
  ConnectClient,
  ListTestCasesCommand,
  GetTestCaseExecutionSummaryCommand,
  StartTestCaseExecutionCommand,
} from "@aws-sdk/client-connect";

// ListTestCases has no server-side Name filter (same constraint documented
// in modules/connect/scripts/sync_test_case.sh) -- pages through NextToken,
// matching Name client-side.
export async function resolveTestCaseId(
  client: ConnectClient,
  instanceId: string,
  testCaseName: string,
): Promise<string> {
  let nextToken: string | undefined;

  do {
    const response = await client.send(
      new ListTestCasesCommand({
        InstanceId: instanceId,
        NextToken: nextToken,
      }),
    );

    const match = (response.TestCaseSummaryList ?? []).find((tc) => tc.Name === testCaseName);
    if (match?.Id) {
      return match.Id;
    }

    nextToken = response.NextToken;
  } while (nextToken);

  throw new Error(`No test case found with name "${testCaseName}" on instance ${instanceId}`);
}

export type TerminalStatus = "PASSED" | "FAILED" | "STOPPED";

export interface ExecutionResult {
  testCaseExecutionId: string;
  status: TerminalStatus | "TIMED_OUT" | "ERROR";
  error?: string;
}

const TERMINAL_STATUSES: ReadonlySet<string> = new Set(["PASSED", "FAILED", "STOPPED"]);

function realSleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// Polls GetTestCaseExecutionSummary at a fixed interval until the execution
// reaches a terminal status (PASSED/FAILED/STOPPED) or the client-side
// deadline elapses. The deadline is a safety net just past the API's own
// 5-minute hard timeout on test case executions -- if the API itself times
// an execution out, GetTestCaseExecutionSummary should surface a terminal
// status before this deadline fires in practice; TIMED_OUT is the harness's
// own fallback if that doesn't happen.
export async function pollExecution(
  client: ConnectClient,
  instanceId: string,
  testCaseId: string,
  testCaseExecutionId: string,
  options?: {
    pollIntervalMs?: number;
    deadlineMs?: number;
    sleep?: (ms: number) => Promise<void>;
  },
): Promise<ExecutionResult> {
  const pollIntervalMs = options?.pollIntervalMs ?? 5000;
  const deadlineMs = options?.deadlineMs ?? 330000;
  const sleep = options?.sleep ?? realSleep;

  const startedAt = Date.now();

  while (true) {
    try {
      const response = await client.send(
        new GetTestCaseExecutionSummaryCommand({
          InstanceId: instanceId,
          TestCaseId: testCaseId,
          TestCaseExecutionId: testCaseExecutionId,
        }),
      );

      const status = response.Status;
      if (status && TERMINAL_STATUSES.has(status)) {
        return { testCaseExecutionId, status: status as TerminalStatus };
      }
    } catch (err) {
      return {
        testCaseExecutionId,
        status: "ERROR",
        error: err instanceof Error ? err.message : String(err),
      };
    }

    if (Date.now() - startedAt >= deadlineMs) {
      return { testCaseExecutionId, status: "TIMED_OUT" };
    }

    await sleep(pollIntervalMs);
  }
}

// Fires `count` test case executions in chunks of at most `batchSize`
// (Promise.all per chunk, awaited fully before the next chunk starts) --
// no semaphore/queue abstraction, per the spec's v1 scope. A failure
// starting one execution is isolated into an ERROR result rather than
// rejecting the whole chunk, matching pollExecution's own error isolation
// so one bad execution never aborts the batch or the run.
export async function runBatches(
  client: ConnectClient,
  instanceId: string,
  testCaseId: string,
  count: number,
  options?: {
    batchSize?: number;
    pollOptions?: Parameters<typeof pollExecution>[4];
  },
): Promise<ExecutionResult[]> {
  const batchSize = options?.batchSize ?? 5;
  const results: ExecutionResult[] = [];

  for (let offset = 0; offset < count; offset += batchSize) {
    const chunkSize = Math.min(batchSize, count - offset);

    const chunkResults = await Promise.all(
      Array.from({ length: chunkSize }, async (): Promise<ExecutionResult> => {
        let testCaseExecutionId: string;

        try {
          const startResponse = await client.send(
            new StartTestCaseExecutionCommand({
              InstanceId: instanceId,
              TestCaseId: testCaseId,
            }),
          );

          if (!startResponse.TestCaseExecutionId) {
            return {
              testCaseExecutionId: "unknown",
              status: "ERROR",
              error: "StartTestCaseExecution returned no TestCaseExecutionId",
            };
          }

          testCaseExecutionId = startResponse.TestCaseExecutionId;
        } catch (err) {
          return {
            testCaseExecutionId: "unknown",
            status: "ERROR",
            error: err instanceof Error ? err.message : String(err),
          };
        }

        return pollExecution(client, instanceId, testCaseId, testCaseExecutionId, options?.pollOptions);
      }),
    );

    results.push(...chunkResults);
  }

  return results;
}

export function formatResults(results: ExecutionResult[]): string {
  const passed = results.filter((r) => r.status === "PASSED").length;
  const failed = results.filter((r) => r.status === "FAILED").length;
  const stopped = results.filter((r) => r.status === "STOPPED").length;
  const timedOut = results.filter((r) => r.status === "TIMED_OUT").length;
  const errored = results.filter((r) => r.status === "ERROR").length;

  const lines: string[] = [];
  lines.push(
    `${results.length} total: ${passed} passed, ${failed} failed, ${stopped} stopped, ${timedOut} timed out, ${errored} errored`,
  );
  lines.push("");

  for (const result of results) {
    const errorSuffix = result.error ? ` (${result.error})` : "";
    lines.push(`  ${result.testCaseExecutionId}: ${result.status}${errorSuffix}`);
  }

  return lines.join("\n");
}

export async function main(): Promise<void> {
  const [, , instanceId, testCaseName, countArg] = process.argv;

  if (!instanceId || !testCaseName) {
    console.error("Usage: npm run load-test -- <instance-id> <test-case-name> [count]");
    process.exitCode = 1;
    return;
  }

  const count = countArg ? Number.parseInt(countArg, 10) : 1;
  if (!Number.isInteger(count) || count < 1) {
    console.error(`Invalid count: "${countArg}" -- must be a positive integer`);
    process.exitCode = 1;
    return;
  }

  const client = new ConnectClient({ region: process.env.AWS_REGION ?? "us-east-1" });

  console.log(`Resolving test case "${testCaseName}" on instance ${instanceId}...`);
  let testCaseId: string;
  try {
    testCaseId = await resolveTestCaseId(client, instanceId, testCaseName);
  } catch (err) {
    console.error((err as Error).message);
    process.exitCode = 1;
    return;
  }
  console.log(`Resolved test case ID: ${testCaseId}`);

  console.log(`Running ${count} execution(s)...`);
  const results = await runBatches(client, instanceId, testCaseId, count);

  const summary = formatResults(results);
  console.log("");
  console.log(summary);

  const allPassed = results.every((r) => r.status === "PASSED");
  process.exitCode = allPassed ? 0 : 1;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  main().catch((err) => {
    console.error("Load test harness error:", (err as Error).message);
    process.exitCode = 1;
  });
}
