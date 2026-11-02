# bazaar — upstream component inventory

Survey of the components the Ruby port on `ruby` must grow, read off
`origin/main` (C + blueprint upstream) with the `component-identification`
skill. No app code was written in this step.

## How this was produced

- `git ls-tree -r --name-only origin/main` for the file list.
- Every `.blp` read first, per the skill: on this upstream the blueprints *are*
  the component map. 59 of the 60 declarative files use `template $BzFoo:`;
  only `src/shortcuts-dialog.blp` declares a bare top-level named object
  (`Adw.ShortcutsDialog shortcuts_dialog`).
- `component-scan.sh` over `src/` with the GIR symbol table, then the C files
  read for the `G_DEFINE_TYPE` parent of each class (that is what decides
  "page" vs "dialog" vs "tile" here, not the file name).

## Totals

| | upstream `src/` | port `lib/` on `ruby` |
|---|---:|---:|
| widget rows | 1095 | 0 |
| distinct widget types | 62 | 4 |
| distinct CSS classes | 114 | 0 |
| distinct signals connected | 97 | 1 |
| GAction names (scan-visible) | 37 | 0 |
| declarative UI files (`.blp`) | 60 | n/a (house style builds in code) |
| `lib/*.rb` component files | — | 0 |

The port is a skeleton: `lib/bazaar.rb`, `lib/bazaar/rb/version.rb` and
`lib/bazaar/application.rb`, the last being an `Adw.ApplicationWindow` holding
one `Adw.StatusPage` that reads "The Ruby port has not been written yet."
**Every component below is absent.** `lib/bazaar/application.rb` is the single
partial: it has the `Gtk::Application` + window + `Adw::ToolbarView` +
`Adw::HeaderBar` shell and none of upstream's 13 app actions, 6 accelerators,
menus or daemon mode.

House shape, from the pilot at `gnome-contacts-rb`: one upstream unit becomes
one flat `lib/<thing>.rb` holding a plain top-level class, `# frozen_string_literal: true`
then `require 'adwaita'` then `require_relative` siblings, a comment naming the
upstream file, widgets as memoized accessors configured in `.tap`. The
application class alone lives at `lib/bazaar/application.rb`.

Pairing rule applied throughout: `src/bz-foo.blp` + `src/bz-foo.c` + `src/bz-foo.h`
are **one** component and become **one** `lib/foo.rb`. Where that is not 1:1 it
is called out in the Notes column.

## Shell and application

| Upstream | → `lib/` | Kind | Present | Notes |
|---|---|---|---|---|
| `src/bz-application.c/.h`, `src/main.c`, `src/bazaar-daemon.c` | `lib/bazaar/application.rb` | application | partial | `AdwApplication` subclass. 13 actions: `flathub-login`, `flathub-logout`, `flathub-favorites`, `quit`, `preferences`, `about`, `sync-remotes`, `search` (`s`), `show-app-id` (`s`), `donate`, `bazaar-inspector`, `toggle-debug-mode`, `open-location` (`s`). 6 accels: `<primary>q`, `<primary>comma`, `<primary>r`, `<primary>f` (`app.search('')`), `<primary><alt><shift>i`, `<primary><alt>d`. CLI options `--help --no-window --extra-blocklist --extra-curated-config --extra-content-config --search-for`; `--no-window` is daemon mode |
| `src/bz-window.blp/.c/.h` | `lib/window.rb` | window | no | `AdwApplicationWindow`, 1220×900, min 360×294. `Gtk.Overlay` → `Adw.ToolbarView` → `Adw.BreakpointBin` (`max-width: 700px`) → `Adw.ToastOverlay` → `Adw.NavigationView` → `Adw.ToolbarView` → `Gtk.Stack` (`loading` / `main`) → `Adw.ViewStack` with 4 pages: browse/Curated, flathub/Explore, installed/Library (badge = n available updates), search/Search. Top bar: debug `Gtk.Box` (`bz-debug`) + bug button, account `Gtk.MenuButton` (`circular`, `flat`) with `Adw.Avatar`, busy `Gtk.Revealer` + `Adw.Spinner`, `Adw.ViewSwitcher` + title `Gtk.Label`, primary `Gtk.MenuButton`. Three `Adw.Banner`s (donations `bz-donations-banner`, cached-Flathub, metered-connection). Bottom: `Adw.ViewSwitcherBar`. `Gtk.ShortcutController` binds `Escape`, `Back`, `BackSpace`, `<ctrl>g` → `action(escape)`. `Gtk.DropTarget` (copy) for dropped `.flatpak`/`.flatpakref`. 13 `install_action`s: `escape`, `window.user-data`, `window.open-library`, `window.open-flathub-page`, `window.install-group` `(sb)`, `window.remove-group` `(sb)`, `window.cancel-group` `s`, `window.show-group` `s`, `window.addons-group` `s`, `window.bulk-install`, `window.launch-group` `s`, `window.activate-hook-app` `s`, `window.open-user-data-folder` `s` |
| `src/bz-window.blp` (`menu primary_menu`, `account_menu`, `debug_menu`) | `lib/window.rb` | menu | no | primary: 4 sections — Donate; Refresh / Login With Flathub (`hidden-when: action-disabled`) / Manage Leftover User Data; Preferences / Keyboard Shortcuts / About; Quit. account: Favorites; Log Out. debug: Open Bazaar Inspector |
| `src/shortcuts-dialog.blp` | `lib/shortcuts_dialog.rb` | shortcuts | no | Standalone `Adw.ShortcutsDialog`, no backing `.c`. 3 `Adw.ShortcutsSection`s — Navigation (Open Explore `<Control>e`, Open Library `<Control>d`, Open Search), Remotes (Sync Remotes), General (Preferences, Show Shortcuts, Close Window `<Control>w`, Quit) |
| `src/bz-application.c` (`about` action) | `lib/about_dialog.rb` | dialog | no | `Adw.AboutDialog`, release notes from `src/release-notes.xml.in` |
| `src/bz-preferences-dialog.blp/.c/.h` | `lib/preferences_dialog.rb` | preferences | no | `AdwPreferencesDialog`, 19 widgets: `Adw.PreferencesPage`, `Adw.PreferencesGroup`s, `Adw.SwitchRow`s and `Adw.ComboRow`-style rows over the GSettings keys below |
| `src/bz-inspector.blp/.c/.h` | `lib/inspector.rb` | window | no | `AdwWindow`. The largest single unit: 104 widget rows, 8 CSS classes. Debug inspector behind `app.bazaar-inspector` |
| `src/bz-entry-inspector.blp/.c/.h` | `lib/entry_inspector.rb` | window | no | `AdwWindow`, 18 widgets. Per-entry debug view |
| `src/template-callbacks.c/.h` | `lib/template_callbacks.rb` | helpers | no | The blueprint closure library. 228 distinct `$closure(...)` names are referenced across the 60 blueprints (`$format_title`, `$invert_boolean`, `$logical_and`, `$is_null`, `$choose_object`, …). In the port these become plain Ruby methods plus explicit `notify::` handlers |

## Pages

| Upstream | → `lib/` | Kind | Present | Scan (widgets/css/signals) |
|---|---|---|---|---|
| `src/bz-curated-view.blp/.c/.h` | `lib/curated_view.rb` | page | no | 8/1/3 + 1/0/2 — `AdwBin`. The Curated tab; `browse-flathub` signal; `Adw.StatusPage` empty state |
| `src/bz-flathub-page.blp/.c/.h` | `lib/flathub_page.rb` | page | no | 35/12/1 + 2/0/3 — `AdwBin`. The Explore tab; `open-search` signal; `Adw.StatusPage` for offline/error |
| `src/bz-library-page.blp/.c/.h` | `lib/library_page.rb` | page | no | 32/10/6 + 1/0/2 — `AdwBin`. The Library tab; `update` signal; `installed-list-view`, `installed-section`, `installed-pill`, `installed-size` CSS; `Adw.StatusPage` for "nothing installed" |
| `src/bz-search-page.blp/.c/.h` | `lib/search_page.rb` | page | no | 35/9/6 + 2/1/14 — `AdwBin`. The Search tab; 14 signals, the busiest C file; `search-box`, `search-grid` CSS; `Adw.StatusPage` for no results |
| `src/bz-full-view.blp/.c/.h` | `lib/full_view.rb` | page | no | 75/24/4 + 3/0/0 — `AdwBin`. The app detail page: second-largest unit, 24 CSS classes (`app-context-bar`, `app-developer`, `app-title`, `full-view-addons`, …), hosts context tiles, screenshots carousel, install controls, share list, developer badge |
| `src/bz-all-apps-page.blp/.c/.h` | `lib/all_apps_page.rb` | page | no | 6/1/0 — `AdwNavigationPage` |
| `src/bz-apps-page.blp/.c/.h` | `lib/apps_page.rb` | page | no | 13/4/1 + 2/0/0 — `AdwNavigationPage` |
| `src/bz-favorites-page.blp/.c/.h` | `lib/favorites_page.rb` | page | no | 11/4/3 + 1/0/1 — `AdwNavigationPage`; `Adw.StatusPage` for no favourites |
| `src/bz-login-page.blp/.c/.h` | `lib/login_page.rb` | page | no | 16/2/1 + 5/1/2 — `AdwNavigationPage`. Flathub login; `Adw.StatusPage` error state built in C |
| `src/bz-user-data-page.blp/.c/.h` | `lib/user_data_page.rb` | page | no | 8/2/0 + 1/0/2 — `AdwNavigationPage`, reached by `window.user-data`; `user-data-list-view` CSS; `Adw.StatusPage` empty state |
| `src/bz-screenshot-page.blp/.c/.h` | `lib/screenshot_page.rb` | page | no | 22/5/1 + 2/0/6 — `AdwBin`. Fullscreen screenshot viewer; actions `screenshot.copy`, `.next`, `.previous`, `.zoom-in`, `.zoom-out`, `.zoom-reset` |
| `src/bz-metainfo-preview-page.blp` + `src/bz-metainfo-preview.c/.h` | `lib/metainfo_preview.rb` | page | no | 9/2/0 + 1/0/0 — blueprint and source are named differently; one component |
| `src/bz-article.blp/.c/.h` | `lib/article.rb` | page | no | 11/3/1 + 5/3/3 — `AdwNavigationPage`; `article`, `article-image-button` CSS; `Adw.StatusPage` |

## Dialogs

| Upstream | → `lib/` | Kind | Present | Scan |
|---|---|---|---|---|
| `src/bz-addons-dialog.blp/.c/.h` | `lib/addons_dialog.rb` | dialog | no | 37/13/1 + 2/0/1 — `AdwDialog`, reached by `window.addons-group`; `Adw.StatusPage` for no addons |
| `src/bz-age-rating-dialog.blp/.c/.h` | `lib/age_rating_dialog.rb` | dialog | no | 7/1/0 + 1/0/0 — `AdwDialog`; spec in `src/bz-age-rating-attribute.txt`; 25 ratings icons |
| `src/bz-app-size-dialog.blp/.c/.h` | `lib/app_size_dialog.rb` | dialog | no | 22/5/2 + 3/0/0 — `AdwBin` presented as a dialog |
| `src/bz-bundle-install-dialog.blp/.c/.h` | `lib/bundle_install_dialog.rb` | dialog | no | 60/13/2 + 2/0/0 — `AdwDialog`. Third-largest unit; the drag-and-drop/`.flatpakref` install flow; `Adw.StatusPage` in both halves; result type `src/bz-bulk-install-dialog-result.txt` |
| `src/bz-donations-dialog.blp/.c/.h` | `lib/donations_dialog.rb` | dialog | no | 18/4/1 + 1/0/1 — `AdwDialog`, `bz-donations-dialog` CSS, `app.donate` |
| `src/bz-error-dialog.blp/.c/.h` | `lib/error_dialog.rb` | error state | no | 11/4/1 + 1/0/0 — `AdwDialog`. The app's one generic error surface; pairs with `src/error.c` |
| `src/bz-hardware-support-dialog.blp/.c/.h` | `lib/hardware_support_dialog.rb` | dialog | no | 7/1/0 + 1/0/1 — `AdwDialog`; the `device-support-*` icons |
| `src/bz-license-dialog.blp/.c/.h` | `lib/license_dialog.rb` | dialog | no | 16/1/1 + 3/0/0 — `AdwBin`; SPDX names from `src/spdx.c` |
| `src/bz-safety-dialog.blp/.c/.h` | `lib/safety_dialog.rb` | dialog | no | 19/5/1 + 5/0/1 — `AdwBin`; rows from `src/bz-safety-row.txt`, scores from `src/safety-calculator.c`; `app-safety-ok/unknown/unsafe` icons |
| `src/bz-stats-dialog.blp/.c/.h` | `lib/stats_dialog.rb` | dialog | no | 11/2/0 + 1/0/0 — `AdwBreakpointBin`; hosts the world map and data graph |
| `src/bz-transaction-dialog.c/.h` | `lib/transaction_dialog.rb` | dialog | no | 11/1/0 — **no blueprint**, built entirely in C; result type `src/bz-transaction-dialog-result.txt` |
| `src/bz-transaction-list-dialog.blp/.c/.h` | `lib/transaction_list_dialog.rb` | dialog | no | 11/3/0 + 1/0/1 — `AdwAlertDialog` |
| `src/bz-releases-dialog.blp` + `src/bz-releases-list.blp/.c/.h` | `lib/releases_list.rb` | dialog | no | 5/1/0 + 5/1/1 + 12/5/0 — **two blueprints, one source**: the `.c` defines both an `AdwDialog` and an `AdwBin` type. Release data from `src/bz-release.txt` |

## Tiles and rows

| Upstream | → `lib/` | Kind | Present | Scan |
|---|---|---|---|---|
| `src/bz-list-tile.c/.h` | `lib/list_tile.rb` | widget (base) | no | 2/2/1 — `GtkWidget` subclass with custom measure/allocate; the parent of 6 tiles below |
| `src/bz-app-tile.blp/.c/.h` | `lib/app_tile.rb` | tile | no | 12/7/0 + 1/0/0 — `GtkButton` **plus a private `GtkLayoutManager` subclass** in the same file; `app-tile`, `lowres-icon` |
| `src/bz-addon-tile.blp/.c/.h` | `lib/addon_tile.rb` | tile | no | 8/5/1 + rows — `BzListTile` subclass |
| `src/bz-article-tile.blp/.c/.h` | `lib/article_tile.rb` | tile | no | 6/4/1 + 1/0/0 — `BzListTile` subclass |
| `src/bz-category-tile.blp/.c/.h` | `lib/category_tile.rb` | tile | no | 4/3/0 + 1/1/0 — `GtkButton`, `category-tile`; 17 category icons |
| `src/bz-context-tile.blp/.c/.h` + `src/context-tile-callbacks.c/.h` | `lib/context_tile.rb` | tile | no | 4/5/0 + 2/0/3 — `GtkButton`; `context-tile`, `context-tile-text`; **three** upstream files to one port file |
| `src/bz-curated-app-tile.c` | `lib/curated_app_tile.rb` | tile | no | 1/0/0 — `AdwBin`, no blueprint, no header |
| `src/bz-favorites-tile.blp/.c/.h` | `lib/favorites_tile.rb` | tile | no | 10/7/1 + 1/1/0 — `BzListTile` subclass, `favorite` |
| `src/bz-featured-tile.blp/.c/.h` | `lib/featured_tile.rb` | tile | no | 10/4/0 + 1/0/2 — `GtkButton` **plus a private layout manager**; `featured-tile` |
| `src/bz-installed-tile.blp/.c/.h` | `lib/installed_tile.rb` | tile | no | 10/8/1 — `BzListTile`; installs actions `installed-tile.install-addons`, `installed-tile.permissions` |
| `src/bz-rich-app-tile.blp/.c/.h` | `lib/rich_app_tile.rb` | tile | no | 15/8/2 — `BzListTile`; `rich-tile-card`, `rich-screenshot-box` |
| `src/bz-transaction-tile.blp/.c/.h` | `lib/transaction_tile.rb` | tile | no | 44/24/1 — `BzListTile`. Most CSS-heavy single file (24 classes) |
| `src/bz-user-data-tile.blp/.c/.h` | `lib/user_data_tile.rb` | tile | no | 11/5/1 + 1/0/1 — `AdwBin` |
| `src/bz-entry-selection-row.blp/.c/.h` | `lib/entry_selection_row.rb` | row | no | 3/0/0 + 1/0/0 — `AdwActionRow` |
| `src/bz-context-row.c/.h` | `lib/context_row.rb` | row | no | 2/1/0 — no blueprint |

## Views, sections and controls

| Upstream | → `lib/` | Kind | Present | Scan |
|---|---|---|---|---|
| `src/bz-banner-view.blp/.c/.h` | `lib/banner_view.rb` | view | no | 2/1/0 + 1/1/1 — `AdwBin`; spec `src/bz-curated-banner.txt` |
| `src/bz-featured-carousel.blp/.c/.h` | `lib/featured_carousel.rb` | view | no | 4/5/6 + 1/2/2 — `GtkBox`, `featured-carousel`, `carousel-box` |
| `src/bz-featured-carousel-view.c/.h` | `lib/featured_carousel_view.rb` | view | no | 1/0/0 — `AdwBin`, no blueprint; spec `src/bz-curated-featured-carousel.txt` |
| `src/bz-flathub-category-section.blp/.c/.h` | `lib/flathub_category_section.rb` | section | no | 2/3/1 + 2/0/0 — `GtkBox` |
| `src/bz-flathub-curated-section.blp/.c/.h` | `lib/flathub_curated_section.rb` | section | no | 4/5/0 + 1/0/0 — `AdwBin`; `flathub-page-section`, `flathub-gunmetal`, `flathub-lotion` |
| `src/bz-section-view.blp/.c/.h` | `lib/section_view.rb` | view | no | 7/2/1 + 2/0/0 — `AdwBin`; spec `src/bz-curated-section.txt` |
| `src/bz-row-view.c/.h` | `lib/row_view.rb` | view | no | 1/0/0 — `AdwBin`, no blueprint; spec `src/bz-curated-row.txt` |
| `src/bz-article-list-view.c/.h` | `lib/article_list_view.rb` | view | no | 1/0/1 — `AdwBin`, no blueprint; `src/article-list-schema.xml` |
| `src/bz-dynamic-list-view.c/.h` | `lib/dynamic_list_view.rb` | view | no | 13/2/5 — `AdwBin`, no blueprint. The recycling list host used by every page; installs `list.scroll-to-item` |
| `src/bz-install-controls.blp/.c/.h` + `src/bz-install-controls.wdgt` | `lib/install_controls.rb` | control | no | 15/4/1 + 1/2/3 — `GtkBox`. The install/remove/cancel button cluster; its icon is a **`.wdgt` bge spec**, not a widget tree |
| `src/bz-updates-card.blp/.c/.h` | `lib/updates_card.rb` | card | no | 5/2/1 + 8/2/3 — `AdwBin` |
| `src/bz-search-bar.blp/.c/.h` | `lib/search_bar.rb` | control | no | 6/4/5 + 2/1/0 — `GtkWidget` subclass (custom allocate); `searchbar-button`, `search-box` |
| `src/bz-search-filter-popover.blp/.c/.h` | `lib/search_filter_popover.rb` | popover | no | 11/1/1 + 3/1/5 — `GtkPopover`; the FOSS / Flathub-only / verified / EOL filters, backed by GSettings |
| `src/bz-search-pill-list.c/.h` | `lib/search_pill_list.rb` | control | no | 2/2/1 — `GtkBox`, no blueprint; `search-pill` |
| `src/bz-subcategory-list.c/.h` | `lib/subcategory_list.rb` | control | no | 3/1/1 — `GtkBox`, no blueprint; spec `src/bz-flathub-sub-category.txt` |
| `src/bz-share-list.c/.h` | `lib/share_list.rb` | control | no | 10/1/2 — `GtkBox`, no blueprint; the `share-symbolic` / `share-alt-symbolic` menu |
| `src/bz-screenshots-carousel.blp/.c/.h` | `lib/screenshots_carousel.rb` | view | no | 12/10/3 + 1/2/3 — `GtkWidget` subclass; `screenshot-carousel`, `-dark`, `-light` |
| `src/bz-decorated-screenshot.blp/.c/.h` | `lib/decorated_screenshot.rb` | widget | no | 2/2/0 + 1/0/2 — `GtkButton`; `decorated-screenshot` |
| `src/bz-screenshot.c/.h` | `lib/screenshot.rb` | widget | no | 1/0/3 — `GtkWidget` subclass, custom snapshot |
| `src/bz-appstream-description-render.blp/.c/.h` | `lib/appstream_description_render.rb` | widget | no | 3/0/0 + 1/1/4 — `AdwBin`; renders AppStream description markup; pairs with `src/bz-appstream-parser.c` and `src/bz-newline-parser.c` |
| `src/bz-developer-badge.blp/.c/.h` | `lib/developer_badge.rb` | widget | no | 6/2/3 + 1/2/0 — `GtkBox`; `developer-badge`, `verified`; spec `src/bz-verification-status.txt` |
| `src/bz-favorite-button.blp/.c/.h` | `lib/favorite_button.rb` | widget | no | 4/3/1 + 6/1/1 — `GtkButton`; `bookmark-filled`/`bookmark-outline`/`heart-*` icons |
| `src/bz-progress-bar.blp/.c/.h` + `src/progress-bar-designs/` | `lib/progress_bar.rb` | widget | no | 1/0/0 + 1/0/0 — `AdwBin`, themed by `global-progress-bar-theme`; the `pride` design is a separate C module driven by `pride-flags.yaml` + `src/bz-pride-flag-*.txt` |
| `src/bz-transact-icon.c/.h` + `src/bz-transact-icon.wdgt` | `lib/transact_icon.rb` | widget | no | 2/1/8 — `AdwBin`; spec `src/bz-transact-icon-info.txt`; icon is a **`.wdgt` bge spec** |
| `src/bz-lozenge.c/.h` | `lib/lozenge.rb` | widget | no | 6/3/0 — `GtkBox`, no blueprint; `lozenge`, `circular-lozenge`, `lozenge-ring-button` |
| `src/bz-data-graph.c/.h` | `lib/data_graph.rb` | widget | no | 8/8/8 — `GtkWidget` subclass drawing its own chart; `src/bz-data-point.txt`, `bz-linear-function.txt`, `bz-exponential-function.txt` |
| `src/bz-world-map.c/.h` + `src/bz-world-map-parser.c/.h` | `lib/world_map.rb` | widget | no | 7/6/7 — `GtkWidget` subclass; needs `countries.gvariant`, generated by `scripts/countries.py` from `scripts/countries.json.in`; `src/bz-country.txt`, `bz-country-data-point.txt` |
| `src/bz-aspect-picture.c/.h` | `lib/aspect_picture.rb` | widget | no | 1/0/2 — `GtkWidget` subclass, custom measure |
| `src/bz-rounded-picture.c/.h` | `lib/rounded_picture.rb` | widget | no | 1/0/2 — `GtkWidget` subclass, rounded-clip snapshot |
| `src/bz-fading-clamp.c/.h` | `lib/fading_clamp.rb` | widget | no | 2/0/0 — `GtkWidget` subclass with a mask-node snapshot |
| `src/bz-themed-entry-group-rect.c/.h` | `lib/themed_entry_group_rect.rb` | widget | no | 2/0/1 — `GtkWidget` subclass |
| `src/bz-lazy-wdgt.c/.h` | `lib/lazy_wdgt.rb` | widget | no | 1/0/0 — `AdwBin` that defers building its child |
| `src/bz-zoom.c/.h` | `lib/zoom.rb` | controller | no | 2/0/8 — pinch/scroll zoom behaviour for the screenshot page |
| `src/bz-group-tile-css-watcher.c/.h` | `lib/group_tile_css_watcher.rb` | behaviour | no | 1/0/1 — `GObject` that attaches/removes CSS classes on tiles as entry state changes. The dynamic-CSS source for the tile classes above |
| `src/transaction-notification.c/.h` | `lib/transaction_notification.rb` | notification | no | `GNotification`s for finished/failed transactions |
| `src/bz-application-map-factory.c/.h` | `lib/application_map_factory.rb` | factory | no | 1/0/0 — builds the per-entry widgets handed to `BzDynamicListView` |
| `src/shell-search-provider-dbus-interfaces.xml`, `data/dbus/*`, `data/*.search-provider.ini.in` | `lib/shell_search_provider.rb` | service | no | GNOME Shell search provider; the pilot has a `shell_search_provider.rb` to copy from |

## Non-UI layer the components depend on

Not user-facing in themselves, but no page above works without them. Listed
so the port plan has somewhere to put them.

| Upstream | → `lib/` | Kind |
|---|---|---|
| `src/bz-state-info.txt` (53-property codegen spec) | `lib/state_info.rb` | model |
| `src/bz-entry.c/.h`, `src/bz-entry-group.c/.h`, `src/bz-entry-group-util.c/.h` | `lib/entry.rb`, `lib/entry_group.rb` | model |
| `src/bz-backend.c/.h`, `src/bz-flatpak-entry.c/.h`, `src/bz-flatpak-instance.c/.h`, `src/bz-flatpak-private.h` | `lib/backend.rb`, `lib/flatpak_backend.rb` | service |
| `src/bz-transaction.c/.h`, `src/bz-transaction-manager.c/.h` | `lib/transaction.rb`, `lib/transaction_manager.rb` | service |
| `src/bz-search-engine.c/.h`, `src/search-index.c/.h`, `src/search-index-write.c/.h` | `lib/search_engine.rb` | service |
| `src/bz-content-provider.c/.h`, `src/bz-curated-*.txt`, `src/curated-config-schema.xml` | `lib/content_provider.rb` | service |
| `src/bz-flathub-state.c/.h`, `src/bz-flathub-category.c/.h`, `src/bz-auth-state.c/.h` | `lib/flathub_state.rb`, `lib/auth_state.rb` | service |
| `src/bz-app-permissions.c/.h`, `src/safety-calculator.c/.h`, `src/bz-malcontent-service.c/.h`, `src/spdx.c/.h` | `lib/app_permissions.rb`, `lib/safety_calculator.rb` | model |
| `src/bz-appstream-parser.c/.h`, `src/bz-yaml-parser.c/.h`, `src/bz-parser.c/.h`, `src/bz-newline-parser.c/.h`, `src/bz-serializable.c/.h` | `lib/appstream_parser.rb`, … | parser |
| `src/bz-async-texture.c/.h`, `src/bz-entry-cache-manager.c/.h`, `src/bz-download-worker.c/.h`, `src/dl-worker.c`, `src/global-net.c/.h` | `lib/async_texture.rb`, … | service |
| `src/update-worker.c/.h`, `src/refresh-worker.c/.h` | `lib/update_worker.rb`, `lib/refresh_worker.rb` | service |
| `src/hooks.c/.h`, `src/bz-hook*.txt` | `lib/hooks.rb` | service |
| `src/bz-blocklist*.txt`, `src/blocklist-schema.xml` | `lib/blocklist.rb` | model |
| `src/env.c/.h`, `src/io.c/.h`, `src/error.c/.h`, `src/util.c/.h`, `src/dex-utils.c/.h` | `lib/env.rb`, `lib/io.rb`, … | support |

## Resources to carry over

| Upstream | Notes |
|---|---|
| `data/io.github.kolunmi.Bazaar.gschema.xml` | 16 keys: `hide-eol`, `show-only-foss`, `show-only-flathub`, `show-only-verified`, `global-progress-bar-theme`, `window-dimensions` `(ii)`, `force-adwaita-icons`, `show-permission-banner`, `check-for-ubuntu`, `auto-update`, `auto-update-notifications`, `last-update-check`, `update-check-hour-offset`, `last-refresh-time`, `last-stale-notification` |
| `src/bazaar.gresource.xml` | 60 `.ui` files (dropped — the port builds in code), `style.css`, `internal-config.yaml`, 6 XML schemas, `release-notes.xml`, `countries.gvariant`, 2 `.wdgt` files, ~175 SVG icons (75 action icons, 25 content-rating icons, 17 category icons, 5 service icons) |
| `src/style.css` | 114 distinct CSS classes used across the blueprints; the port needs this stylesheet verbatim or the app is grey |
| `po/` | 31 catalogues (`ar be bg bs cs de el es eu fa_IR fi fr ga hu id it ja ka kw nl pl pt pt_BR ru sl sv tr uk vi zh_CN zh_TW`) over 160 `POTFILES.in` entries. Upstream uses `_()` and `C_("shortcut window", …)` |
| `data/io.github.kolunmi.Bazaar.metainfo.xml.in`, `.desktop.in`, `.service.in`, `src/bazaar-autostart.desktop` | app metadata, D-Bus activation, autostart for daemon mode |
| `src/icons/` + `data/icons/` | app icon, devel icon, symbolic icon, plus the in-resource icon set above |

## Blockers

1. **`bge/` — the vendored widget engine.** 30 files implementing `BgeCarousel`,
   `BgeMarkdownRender`, an animation framework, and a whole declarative widget
   language (`bge/wdgt/`: a spec parser, easing, renderer, snapshot and
   transform lookup). `src/bz-install-controls.wdgt` and
   `src/bz-transact-icon.wdgt` are authored in that language, and both are
   on-screen in the app's most-used control. Nothing in the Ruby bindings
   corresponds to it; either reimplement the two widgets by hand in Ruby or
   port the engine.
2. **Custom `GtkWidget` subclasses.** 12 components override `measure`,
   `size_allocate` and/or `snapshot` (`bz-list-tile`, `bz-aspect-picture`,
   `bz-rounded-picture`, `bz-fading-clamp`, `bz-screenshot`,
   `bz-screenshots-carousel`, `bz-themed-entry-group-rect`, `bz-world-map`,
   `bz-data-graph`, `bz-search-bar`, plus two private `GtkLayoutManager`
   subclasses inside `bz-app-tile.c` and `bz-featured-tile.c`). Whether Ruby
   GTK4 can subclass `Gtk::Widget` with virtual-function overrides and build
   `Gsk` render nodes must be settled against the `ruby-gtk` skill before any
   of these is planned; several may have to become composed widgets instead.
3. **libdex.** `DexFuture` async is pervasive (`src/dex-utils.c`, every worker,
   the backend). No Ruby binding exists; needs replacing with threads plus
   `GLib::Idle`, which changes the shape of the backend layer.
4. **No Ruby bindings for libflatpak, libmalcontent or libappstream.** The
   entire install/remove path, parental controls and metadata parsing sit on
   these. Either drive them through GObject-Introspection from Ruby or shell
   out to `flatpak(1)`; this decision gates the Library, Explore and full-view
   pages.
5. **Blueprint `bind` closures.** 228 distinct `$closure(...)` names across the
   60 blueprints, many nested (`$logical_and($invert_boolean(...), ...)`).
   `Gtk::Expression` is thin in the Ruby bindings, so every one becomes an
   explicit `notify::` handler — this is the single largest mechanical cost in
   the port and should be budgeted per unit.
6. **53 `gen_gobject.sh` codegen specs** (`src/bz-*.txt`) produce GObject
   classes with properties the blueprints bind to by name. In Ruby these are
   plain classes with `attr_accessor`, but the property *names* and types have
   to be read out of the specs, not guessed.
7. **Generated resources.** `countries.gvariant` (`scripts/countries.py`),
   `release-notes.xml`, the 6 GSettings/XML schemas and the GResource bundle
   are all build-time products. The Nix dev shell must compile the schema and
   either bundle or bypass GResource before any page renders.
8. **Scale.** 1095 widget rows, 114 CSS classes, 97 signals, 26 app/window
   actions plus 10 widget-scoped ones, across 86 UI components, against a port
   that currently has one status page. The two largest single units
   (`bz-inspector.blp` at 104 widgets, `bz-full-view.blp` at 75) each exceed
   the whole of the pilot port's biggest file.
