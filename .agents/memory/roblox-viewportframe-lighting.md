---
name: ViewportFrame black silhouette / phase-crash isolation
description: Why an avatar rendered in a ViewportFrame can appear solid black, and why one crashing phase in a sequential Lua intro can silently swallow every phase after it.
---

## ViewportFrame renders its own isolated scene
A `ViewportFrame` does NOT inherit the game's `Lighting` service settings. Its
`Ambient` and `LightColor` properties default to pure black. A character/model
cloned into a `WorldModel` inside a `ViewportFrame` with no explicit lighting
will render as a solid black silhouette, indistinguishable from a black
backdrop behind it — this looks exactly like "the screen goes black / nothing
is happening", even though everything else (poses, particles, camera moves)
is running correctly.

**Why:** Spent a full debugging pass chasing a phantom script error for a
"goes black after X" report before realizing the actual cause was missing
scene lighting, not a crash.

**How to apply:** Whenever building a ViewportFrame-based character preview,
explicitly set `viewport.Ambient`, `viewport.LightColor`, and
`viewport.LightDirection` (e.g. mid-grey ambient + warm-white light) right
after creating the ViewportFrame. Don't rely on a single `PointLight` parented
into the WorldModel as the only light source — set the viewport-level
ambient/light properties too.

## Isolate sequential phases with pcall + bounded waits
In a Lua script that plays a fixed sequence of phases one after another
(e.g. a cinematic intro: welcome -> loading -> showcase -> credits -> logo),
one phase throwing an error, OR blocking on an event that will never fire
again (e.g. `Instance.CharacterAdded:Wait()` called after the character has
already spawned), silently halts every phase after it with no visible error
to the player — they just see the last successful phase frozen forever.

**Why:** A single unguarded `:Wait()` on an event that may have already fired,
or an unguarded runtime error deep in one phase, took down phases that were
otherwise completely unrelated and already working (e.g. a "creator credit"
screen disappeared even though its own code was untouched).

**How to apply:** Wrap each phase call in `pcall` (log+continue on error) and
give any one-shot event wait a hard timeout/polling fallback instead of an
unbounded `:Wait()`, so a bug in one phase can never cascade into skipping
every phase that comes after it.
