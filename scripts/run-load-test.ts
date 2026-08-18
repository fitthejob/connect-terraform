import { ConnectClient, ListTestCasesCommand } from "@aws-sdk/client-connect";

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
