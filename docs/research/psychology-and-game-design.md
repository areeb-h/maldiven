# Psychology, cooperation and game-design research

Research date: 2026-11-12. Purpose: inform Drift Station's design and tests. This is a scoped research synthesis, not a systematic review, new human-subject study or proof of commercial success. Papers span foundational work and a 2026 study. Search results about LLM social-deduction agents were excluded as evidence about human player experience.

## How to interpret this document
- **Finding:** what a cited study or paper reports in its setting.
- **Framework:** a way to organise design or evaluation; not a causal law.
- **Inference:** our proposed application to this game, requiring a playtest.
- **Target:** an engineering or product threshold we chose, not a scientific constant.

The sources differ in age, genre, participant population and methods. Friend groups playing a mobile social-survival game are not interchangeable with MMO guilds, children playing local co-op, competitive strategy players or laboratory social dilemmas. Do not combine their sample sizes, effect sizes or findings into a predicted success rate for this game.

## Evidence register
### R01 — Autonomy, competence and relatedness
**Source:** Ryan, R. M., Rigby, C. S., & Przybylski, A. (2006). *The Motivational Pull of Video Games: A Self-Determination Theory Approach*. Motivation and Emotion. [DOI](https://doi.org/10.1007/s11031-006-9051-8) · [original paper](https://selfdeterminationtheory.org/SDT/documents/2006_RyanRigbyPrzybylski_MandE.pdf).

**Evidence:** Four studies relate need satisfaction to game enjoyment and motivation; the multiplayer survey includes autonomy, competence and relatedness. Methods include experiments and survey evidence; associations must not all be treated as causal.

**Limits:** Selected games/populations and largely immediate experience or stated future play; not proof of long-term retention or the best match length.

**Inference:** Offer several useful contributions, understandable controls and opportunities to help friends. Test felt choice, capability and belonging separately. A player can win while feeling useless.

**Inspection:** Full-text paper available; abstract and selected methods/discussion consulted.

### R02 — Mechanics, dynamics, aesthetics
**Source:** Hunicke, R., LeBlanc, M., & Zubek, R. (2004). *MDA: A Formal Approach to Game Design and Game Research*. [AAAI publication](https://aaai.org/papers/ws04-04-001-mda-a-formal-approach-to-game-design-and-game-research/) · [original paper](https://www.cs.northwestern.edu/~hunicke/MDA.pdf).

**Framework:** Connect implemented rules, emergent interaction and the player's experienced qualities. It encourages starting with the desired experience and tracing how rules might produce it.

**Limits:** Design framework, not an experiment establishing which mechanics cause enjoyment or a complete model of every game.

**Inference:** Trace a tool handover through negotiation to fellowship/tension; trace a weapon through rescue/retaliation to the actual experience observed. Keep or cut mechanics according to the dynamics they produce, not feature count.

**Inspection:** Original full-text paper.

### R03 — Flow-inspired evaluation and readability
**Source:** Sweetser, P., & Wyeth, P. (2005). *GameFlow: A model for evaluating player enjoyment in games*. Computers in Entertainment, 3(3). [DOI](https://doi.org/10.1145/1077246.1077253) · [original-paper copy](https://www.valuesatplay.org/wp-content/uploads/2007/09/sweetser.pdf).

**Framework/evaluation:** Organises enjoyment heuristics around concentration, challenge, skill, control, goals, feedback, immersion and social interaction. Initial evaluation used expert reviews of two real-time strategy games.

**Limits:** That initial validation is narrow. It does not establish a universal challenge curve, an optimal cognitive load or social-game pacing.

**Inference:** Keep the shared goal legible, teach actions in play, give immediate system feedback and vary pressure with recovery time. Inspect confusion and input friction separately from intentional uncertainty.

**Inspection:** Original full-text paper; publisher page was not fully accessible.

### R04 — Voice and social connection
**Source:** Williams, D., Caplan, S., & Xiong, L. (2007). *Can You Hear Me Now? The Impact of Voice in an Online Gaming Community*. Human Communication Research, 33(4), 427–449. [DOI](https://doi.org/10.1111/j.1468-2958.2007.00306.x) · [author-hosted original paper](https://dmitriwilliams.com/wp-content/uploads/2020/06/HCRVoice.pdf).

**Finding:** A controlled field experiment introduced voice into existing World of Warcraft guilds; results included increased liking and trust. Group assignment and baseline differences matter to interpretation.

**Limits:** Established MMO groups are not six-person mobile deduction rounds. This does not prove proximity audio, many radio channels or mandatory microphones improve our game.

**Inference:** Put intelligible voice in the earliest physical-phone experiment, with pings and mute options. Compare social connection and participation, not just voice uptime or speaking duration.

**Inspection:** Author-hosted full text, including group-assignment discussion.

### R05 — Cooperative patterns and observation
**Source:** Seif El-Nasr, M., Aghabeigi, B., Milam, D., Erfani, M., Lameman, B., Maygoli, H., & Mah, S. (2010). *Understanding and evaluating cooperative games*. CHI, 253–262. [DOI](https://doi.org/10.1145/1753326.1753363) · [author-uploaded paper](https://www.researchgate.net/publication/221516170_Understanding_and_evaluating_cooperative_games).

**Finding:** Analysis of cooperative patterns and an observational study with 60 participants in groups of two or three connect patterns such as shared goals, puzzles and complementary capabilities with observed cooperation metrics.

**Limits:** Participants were aged 6–14 and played selected local cooperative games. Observed helping can reflect control difficulty; more helping is not automatically more fun. Annotation associations are not isolated randomised mechanic effects.

**Inference:** Test shared-object interactions and transferable complementary tools. Record planning, helping, waiting and frustration together. Do not manufacture awkward controls just to force conversation.

**Inspection:** Author-uploaded full text, methods and conclusion; ACM endpoint restricted.

### R06 — Communication in social dilemmas
**Source:** Balliet, D. (2010; online 2009). *Communication and Cooperation in Social Dilemmas: A Meta-Analytic Review*. Journal of Conflict Resolution, 54(1), 39–57. [publisher/DOI](https://journals.sagepub.com/doi/10.1177/0022002709352443).

**Finding:** The publisher abstract reports a positive communication–cooperation relationship across 45 effect sizes, moderated by communication form and group size.

**Limits:** Only the abstract was accessible. Social-dilemma cooperation is not game enjoyment; face-to-face discussion must not be equated with our radio/proximity voice.

**Inference:** Give players an opportunity to agree on plans before irreversible actions. Treat communication architecture as a design variable; do not predict our effect size from this review.

**Inspection:** Publisher abstract only. No claims are made about unread full-text analyses.

### R07 — Deception cues are context-dependent
**Source:** Zhang, Z., McGettigan, C., & Belyk, M. (2022). *Speech timing cues reveal deceptive speech in social deduction board games*. PLOS ONE, 17(2), e0263852. [original article](https://journals.plos.org/plosone/article?id=10.1371/journal.pone.0263852).

**Finding:** An audio-only social-deduction setting showed associations between speech timing and deceptive statements. The paper discusses equipment/environment control and variation in how participants deceive.

**Limits:** Group-level statistical cues are not a dependable verdict about an individual. This setting cannot validate accent-, pause- or confidence-based suspicion in our player population.

**Inference:** Supply discussable world events, and never build automatic lie detection or score vocal behaviour. Inspect whether quieter/less fluent participants can contribute without being reflexively accused.

**Inspection:** Original article, methods and limitations/conclusion.

### R08 — Players do not automatically follow designer incentives
**Source:** Chen, E., Bisberg, A. J., Williams, D., Seif El-Nasr, M., & Ferrara, E. (2026). *Change is Hard: Consistent Player Behavior Across Games with Conflicting Incentives*. CHI '26. [DOI](https://doi.org/10.1145/3772318.3791411) · [author-hosted paper](https://dmitriwilliams.com/wp-content/uploads/2026/04/ChangeIsHard.pdf).

**Finding:** Cross-game analysis of 4,830 players with at least 50 competitive games in both League of Legends and Teamfight Tactics found behavioural consistency despite different incentives.

**Limits:** Observational study within one developer ecosystem; selection and how flexibility was operationalised limit transfer to other genres and groups.

**Inference:** Do not assume scarce ammunition or a repair reward will make aggressive friends cooperative. Observe actual strategies across repeated rounds and varied groups; provide multiple legitimate styles of contribution.

**Inspection:** Original full-text paper, abstract and limitations.

## Design hypotheses and experience mapping
The following table is our synthesis, not an additional finding from the cited papers. Test identifiers resolve to the playtest protocol.

| Hypothesis | Proposed rule | Desired experience | Principal failure | Test |
| --- | --- | --- | --- | --- |
| H1: useful interdependence creates conversation | Shared cell plus transferable tools | Planning/helping with agency | Waiting for a missing specialist | PT-01 |
| H2: spatial voice creates meaningful local groups | Proximity plus one common radio | Social presence and discoverable separation | Isolation, echo or vocal domination | PT-02 |
| H3: imperfect world evidence supports fair suspicion | Credential/event evidence without role labels | Debate and uncertainty | Perfect detective terminal or arbitrary accusations | PT-03 |
| H4: recoverable weapons add stories | Visible stun, cargo drop, revive and bounded recovery | Protection, bargaining and rescue | Random attacks, stunlock and inactivity | PT-04 |
| H5: route loops create encounters and choice | Two loops, public overrides, visible destinations | Navigation competence and chance meetings | Camping, confusion, permanent trapping | PT-05 |
| H6: a readable complete round supports replay | Clear goals, short debrief and rematch | Closure and shared storytelling | Rules confusion or social pressure to replay | PT-06 |

## Game-theoretic incentive audit
This is a qualitative design analysis, not an estimated utility model, solved equilibrium or empirical finding. The shared station threat creates temporary alignment; rival core extraction creates later conflict. Information asymmetry should concern intent and opportunity while basic rules remain common knowledge.

| Strategy | Why it could seem attractive | Design cost/counterplay to test |
| --- | --- | --- |
| Cooperate early, betray late | Both factions need power and routes | Observable core removal and interruptible escape preserve response |
| Hoard all tools | Control the group's progress | Transfer, spare/manual alternatives and limited inventory reduce absolute vetoes |
| Attack everyone immediately | Remove uncertainty through force | Limited stun charges, recovery and visible aggression make consequences observable |
| Follow one friend constantly | Reduce uncertainty and remain safe | Multiple time-sensitive objectives create a choice; do not force solitary play |
| Camp the only exit | Convert position into unavoidable victory | Alternate routes, manual overrides and extraction warnings |
| Always obey the loudest person | Saves discussion effort | Independent evidence, actionable pings and transferable responsibility |

If observed incentives contradict intended incentives, change the rules. Do not blame players for finding a dominant strategy. Measure whether credible cooperation and betrayal both remain possible.

## Applications we should avoid
- Treating uncertainty as permission for obscure controls or random punishments.
- Reading silence, accent, pitch or hesitation as a reliable lie detector.
- Fixed personality labels that assume each player always wants one role.
- Using time played, total speech or raw laughter as a complete measure of enjoyment.
- Predicting retention from one successful session or forcing replay through streaks, expiring rewards or pay-to-win advantages.
- Treating a statistically significant paper result as a shipping specification.

## Technical feasibility sources, distinct from psychology evidence
- [T01: Godot 4.7 high-level multiplayer](https://docs.godotengine.org/en/4.7/tutorials/networking/high_level_multiplayer.html): available peer implementations and multiplayer API constraints. Server-authoritative design is our application, not automatic protection provided by RPCs.
- [T02: dedicated server export](https://docs.godotengine.org/en/4.7/tutorials/export/exporting_for_dedicated_servers.html): headless and stripped server export support.
- [T03: native WebRTC](https://docs.godotengine.org/en/4.7/tutorials/networking/webrtc.html) and [official extension](https://github.com/godotengine/webrtc-native): native extension requirement for the documented WebRTC classes. The documentation page flags possible outdated content; verify the exact release. Data-channel support alone does not implement microphone audio, codec, echo cancellation or voice-service compatibility.
- [T04: LiveKit SDK platforms](https://docs.livekit.io/transport/sdk-platforms/) and [Android quickstart](https://docs.livekit.io/transport/sdk-platforms/android/): official Android SDK is a candidate for a Godot Android plugin bridge. The reviewed platform list does not establish a supported drop-in Godot Android SDK. No provider is selected yet.
- [T05: ENetConnection](https://docs.godotengine.org/en/4.7/classes/class_enetconnection.html): documented DTLS setup methods. Verify integration/certificates on the exact Android/server build before claiming encrypted transport.

## What research does not settle
It does not choose a voice vendor, optimal map size, stun duration, infiltrator ratio, match length, server region or spending budget. Those decisions require technical spikes, owner constraints and human playtests. All source URLs and access scope above are recorded so later reviewers can challenge the reasoning.

## Coordination and participation extension

The [research addendum](coordination-and-participation.md) adds R09 (Clark/Brennan on grounding) and R10 (Woolley and colleagues on group performance), including inspection scope, transfer limits and PT-07–PT-10 hypotheses. The combined register now has ten sources; these additional sources do not establish that our particular coordination UI or gameplay will succeed.
