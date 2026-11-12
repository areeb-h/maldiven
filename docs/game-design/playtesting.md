# Playtest and evaluation protocol

Version 0.1, 2026-11-12. Formative product evaluation; not a clinical/psychological assessment or a powered scientific experiment. Numbers below are chosen targets to revise transparently.

## Recruitment and session shape
Start with one familiar group to find crashes and unclear rules. Before the friends-alpha gate, include at least six distinct groups and 30 valid completed rounds. Repeated rounds in one group are dependent observations; report counts by group and participant as well as round. Include mixed gaming experience and people who prefer less speaking. Do not infer personality, honesty or wellbeing from telemetry.

A session contains a voice/control check, a short playable briefing, a cooperative practice, two or three test rounds and a five-minute debrief. Allow leaving or declining voice without pressure. Participant recruitment and invitations remain the owner's action; this plan does not authorise messages to others.

Record game version, device/OS, renderer, network, group familiarity, round order, role assignment method and test condition. Exclude aborted technical rounds from win-rate balance calculations, but count them in reliability reporting. Do not silently drop bad sessions.

## Evidence and privacy
Use pseudonymous session/player IDs and minimal event records: joins/leaves, role distribution at round end, validated interactions, ownership, down/revive events, objective/extraction timings and failures. Do not log join tokens, private credentials, raw microphone audio or chat transcripts by default. Voice recording requires a separate explicit opt-in decision by all affected participants; it is not required for the core evaluation.

A facilitator can tally planning/helping/confusion events without saving speech. Speaking-time summaries, if collected with disclosure, indicate participation patterns rather than enjoyment or deception. Participants can decline optional feedback/observation. Do not deploy a lie detector.

## Protocols
| ID | Question and comparison | Observe | Decision |
| --- | --- | --- | --- |
| PT-01 | In a cooperative rehearsal, does a shared cell create useful teamwork? Compare with an independently operable objective. | Negotiation, helping, time blocked by another player, completion and contribution ratings | Keep the shared interaction only if added social value exceeds waiting/friction |
| PT-02 | Does proximity+shared radio improve local interaction relative to always-global voice? | Audibility, group separation/reunion, missed critical information, muted-player contribution | Keep or simplify routing; do not add channels until first model is understood |
| PT-03 | Does partial world evidence make the infiltrator round understandable and contestable? | Claimed evidence, actual events, arbitrary accusations, role leaks and fairness ratings | Tune evidence specificity; never substitute vocal profiling |
| PT-04 | Does one stun weapon improve stories relative to the no-weapon deduction condition? | Protection/rescue, random attacks, retaliation loops, inactive time and perceived agency | Tune or remove combat if participation/conversation deteriorate |
| PT-05 | Does the two-loop map produce choices and encounters without navigation burden? | Route heatmaps/sector transitions, time lost, camping and door softlocks | Alter topology before polishing art |
| PT-06 | Are rules and outcomes clear enough for voluntary replay? | Goal recall, outcome explanation, spontaneous story recall, unprompted rematch/exit | Fix clarity/closure; do not interpret politeness as replay demand |

Change one principal variable per comparison. Counterbalance order across groups where practical and rotate the infiltrator fairly. Disclose that roles are randomised; do not announce future assignments. Include qualitative reports that contradict the preferred result. Do not compare a polished condition against a deliberately broken one.

## Short post-round questions
Use a 1–5 response scale with optional comments:
1. I understood what I could do next.
2. I could make useful choices and contribute.
3. I felt included in the group's activity.
4. The outcome felt understandable and fair.
5. I would choose another round now.

Also ask: What was your most memorable moment? When did you feel stuck or left out? Which rule would you remove? For someone declining voice: Could you still influence the round?

These are custom formative questions, not validated SDT/PENS or GameFlow instruments. Do not call the results clinical scores or claim validated measurement without selecting and administering an appropriate instrument.

## Product thresholds and analysis
Initial alpha target: group medians at least 4/5 on contribution, clarity and willingness to replay, with no recurring exclusion pattern hidden by the average. Track per-player responses and disagreements. Review if someone repeatedly scores 1–2 even while the group median is high. The threshold itself is not research evidence.

Report crew wins, infiltrator wins, station losses and interrupted rounds separately. At 30 rounds, report uncertainty and context; do not infer precise balance or superiority over another game. Investigate runs of early attacks, long inactivity, dominant routes or a single friend controlling every session. Baseline familiarity and learning can explain changes across rounds.

If comparing against an existing game later, use consented comparable groups, comparable session length, counterbalanced order and the same outcome questions. Record existing-game familiarity and novelty. A small convenience sample cannot establish market-wide superiority.

## Technical checks alongside experience
- Real-phone audio latency/intelligibility and headset/speaker routes.
- Permission denial, app background/resume and Wi-Fi/mobile-data switching.
- Six/eight-player frame times, thermal behaviour, RAM and bandwidth.
- Simultaneous item claims, shot/door timing, invalid RPCs and reconnect identity.
- Client inspection cannot reveal undisclosed roles or forbidden voice tracks.
- Compare the affected phone's horizontal bands across the supported renderers.

## Session note template
```text
Date / source commit / client and server versions:
Devices / OS / renderer / network:
Participants / distinct group / prior familiarity:
Condition / order / role rotation:
Completed / interrupted rounds and reasons:
Event observations and counterexamples:
Individual feedback and group summary:
Technical measurements and measurement method:
Defects / continue-change-stop decision / owner:
Next single variable to test:
```
