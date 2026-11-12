# ADR 0017: Preserve provenance and scope in social information

Date: 2026-11-12. Status: Proposed. Extends ADR 0010/0013.

## Context

Players need facts worth discussing without an interface that automatically identifies the infiltrator. Optional agreement cards could help coordination but could also falsely imply understanding, enforced intent or moral judgement.

## Decision

Distinguish authoritative public facts, limited instrument facts, personal observations, agreement acknowledgements and accusations. System evidence is truthful within its stated scope. Player claims are visibly attributed. An acknowledgement is explicit and revision-specific; delivery alone is not acceptance. Agreements never automatically score honesty, force ownership changes or reveal allegiance.

## Alternatives

- Automatic suspicion/trust scores: easy summary, but an unsupported verdict and a likely source of exclusion.
- Indistinguishable forged system records: more uncertainty, but first requires a separate understandable authenticity mechanic.
- Voice-only agreements: retain as the comparison baseline and use it if cards add friction.

## Consequences and validation

Evidence UI and server visibility policy must agree. Custom labels cannot imitate official warnings. Test truthful disagreement, changed acknowledgement and authority spoofing with SX-02/03/05 and PT-07. See [social design](../blueprint/social-roles-and-agreements.md); this ADR does not establish implementation or measured benefit.
