import {
  ConnectClient,
  ListTestCasesCommand,
  GetTestCaseExecutionSummaryCommand,
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
