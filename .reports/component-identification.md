# Component identification — bazaar

| | |
|---|---|
| Upstream | `main` @ `3d347d5` |
| Port | `ruby` @ `34f2564` |

This run re-verifies, and does not supersede, the inventory already committed
at `.reports/component-inventory.md` (produced by an earlier pass of this same
skill). That document is the Step 1–5 census the skill asks for: every `.blp`
template on upstream read first (59 of 60 use `template $BzFoo:`), the GIR
symbol table built, `component-scan.sh` run over `src/`, and the result
written as one `## <file>` section per unit with widget counts, CSS classes
and signals.

Its totals, confirmed again here by walking `git ls-tree -r --name-only
origin/main`:

| | upstream `src/` | port `lib/` |
|---:|---:|---:|
| `.c` files | 127 | — |
| `.blp` templates | 60 | 0 (house style builds in code — correspondence, not a gap) |
| widget rows (scanned) | 1095 | partial — 41 files |
| distinct widget types | 62 | ~40 |
| distinct CSS classes | 114 | carried over verbatim in `lib/style.css` |
| distinct signals connected | 97 | ~46 |
| GAction names | 37 | 20 |

Per-unit disposition, counted from the inventory's own table rows and updated
for the 8 units ported since the last `Parity reports` commit (`2698ccc`):
`AspectPicture`, `AuthState`, `ContextRow`, `DonationsDialog`,
`EntrySelectionRow`, `HardwareSupportDialog`, `LicenseDialog`, `Lozenge`:

| Disposition | Count |
|---|---:|
| `no` (not built at all) | 60 |
| `partial` | 8 |
| `yes` | 19 |

**60 of 87 identified upstream units (≈69%) still have no counterpart in the
port at all.** That is real progress from the 68/87 (≈78%) of the previous
round, and every one of the 8 newly-built units is driven by
`test/drive_bazaar.rb` (steps 22–25: AuthState, donate action, malcontent
query, OARS ceiling). But the number the rest of the parity work has to be
read against is still 60, not the 41 files that now exist.

The units marked `no` still include the app's primary purpose: the Curated
tab (`bz-curated-view`), the Explore/Flathub-discovery tab (`bz-flathub-page`
and its state, category and section helpers), the Search tab
(`bz-search-page`), the app detail page (`bz-full-view`, 75 widget rows / 24
CSS classes — the single largest unit in the app), and 10 of 17 dialogs:
add-ons, app permissions, app size, age rating, bundle install, safety,
stats, transaction, transaction list, user-data. (Donations, hardware
support and license dialogs moved from `no` to `yes` this round.)

## Confirmed this pass

- `lib/window.rb` still only `require_relative`s `library_page`,
  `template_callbacks` and `transaction` (verified by reading the file at
  `34f2564`) — there is no `require_relative` anywhere in `lib/` for a
  flathub/curated/search/full-view file because none exists. `find lib
  -type f` now lists 42 files (41 Ruby files plus `style.css`) against the
  87 identified upstream units — up from 27 at the previous round, but the
  window's own stack is unchanged: one page, Library.
- `lib/template_callbacks.rb` still has a small minority of upstream's 228
  `$closure(...)` names — confirmed consistent with the absent pages, since
  most of the closure names belong to templates that are not built.
- The window's own comment (`lib/window.rb:25`) and the application's
  (`lib/bazaar/application.rb:159`) are unchanged word-for-word from the
  previous round — the three missing top-level tabs and the insensitive
  menu items they describe are still exactly as missing as before.

No correction to the previous round's upstream-side numbers was found; they
are unchanged because `origin/main` has not moved (`3d347d5` both rounds).
The only numbers that changed are the port's.

See `.reports/component-parity.md` for the four-axis comparison this
inventory feeds, and `.reports/accountability-ensurance.md` for how the gap
is described in `lib/window.rb`, `lib/bazaar/application.rb`,
`lib/releases_list.rb` and `lib/appstream_description_render.rb`.
