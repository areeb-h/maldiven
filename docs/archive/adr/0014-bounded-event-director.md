# ADR 0014: Use a bounded, observable event director

Date: 2026-11-12. Status: Proposed for H2; not an H1 dependency.

## Context
A living station needs variation and pressure, but arbitrary incidents can erase player agency, block all routes or look like hidden cheating.

## Decision
Use authored events with prerequisites, warning, pressure cost, duration, recovery and incompatibility data. The authoritative server evaluates map reachability and phase rules before scheduling. Log the seed and selected events for diagnosis/debrief. Reject combinations that create unsupported trapping or concurrent information overload.

Do not infer player emotion/honesty from microphone signals, select victims based on vulnerability, or secretly change faction outcomes. Begin with three incidents and assess their social impact before expanding the catalogue.

## Consequences
Some combinations must be excluded and some emergent surprises will be lost. Reproducible event selection is useful, but does not imply deterministic physics across devices. A director budget is a design tool requiring playtests, not a validated psychological tension controller.

## Gate
EXP-06 requires stable H1 rules and the station graph validator. SC-13 checks invalid closures; PT-01/PT-05/PT-06 check whether pressure retains navigation, contribution and readable causes.
