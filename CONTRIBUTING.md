# Contributing

## Development Setup

Clone the repository and symlink the source into your AwesomeWM config for live testing:

```bash
git clone https://github.com/quincyjo/continuity.git ~/path/to/continuity
ln -s ~/path/to/continuity/lua/continuity ~/.config/awesome/continuity
```

Install the required tools:

- [busted](https://lunarmodules.github.io/busted/) — test runner
- [luacheck](https://github.com/mpeterv/luacheck) — linter
- [StyLua](https://github.com/JohnnyMorganz/StyLua) — formatter

## Branching

- `main` — stable release branch; only release merges land here
- `develop` — integration branch; all feature branches merge here
- `feature/<name>` — cut from `develop`, merge back to `develop` via PR

```bash
git checkout develop
git checkout -b feature/my-feature
# ... implement ...
git push origin feature/my-feature
# open PR targeting develop
```

## Local Verification

Run all checks before opening a PR:

```bash
busted                    # tests on system Lua
busted --run=luajit       # tests on LuaJIT (if installed)
luacheck .                # zero warnings/errors
stylua . --check          # format-clean
```

CI runs tests on both Lua 5.3 and LuaJIT 2.1. Run both locally if you have them installed. If only one runtime is available, CI will catch the other — but running both before pushing avoids surprises.

Format files as you work to avoid drift:

```bash
stylua lua/continuity/mymodule/init.lua
```

## Code Conventions

**Lua compatibility:** all code must work on Lua 5.3 and LuaJIT. Avoid `//`, `&`, `|`, `~`, `>>`, `<<` operators and `bit`/`ffi`/`table.new`.

**EmmyLua annotations:** add `---@class`, `---@field`, `---@param`, `---@return` to all public types and functions.

**Dot vs colon:** use dot notation for module-level functions (`module.setup`, `module.stop`); use colon notation for instance/handle methods (`handle:subscribe`, `handle:on_control`).

**Comments:** only when the _why_ is non-obvious. No redundant "what the code does" comments.

## Pull Requests

Target `develop`. The PR description should cover:

- What changed and why
- Which modules are affected
- Whether tests were added or updated
- Whether `docs/` and `README.md` were updated if public API changed
