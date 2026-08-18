import { describe, it, expect, vi } from "vitest";
import type { ConnectClient } from "@aws-sdk/client-connect";
import { resolveTestCaseId, pollExecution } from "./run-load-test.js";

function fakeClient(pages: Array<{ TestCaseSummaryList: Array<{ Id?: string; Name?: string }>; NextToken?: string }>): ConnectClient {
  let call = 0;
  return {
    send: vi.fn().mockImplementation(async () => {
      const page = pages[call];
      call += 1;
      return page;
    }),
  } as unknown as ConnectClient;
}

describe("resolveTestCaseId", () => {
  it("returns the Id of the matching test case on the first page", async () => {
    const client = fakeClient([
      { TestCaseSummaryList: [{ Id: "tc-1", Name: "smoke-test" }, { Id: "tc-2", Name: "other-test" }] },
    ]);

    const id = await resolveTestCaseId(client, "instance-1", "smoke-test");

    expect(id).toBe("tc-1");
  });

  it("pages through NextToken to find a match on a later page", async () => {
    const client = fakeClient([
      { TestCaseSummaryList: [{ Id: "tc-1", Name: "other-test" }], NextToken: "page-2" },
      { TestCaseSummaryList: [{ Id: "tc-2", Name: "smoke-test" }] },
    ]);

    const id = await resolveTestCaseId(client, "instance-1", "smoke-test");

    expect(id).toBe("tc-2");
    expect(client.send).toHaveBeenCalledTimes(2);
  });

  it("throws a clear error when no test case matches after exhausting pagination", async () => {
    const client = fakeClient([
      { TestCaseSummaryList: [{ Id: "tc-1", Name: "other-test" }] },
    ]);

    await expect(resolveTestCaseId(client, "instance-1", "nonexistent-test")).rejects.toThrow(
      /No test case found with name/,
    );
  });

  it("skips a page with an empty TestCaseSummaryList without erroring", async () => {
    const client = fakeClient([
      { TestCaseSummaryList: [], NextToken: "page-2" },
      { TestCaseSummaryList: [{ Id: "tc-2", Name: "smoke-test" }] },
    ]);

    const id = await resolveTestCaseId(client, "instance-1", "smoke-test");

    expect(id).toBe("tc-2");
  });
});

describe("pollExecution", () => {
  const instantSleep = async (_ms: number): Promise<void> => {};

  it("returns immediately when the first poll is already terminal", async () => {
    const client = {
      send: vi.fn().mockResolvedValue({ Status: "PASSED" }),
    } as unknown as ConnectClient;

    const result = await pollExecution(client, "instance-1", "tc-1", "exec-1", { sleep: instantSleep });

    expect(result).toEqual({ testCaseExecutionId: "exec-1", status: "PASSED" });
    expect(client.send).toHaveBeenCalledTimes(1);
  });

  it("polls through non-terminal statuses until a terminal one arrives", async () => {
    const statuses = ["INITIATED", "IN_PROGRESS", "IN_PROGRESS", "FAILED"];
    let call = 0;
    const client = {
      send: vi.fn().mockImplementation(async () => {
        const status = statuses[call];
        call += 1;
        return { Status: status };
      }),
    } as unknown as ConnectClient;

    const result = await pollExecution(client, "instance-1", "tc-1", "exec-1", { sleep: instantSleep });

    expect(result).toEqual({ testCaseExecutionId: "exec-1", status: "FAILED" });
    expect(client.send).toHaveBeenCalledTimes(4);
  });

  it("resolves with TIMED_OUT status when the deadline elapses before a terminal status", async () => {
    // Simulate elapsed time via a sleep stub that advances a fake clock,
    // since pollExecution measures elapsed time with Date.now() internally.
    let fakeNow = 0;
    vi.spyOn(Date, "now").mockImplementation(() => fakeNow);
    const advancingSleep = async (ms: number): Promise<void> => {
      fakeNow += ms;
    };

    const client = {
      send: vi.fn().mockResolvedValue({ Status: "IN_PROGRESS" }),
    } as unknown as ConnectClient;

    const result = await pollExecution(client, "instance-1", "tc-1", "exec-1", {
      sleep: advancingSleep,
      pollIntervalMs: 100000,
      deadlineMs: 250000,
    });

    expect(result.status).toBe("TIMED_OUT");
    expect(result.testCaseExecutionId).toBe("exec-1");

    vi.restoreAllMocks();
  });

  it("isolates a per-poll API error into an ERROR result rather than throwing", async () => {
    const client = {
      send: vi.fn().mockRejectedValue(new Error("ThrottlingException")),
    } as unknown as ConnectClient;

    const result = await pollExecution(client, "instance-1", "tc-1", "exec-1", { sleep: instantSleep });

    expect(result.status).toBe("ERROR");
    expect(result.error).toContain("ThrottlingException");
  });
});
