import {
  TestCaseBuilder,
  TestInitiatedEventBuilder,
  EndTestActionBuilder,
} from "@fitthejob/connect-flow-builder";
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";

// Minimal legal test case: prove the full pipeline (builder -> JSON ->
// null_resource sync -> real Connect test case) works end to end. Not
// meant to simulate rich caller behavior -- see CLAUDE.md's Phase 3 TODOs
// for richer scenarios once Load-Test-Sandbox has real flow content loaded.
const testInitiated = new TestInitiatedEventBuilder().build();
const endTest = new EndTestActionBuilder("EndTest").build();

const builtTestCase = new TestCaseBuilder()
  .add({
    Identifier: "Start",
    Event: testInitiated,
    Usage: { Type: "EXACTLY" },
    Actions: [endTest],
    Transitions: { NextObservations: [] },
  })
  .build();

const outputPath = process.env.TEST_CASE_OUTPUT_PATH
  ? resolve(process.env.TEST_CASE_OUTPUT_PATH)
  : resolve(
      dirname(fileURLToPath(import.meta.url)),
      "../modules/connect/test_cases/smoke-test.json",
    );

writeFileSync(outputPath, builtTestCase.toJsonString(true));
console.log(`Wrote ${outputPath}`);
