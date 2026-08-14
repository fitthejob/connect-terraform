export interface RegistryEntry {
  flowName: string;
  identifier: string;
  label: string;
}

// Hand-maintained per the design (docs/superpowers/specs/2026-08-14-self-service-abandonment-metric-design.md)
// -- Lex-engagement-only abandonment points. Do not auto-derive this from
// flow JSON; that's an explicit non-goal until this basic version is proven.
export const REGISTRY: RegistryEntry[] = [
  { flowName: "Main-Inbound", identifier: "MenuInput", label: "menu-selection" },
  { flowName: "Module-SmsVerification", identifier: "CollectCode", label: "sms-verification-code" },
];

// ContactFlowName in a real flow log entry carries the environment suffix
// (e.g. "Main-Inbound-dev") -- strip a trailing -dev/-staging/-prod before
// matching against the environment-agnostic registry.
function stripEnvSuffix(flowName: string): string {
  return flowName.replace(/-(dev|staging|prod)$/, "");
}

export function matchRegistry(flowName: string, identifier: string): RegistryEntry | undefined {
  const baseName = stripEnvSuffix(flowName);
  return REGISTRY.find(
    (entry) => entry.flowName === baseName && entry.identifier === identifier,
  );
}
