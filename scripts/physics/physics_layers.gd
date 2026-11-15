class_name PhysicsLayers
extends RefCounted
## Collision layer bits used across Drift Station (see scripts/physics/README.md).

const WORLD := 1  ## Static station geometry and socket fixtures.
const REMOTE_PLAYER := 2  ## Remote crew puppets (CharacterBody3D).
const LOCAL_PLAYER := 4  ## This peer's own crew member (CharacterBody3D).
const ITEM := 8  ## Loose items: cells, the core, the gun (host RigidBody3D / client replica).
const PROP := 16  ## Pushable props: crates, barrels, carts, chairs, toolboxes, canisters.
const PROXY := 32  ## Host-only kinematic player proxies that push props and catch thrown items.
const RAGDOLL := 64  ## Client-local cosmetic ragdoll parts (collide with WORLD only).

## Items rest on the world and on each other, ride on props. Proxies are added
## only while an item is in flight, so walking into a resting item nudges it
## (scripted) instead of launching it at running speed.
const ITEM_MASK := WORLD | ITEM | PROP
const ITEM_HOT_MASK := WORLD | ITEM | PROP | PROXY
const PROP_MASK := WORLD | ITEM | PROP | PROXY
