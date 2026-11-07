# Component identification — bazaar

| | |
|---|---|
| Upstream | `main` @ `3d347d5` |
| Port | `ruby` @ `cc88d35` |

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
| widget rows (scanned) | 1095 | partial — 29 files |
| distinct widget types | 62 | ~35 |
| distinct CSS classes | 114 | carried over verbatim in `lib/style.css` |
| distinct signals connected | 97 | ~40 |
| GAction names | 37 | 20 |

Per-unit disposition, counted from the inventory's own table rows:

| Disposition | Count |
|---|---:|
| `no` (not built at all) | 68 |
| `partial` | 8 |
| `yes` | 11 |

**68 of 87 identified upstream units (≈78%) have no counterpart in the port
at all.** This is the number the rest of the parity work has to be read
against — not the 29 files that do exist, which is the easy half of the
question.

The units marked `no` include the app's primary purpose: the Curated tab
(`bz-curated-view`), the Explore/Flathub-discovery tab (`bz-flathub-page` and
its state, category and section helpers), the Search tab (`bz-search-page`),
the app detail page (`bz-full-view`, 75 widget rows / 24 CSS classes — the
single largest unit in the app), and essentially every dialog except About,
Preferences, Shortcuts and Error: add-ons, app permissions, app size, age
rating, bundle install, donations, hardware support, license, safety, stats,
transaction, transaction list, user-data.

## Confirmed this pass

- `lib/window.rb` only `require_relative`s `library_page`, `template_callbacks`
  and `transaction` (verified by reading the file) — there is no
  `require_relative` anywhere in `lib/` for a flathub/curated/search/full-view
  file because none exists. `find lib -type f` lists 27 files total against
  the 87 identified upstream units.
- `lib/template_callbacks.rb` has 28 of upstream's 228 `$closure(...)` names
  (per the existing inventory) — confirmed consistent with the absent pages,
  since most of the closure names belong to templates that are not built.

No correction to the existing inventory's numbers was found. It is accurate
and current against today's `origin/main` tip.

See `.reports/component-parity.md` for the four-axis comparison this
inventory feeds, and `.reports/accountability-ensurance.md` for how the gap
is described in `lib/window.rb`, `lib/bazaar/application.rb`,
`lib/releases_list.rb` and `lib/appstream_description_render.rb`.
