/**
 * Pushes a contact flow module's JSON content to a real contact flow module
 * on the Connect instance via UpdateContactFlowModuleContent. Connect
 * returns specific problem messages for invalid content -- the same errors
 * that would otherwise only surface after a failed terraform apply.
 *
 * Usage:
 *   npm run validate:flow-module -- <instance-id> <module-id> [content-path]
 *
 * content-path defaults to modules/connect/contact_flows/callback_offer.json
 * if omitted. Pass an absolute or repo-relative path to validate any other
 * generated module content.
 *
 * AWS credentials must already be configured in the environment.
 */

import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
import {
  ConnectClient,
  UpdateContactFlowModuleContentCommand,
} from "@aws-sdk/client-connect";

const [, , instanceId, moduleId, contentPathArg] = process.argv;

if (!instanceId || !moduleId) {
  console.error(
    "Usage: npm run validate:flow-module -- <instance-id> <module-id> [content-path]",
  );
  process.exit(1);
}

const contentPath = contentPathArg
  ? resolve(contentPathArg)
  : resolve(
      dirname(fileURLToPath(import.meta.url)),
      "../modules/connect/contact_flows/callback_offer.json",
    );
const content = readFileSync(contentPath, "utf-8");

const connect = new ConnectClient({ region: process.env.AWS_REGION ?? "us-east-1" });

async function main(): Promise<void> {
  console.log(`Pushing ${contentPath} to module ${moduleId}...\n`);

  try {
    await connect.send(
      new UpdateContactFlowModuleContentCommand({
        InstanceId: instanceId,
        ContactFlowModuleId: moduleId,
        Content: content,
      }),
    );
    console.log("Valid -- Connect accepted the content.");
  } catch (err: unknown) {
    const error = err as {
      name?: string;
      message?: string;
      problems?: Array<{ message: string }>;
      $metadata?: { httpStatusCode?: number };
    };

    if (error.$metadata?.httpStatusCode === 400) {
      console.log("Invalid -- Connect rejected the content:\n");
      const problems = error.problems?.map((p) => p.message) ?? [error.message ?? "Unknown error"];
      for (const problem of problems) {
        console.log(`  -> ${problem}`);
      }
      process.exit(1);
    }

    throw err;
  }
}

main().catch((err) => {
  console.error("\nValidator error:", (err as Error).message);
  process.exit(1);
});
