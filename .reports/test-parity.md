# Test parity — bazaar

| | |
|---|---|
| Upstream | `main` @ `3d347d5` |
| Port | `ruby` @ `34f2564` |
| Upstream tests | 0 |
| Ported | 0 |
| Gaps | 0 |
| Test command (port's own extras) | `nix develop --command xvfb-run -a ruby test/drive_bazaar.rb` and `test/drive_library.rb` |

## Step 1 — census of upstream

```sh
find /tmp/bazaar-upstream -iname '*test*' -not -path '*/.git/*'
```

returns exactly one hit, `bge/demo/test.wdgt` — a demo fixture file for the
bundled `bge` widget library, not a test. `test-census.sh` run against the
upstream tree returns **0 rows**. There is no `test/`, `tests/` directory, no
`meson test()` target, no `g_test_add_func` call anywhere in `src/`.

**Upstream has no test suite.** Parity is 0/0 and is met trivially. The port
therefore inherits no safety net — every check in the port's own test files
was written for the port and pins nothing upstream ever considered worth
pinning down. This is the finding, not a footnote to it.

## Step 2 — what the port actually has, and whether it runs

`test-census.sh` against the `ruby` branch finds rows across
`test/drive_bazaar.rb`, `test/drive_library.rb` and `test/gtk_driver.rb`
(the last is the driver helper and contributes none of substance — its rows
are usage-example comments the census over-matched; the real count is the
`plain_check`/`check`/`d.check` call sites in the two drive scripts).

Both drive scripts were run live during this audit, through the dev shell
and a virtual display, exactly as `CLAUDE.md` and the `AGENTS.md` for this
fork specify:

```
nix develop --command xvfb-run -a ruby test/drive_bazaar.rb
→ 44 of 44 plain checks passed
→ 42 of 42 widget-driving checks passed across 26 steps (indices 0–25)
→ DRIVE OK

nix develop --command xvfb-run -a ruby test/drive_library.rb
→ all checks passed (32 further checks)
```

This matches the runtime gate handed to this audit (`drive_ok=true`, 86
checks, 0 failed, 28 components) exactly: 44 + 42 = 86 in `drive_bazaar.rb`
alone, and the 26 numbered steps plus the plain/driven groupings are the "28
components." **The gate is real — it was re-run here, not merely trusted —
and it is not green by omission of a check that would fail; every check it
contains actually passed.** This is also a larger gate than the previous
round's (58 checks, 23 steps), growing in step with the 8 units
(`AspectPicture`, `AuthState`, `ContextRow`, `DonationsDialog`,
`EntrySelectionRow`, `HardwareSupportDialog`, `LicenseDialog`, `Lozenge`)
ported since `2698ccc` — steps 22–25 are new this round and exercise exactly
those additions (AuthState sign-in/out, donate action, malcontent bus query,
OARS ceiling).

## Step 3 — but the gate is still narrow, and that is a parity gap in its own right

The runtime gate's "28 components" is a count of *drive steps and check
groups*, not of upstream units. Read against
`.reports/component-identification.md`'s 87 identified units, the 86+32
checks exercise at most:

- the application shell's `preferences`, `toggle-debug-mode`, `search`,
  `donate` actions (still a minority of the 13 window actions, plus a
  handful of app actions)
- the window's main stack, breakpoint bin, navigation push/pop, menus
- the library page (content/no-results/search states, sort, two tiles)
- about dialog, shortcuts dialog, preferences dialog, error dialog,
  donations dialog
- AuthState, malcontent service, the OARS parental-ceiling check
- transaction manager (success + failure paths)
- the non-widget layer: appstream parser, entry, entry group, search
  engine, settings, blocklist, spdx

That is roughly 20–23 of the 87 identified units — more than last round, but
still a minority. **The other ~60–64 units — including the Curated tab, the
Explore/discovery tab, the Search tab, the full app-detail view, and 10 of
17 dialogs (addons, app-permissions, app-size, age-rating, bundle-install,
safety, stats, transaction, transaction-list, user-data) — are exercised by
zero checks, because the code that would need exercising does not exist.**
Per this audit's brief: a component no check exercises is unverified, not
done. A passing, narrower-than-the-app drive run is evidence the ~20–23
built units work; it is not evidence about the ~60 unbuilt ones, and must
not be read as such.

## Step 4 — extra

```markdown
## Extra
- `test/drive_bazaar.rb` — 86 checks (44 plain + 42 driven across 26 steps),
  driving the application shell, window, library page, preferences, about,
  shortcuts, error and donations dialogs, AuthState, malcontent and the
  transaction manager, through the real `Bazaar::Application` against a
  fake backend. Re-run live for this audit; passes, 0 failed.
- `test/drive_library.rb` — a smaller, overlapping drive of the same
  surface (library page, preferences, transaction manager) via a
  hand-built `Window` rather than the full `Application`. Re-run live for
  this audit; passes, 32 checks, 0 failed.
```

Neither file maps to an upstream test, because none exists to map to. Both
are useful regression coverage for the fraction of the app that is built,
and neither should be read as proof that more of the app works than it
actually tests.

## Rules re-affirmed

- 0/0 is met trivially; it is not evidence of quality, and the drive scripts'
  86+32 passing checks are not test-parity work — they are listed under
  `## Extra`, outside the count, per the skill.
- A narrow, passing drive run is reported as narrow, even as it grows. See
  `.reports/component-parity.md` for the 60 units it still says nothing
  about.
