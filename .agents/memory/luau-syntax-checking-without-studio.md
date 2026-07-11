---
name: Checking Luau/Roblox script syntax with no Roblox engine available
description: How to sanity-check .lua/.luau files for balanced blocks when there is no lua/luau interpreter that accepts Luau syntax (type annotations, etc.) and no Roblox Studio to actually run them.
---

Replit's containers have no Roblox engine and no interpreter that accepts Luau's syntax
extensions (`local function f(x: number): string?`, etc.) — plain `lua`/`lua5.x` will
reject those files with a syntax error even if they're otherwise correct, and no
`luau`/`luau-analyze`/`selene` binary is preinstalled. `nix-shell -p nodejs_20` is
available on demand, though, so a quick Node script that tokenizes the source (after
stripping comments/strings) and does a stack-based match of
`function/if/for/while/repeat/until/end` plus paren/brace/bracket balance is the
practical substitute for a real parser.

**Why:** without this, edits to large Roblox scripts (1000+ lines) can't be verified at
all before handing them back, and a single missing `end` or stray paren silently breaks
the whole script at runtime in Studio with no feedback loop back to the agent.

**How to apply:** when editing `.lua`/`.luau` files for a Roblox project with no engine
attached, after edits run a Node balance-checker via `nix-shell -p nodejs_20 --run "node script.js"`.
Key gotcha: don't treat every `do` as its own block opener — `for ... do ... end` and
`while ... do ... end` only need ONE matching `end` between them, so counting `do` as a
separate opener produces false "unbalanced" results. Only standalone `do...end` scoping
blocks (rare) would need `do` tracked separately; in practice it's simplest to drop `do`
from the opener list entirely unless the file is known to use bare `do` blocks.
