# Component parity — bazaar

| | |
|---|---|
| Upstream | `main` @ `3d347d5` |
| Port | `ruby` @ `cc88d35` |
| Units with parity | 0 / 87 (strict) — see note below |

No unit in this port is marked `parity` under this skill's definition: "every
row says `parity`, the stylesheet and messages lines are clean, and the
driven line has no ✗." Several of the built units come close on the widget
axis but every one of them fails the text axis, because the port carries no
translation markers at all (`.reports/translation-parity.md`: 0 of ~803
upstream messages reproduced). A component cannot have parity while its text
axis is unconditionally failing, so the honest count is 0/87.

## Step 1–2: inventory and file mapping

Taken from `.reports/component-identification.md` and
`.reports/component-inventory.md`, which already do this work per-unit.
87 units identified upstream (one application class, one window, 4 pages, 18
dialogs, dozens of tiles/widgets/helpers). 68 have no port file opposite them
at all; 8 are partial; 11 are built.

## Step 3: built units, compared on the four axes

### Unit: library page — `src/bz-library-page.blp/.c/.h` → `lib/library_page.rb`

| Widget | Up × | Port × | CSS | Signals | Text | Verdict |
|---|---:|---:|---|---|:-:|---|
| (32 widget rows per inventory scan) | 32 | ~32 | ✓ carried in `lib/style.css` | ✓ (driven: content/no-results/search states all fire, see `test/drive_bazaar.rb` steps 0, 7–13) | ✗ — no `_()`/`N_()` anywhere in `lib/`; every label is a bare English literal | **gap** on text axis only |

Behaviour is driven and passes (`DRIVE OK`, 58/58 checks — see
`.reports/test-parity.md`). Widget/CSS/signal axes read clean from the scan
and the drive. Text axis fails uniformly, as it does for every unit below.

### Unit: window shell — `src/bz-window.blp/.c/.h` → `lib/window.rb`

| Axis | Verdict |
|---|---|
| Widget count | **gap** — upstream's `Adw.ViewStack` carries 4 pages (Curated/browse, Explore/flathub, Library/installed, Search); the port's stack carries 1 (Library only). `lib/window.rb:25` states this directly (quoted in `.reports/accountability-ensurance.md`) |
| Actions | **gap** — upstream installs 13 `window.*` actions; `lib/bazaar/application.rb:159`'s own comment says pages that are not built get an insensitive menu item instead of an installed action. Scan-visible GAction count: 20 of 37 app+window actions |
| CSS | partial — stylesheet is carried over verbatim (114 classes upstream, same file in the port), but classes that belong only to the unbuilt pages (`search-box`, `search-grid`, `app-context-bar`, `full-view-addons`, …) are defined and never attached, because nothing in `lib/` builds those widgets |
| Text | **gap** — same as above |

### Units: about dialog, shortcuts dialog, preferences dialog, error dialog

All four are present, scan clean on widget/CSS/signal axes, and are driven
by `test/drive_bazaar.rb` (about, shortcuts, preferences all have explicit
steps; error dialog is exercised via the failed-transaction step). All four
fail the text axis — none of their labels go through a translation marker.

### The 68 units with no port file at all

Each is a gap by definition — there is nothing to compare on any axis. The
largest, in order of upstream widget-row count (from
`.reports/component-inventory.md`):

| Upstream | Widget rows | What is missing, as a user experiences it |
|---|---:|---|
| `src/bz-full-view.*` | 75 | Opening any app's detail page — description, screenshots, install button, context tiles, share, developer badge — does not exist |
| `src/bz-search-page.*` | 35 | The Search tab (one of 4 top-level views) does not exist |
| `src/bz-flathub-page.*` | 35 | The Explore tab — the app's actual discovery/storefront surface — does not exist |
| `src/bz-inspector.*` | 104 | Debug inspector window absent (lower priority — debug-only) |
| `src/bz-curated-view.*` | 8 | The Curated tab does not exist |
| 13 remaining dialogs (addons, app-permissions, app-size, age-rating, bundle-install, donations, hardware-support, license, safety, stats, transaction, transaction-list, user-data) | — | None of these dialogs can be opened; the actions that would open them are either absent or installed-but-insensitive per `lib/bazaar/application.rb:159` |

## Step 4: stylesheet

`lib/style.css` is the same file carried over (per the existing inventory).
Classes belonging to built widgets render correctly. Classes belonging to
the 68 unbuilt units are defined in the stylesheet and attached by nothing —
not a rule mismatch, an attachment gap, and it will stay one until those
units are built.

## Step 5: behaviour actually fires

Driven and confirmed via `nix develop --command xvfb-run -a ruby
test/drive_bazaar.rb` (ran during this audit): `DRIVE OK`, 26/26 plain checks
+ 32/32 widget-driving checks across 23 steps. Every signal this drives,
fires correctly. But the drive only reaches the ~15 units listed as built
above — see `.reports/test-parity.md` for why the other 72 units are
unverified by any check, not merely unported.

## Rules re-affirmed

- Nothing here is excused by `PORTING.md`-equivalent prose; this port keeps
  no such file, and the three in-code notes that come closest
  (`lib/window.rb:25`, `lib/bazaar/application.rb:159`,
  `lib/releases_list.rb:13`, `lib/appstream_description_render.rb:18`) are
  logged as excuses, not authority, in `.reports/accountability-ensurance.md`.
- The house-style absence of `.ui`/`.blp` files is a correspondence, not a
  gap, and is not counted above.
- A class that exists in both stylesheets but is attached on neither side
  because the widget is unbuilt is one gap (the widget), not two.
