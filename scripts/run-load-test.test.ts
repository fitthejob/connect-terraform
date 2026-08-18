import { describe, it, expect, vi } from "vitest";
import type { ConnectClient } from "@aws-sdk/client-connect";
import { resolveTestCaseId } from "./run-load-test.js";

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
