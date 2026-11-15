# First-session storyboard and reviewable mockup scope

Version 0.3, 2026-11-12. This is the proposed screen/interaction specification for the next UI mockup, not an existing interactive preview. It turns the experience journey into content a designer and implementer can review.

## The first three minutes: remove uncertainty about controls

Timing is illustrative and may be slower for an unfamiliar player. Skip/repeat is available; no speed score is shown.

| Beat | Screen/world moment | Primary action | Visible feedback | Alternate/error path |
| --- | --- | --- | --- | --- |
| 1 | Home: Join friends, Create room, Practice, Settings | Join friends | Code field and optional supported invite route | Paste/manual code; useful invalid/expired/version message |
| 2 | Voice check before entry | Choose mic/PTT, test locally, continue muted | Explicit input/transmit and audio destination status | Denied mic still permits the supported muted route |
| 3 | Hangar arrival | Walk to the station model | Own movement and another avatar are visible | Sensitivity/text/control settings remain reachable |
| 4 | Practice handover | Offer a cutter to a teammate | Pending offer; recipient accepts; holder updates once | Recipient declines or walks away; original keeps it |
| 5 | Shared-cell practice | Join another carrier and choose a safe parking point | Shared state and release control | One leaves/backgrounds; the load safely releases |
| 6 | Ready/briefing | Confirm the displayed preset and read private objective | Shared objective separate from allegiance | Rules change clears ready; no secret appears in public UI |

The mockup can simulate these beats, but its label must distinguish simulated network/voice from real integration. The P1 voice gate still needs physical phones.

## HUD priorities in a round

1. The world and other players remain the main focus.
2. One short current goal and the sector name provide context; expanded objectives are optional.
3. The nearest eligible interaction gives a verb and understandable target.
4. Persistent mic/transmit/destination and an accessible mute control remain visible.
5. Warnings take temporary priority with source, location, consequence and time; ordinary notifications do not cover them.

Movement uses the left thumb; looking uses the right. Context action replaces irrelevant buttons instead of stacking every future tool on screen. PTT needs a reachable/toggle option without requiring a third held finger. Test left-handed and resized layouts. No essential control should sit in a camera cutout or gesture area.

## Twelve states the mockup must represent

| State | Exact question answered | Required action/feedback |
| --- | --- | --- |
| Empty room | Am I alone or still loading? | Participant count, invite code, practice and leave |
| Joining | Has entry succeeded? | Bounded progress, cancel and explicit failure |
| Incompatible version | Why can I not play with my friend? | Show required/current version; no partial avatar |
| Muted/permission denied | Can I still participate? | Continue with pings; settings route for microphone |
| Offer pending | Who owns this item now? | Pending label; accept/decline; current owner stays visible |
| Interaction interrupted | Why did progress stop? | Allowed public reason and what can be tried next |
| Warning active | Where is the danger and how long do we have? | Named location, visible timer, consequence and route context |
| Downed | Am I excluded, and for how long? | Bounded recovery timer, ping and visible rescue state |
| Reconnecting | Is my character/role preserved? | Grace indicator, retained identity and return-to-lobby choice |
| Connection lost by a teammate | Is this a game event? | Honest technical status without faction inference |
| Round interrupted | Did either faction win? | Neither; clear technical/roster reason and rematch/leave |
| Debrief | What happened and what is next? | Outcome, short factual timeline, rematch/change preset/leave |

## Three review scenes

**A. The friendly arrival:** one experienced player and one newcomer exchange a tool, change audio route and park a shared cell. Review whether assistance can happen through the UI without the experienced player taking over.

**B. The disputed case:** a Cargo warning appears while a credential is being transferred. The UI shows the transfer state and narrow hatch fact without declaring guilt. A muted participant uses a meet/bring-item ping. Review whether viewers can distinguish system fact, player claim and agreement.

**C. The recoverable crisis:** a carrier is downed near a hatch as another phone loses connection. The HUD prioritises the real warning, clears stale controls and preserves a visible recovery path. The story ends in a valid result or explicit interruption, not a fabricated win screen.

## Art needed for the first mockup

One readable Commons view, a compact station map, six distinct readable suit treatments, cell/cutter/kit silhouettes, one hatch, one transfer card and one warning/debrief treatment. Use temporary silhouettes/greybox where appropriate. A rendered illustration is concept art; engine performance, collision and real voice are separate acceptance evidence.

Do not polish a purchase screen, ranked lobby or many weapon menus before these states are understandable. The mockup should let us review an entire small session rather than only a beautiful home screen.

## Review checklist

Ask a person unfamiliar with the design to point to: where their voice goes, who holds the offered item, their next useful action, how to decline, why a countdown stopped and how to leave. Record mistakes and hesitations without turning them into a player ability score. Fix the interface before adding tutorial text to explain it away.
