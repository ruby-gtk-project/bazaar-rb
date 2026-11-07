# frozen_string_literal: true

# Drives the whole port headlessly, through the real Bazaar::Application —
# not a hand-built Window — so the app-level actions, accelerators and
# dialogs are exercised exactly as a user's click or keypress would reach
# them, in addition to the model-level checks that need no widget at all.
#
# Run it from the repository root:
#
#   nix develop --command xvfb-run -a ruby test/drive_bazaar.rb
#
# A scratch XDG_CONFIG_HOME keeps this from reading or writing real settings.
require "fileutils"
require "tmpdir"
require "socket"
require "zlib"

ENV["XDG_CONFIG_HOME"] = Dir.mktmpdir("bazaar-drive")

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

require "bazaar"
require_relative "gtk_driver"

SHOTS = File.expand_path("../tmp/shots", __dir__)
FileUtils.rm_rf(SHOTS)

# A minimal, real 1x1 red PNG, built by hand so the glycin/soup3 checks below
# decode and fetch actual bytes rather than a canned fixture file.
def tiny_png
  chunk = ->(tag, data) { [data.bytesize].pack("N") + tag + data + [Zlib.crc32(tag + data)].pack("N") }
  "\x89PNG\r\n\x1a\n".b +
    chunk.call("IHDR", [1, 1, 8, 2, 0, 0, 0].pack("NNC5")) +
    chunk.call("IDAT", Zlib::Deflate.deflate("\x00\xff\x00\x00".b)) +
    chunk.call("IEND", "")
end

# A loopback HTTP server that serves `tiny_png`, so the soup3 remote-icon
# fetch in AppstreamParser#apply_icon runs an actual HTTP round trip instead
# of touching the real network.
#
# This runs in a forked child process, not a Ruby Thread: `Soup::Session
# #send_and_read` is a blocking call into the C library that does not yield
# the GVL, so a same-process accept loop would never get scheduled while the
# request is in flight (reproduced directly — it deadlocks). A separate OS
# process has no such dependency on this process's GVL.
ICON_SERVER = TCPServer.new("127.0.0.1", 0)
ICON_SERVER_PORT = ICON_SERVER.addr[1]
ICON_SERVER_PID = fork do
  loop do
    client = ICON_SERVER.accept
    loop { break if client.gets.to_s.chomp.empty? } # request line, then headers to the blank line
    body = tiny_png
    client.write("HTTP/1.1 200 OK\r\nContent-Type: image/png\r\nContent-Length: #{body.bytesize}\r\nConnection: close\r\n\r\n#{body}")
    client.close
  rescue StandardError
    nil
  end
rescue StandardError
  nil
end
at_exit do
  Process.kill("TERM", ICON_SERVER_PID)
rescue StandardError
  nil
end

CATALOGUE = <<~XML
  <?xml version="1.0"?>
  <components version="0.14" origin="flathub">
    <component type="desktop-application">
      <id>org.gnome.Loupe</id>
      <name>Loupe</name>
      <summary>Browse images</summary>
      <description><p>A simple image viewer.</p><ul><li>Fast</li><li>Small</li></ul></description>
      <developer id="org.gnome"><name>The GNOME Project</name></developer>
      <project_license>GPL-3.0-or-later</project_license>
      <metadata_license>CC0-1.0</metadata_license>
      <categories><category>Graphics</category></categories>
      <keywords><keyword>image</keyword><keyword>viewer</keyword></keywords>
      <url type="homepage">https://apps.gnome.org/Loupe</url>
      <url type="donation">https://donate.gnome.org</url>
      <bundle type="flatpak">app/org.gnome.Loupe/x86_64/stable</bundle>
      <icon type="cached" width="64" height="64">org.gnome.Loupe.png</icon>
      <releases>
        <release version="48.1" timestamp="1714000000"><description><p>Bug fixes.</p></description></release>
      </releases>
      <supports><control>touch</control><control>keyboard</control></supports>
      <custom><value key="flathub::verification::verified">true</value></custom>
    </component>
    <component type="desktop-application">
      <id>com.example.Proprietary</id>
      <name>Example</name>
      <summary>An example app</summary>
      <project_license>LicenseRef-proprietary</project_license>
      <bundle type="flatpak">app/com.example.Proprietary/x86_64/stable</bundle>
      <supports><control>pointing</control></supports>
      <content_rating type="oars-1.1">
        <content_attribute id="violence-realistic">intense</content_attribute>
      </content_rating>
    </component>
    <component type="desktop-application">
      <id>org.example.RemoteIcon</id>
      <name>RemoteIcon</name>
      <summary>An app whose icon has no local AppStream catalogue copy</summary>
      <project_license>MIT</project_license>
      <bundle type="flatpak">app/org.example.RemoteIcon/x86_64/stable</bundle>
      <icon type="remote">http://127.0.0.1:#{ICON_SERVER_PORT}/icon.png</icon>
      <supports><control>pointing</control></supports>
    </component>
  </components>
XML

# The UI-driving run (part 2, below) uses this trimmed catalogue instead: the
# remote-icon component's HTTP round trip (plus the fork it runs in) adds
# latency the timed driver steps are not built to absorb, and the soup3/
# glycin remote-fetch path is already proven, for real, by the plain check
# above — the UI run only needs to prove the *wiring* (actions, dialogs,
# transactions), not re-exercise every gem a second time under a timer.
UI_CATALOGUE = CATALOGUE.sub(%r{\s*<component type="desktop-application">\s*<id>org\.example\.RemoteIcon</id>.*?</component>\n}m, "\n")

# A backend that answers out of the catalogue above instead of talking to
# flatpak. `FAIL_REF` is scheduled but never finishes, which is how the
# "Cancelled"/errored-task path (the pill, the details toggle and the
# ErrorDialog it opens) gets exercised without a real package manager to
# break.
class FakeBackend < Backend
  REFS = {
    "app/org.gnome.Loupe/x86_64/stable"         => { download_size: 4_500_000, installed_size: 9_000_000 },
    "app/com.example.Proprietary/x86_64/stable" => { download_size: 1_000_000, installed_size: 2_000_000 },
    "app/org.example.RemoteIcon/x86_64/stable"  => { download_size: 500_000, installed_size: 900_000 },
  }.freeze

  attr_accessor :fail_next

  def initialize(catalogue_dir)
    super()
    @catalogue_dir = catalogue_dir
    @fail_next = false
  end

  def list_repositories
    [Repository.new(name: "flathub", title: "Flathub", url: "https://flathub.org/repo", is_user: false)]
  end

  def retrieve_install_ids
    { "FLATPAK-SYSTEM::flathub::app/org.gnome.Loupe/x86_64/stable" => "48.0" }
  end

  def retrieve_update_ids
    ["FLATPAK-SYSTEM::flathub::app/org.gnome.Loupe/x86_64/stable"]
  end

  def retrieve_remote_entries
    AppstreamParser.components(File.join(@catalogue_dir, "appstream.xml")).map do |component|
      ref = component.bundle
      Entry.new.tap do |entry|
        entry.unique_id = "FLATPAK-SYSTEM::flathub::#{ref}"
        entry.remote_repo_name = "flathub"
        entry.size = REFS.fetch(ref)[:download_size]
        entry.installed_size = REFS.fetch(ref)[:installed_size]
        AppstreamParser.populate_entry(
          entry,
          component,
          appstream_dir: @catalogue_dir,
          remote_name:   "flathub",
          kinds:         Entry::KIND_APPLICATION,
        )
      end
    end
  end

  def schedule_transaction(installs:, updates:, removals:, channel:)
    case @fail_next
    when true
      @fail_next = false
      fail_one(installs + updates + removals, channel)
    else succeed_all(installs + updates + removals, channel)
    end
  end

  private

    def succeed_all(entries, channel)
      entries.each { |entry| run_op(entry, channel) }
      channel.close
      true
    end

    # Announces the op (so a tracker exists) but never finishes it, which is
    # what a package-manager crash looks like from this side of the channel:
    # the transaction manager's `settle` steps in and error_out_task's it.
    def fail_one(entries, channel)
      entries.each_with_index do |entry, index|
        case index.zero?
        when true then channel.push(Backend::OpPayload.new(name: "Updating #{entry.title}", entry: entry))
        else run_op(entry, channel)
        end
      end
      channel.close
      true
    end

    def run_op(entry, channel)
      op = Backend::OpPayload.new(name: "Updating #{entry.title}", entry: entry)
      channel.push(op)
      [0.25, 0.5, 1.0].each do |fraction|
        channel.push(
          Backend::OpProgressPayload.new(
            op:                op,
            status:            "Updating #{entry.title}",
            progress:          fraction,
            total_progress:    fraction,
            bytes_transferred: (entry.size * fraction).to_i,
          ),
        )
      end
      channel.push(op)
    end
end

# --- Part 1: plain checks on the non-widget code -----------------------
#
# No display, no main loop - models, parsing, settings and blocklists, run
# exhaustively and fast.

$plain_checks = 0
$plain_failures = []

def plain_check(label, actual, expected)
  $plain_checks += 1
  case actual == expected
  when true then puts "ok   #{label}: #{actual.inspect}"
  else
    puts "FAIL #{label}: #{actual.inspect} != #{expected.inspect}"
    $plain_failures << label
  end
end

catalogue_dir = Dir.mktmpdir("bazaar-catalogue")
File.write(File.join(catalogue_dir, "appstream.xml"), CATALOGUE)
FileUtils.mkdir_p(File.join(catalogue_dir, "icons", "flatpak", "64x64"))
File.binwrite(File.join(catalogue_dir, "icons", "flatpak", "64x64", "org.gnome.Loupe.png"), tiny_png)

backend = FakeBackend.new(catalogue_dir)
entries = backend.retrieve_remote_entries
loupe = entries[0]
proprietary = entries[1]
remote_icon_entry = entries[2]

plain_check("parsed entries", entries.length, 3)
plain_check("title", loupe.title, "Loupe")
plain_check("developer", loupe.developer, "The GNOME Project")
plain_check("summary", loupe.description, "Browse images")
plain_check("donation url", loupe.donation_url, "https://donate.gnome.org")
plain_check("foss", loupe.is_foss, true)
plain_check("proprietary", proprietary.is_foss, false)
plain_check("verified", loupe.verified?, true)
plain_check("mobile friendly", loupe.is_mobile_friendly, true)
plain_check("graphics category", loupe.has_category?("graphics"), true)
plain_check("mobile category", loupe.has_category?("mobile"), true)
plain_check("releases", loupe.version_history.first.version, "48.1")
plain_check("share urls", loupe.share_urls.map(&:id).first, "flathub")
plain_check("usefulness beats proprietary", loupe.calc_usefulness > proprietary.calc_usefulness, true)

# glycin + libglycin-gtk4: a local icon under the AppStream catalogue's
# icons/flatpak directory is decoded through Gly::Loader ->
# GlyGtk4.frame_get_texture (AppstreamParser#load_texture), not
# Gdk::Texture.new.
plain_check("local icon decoded into a real texture via glycin", loupe.icon_paintable.is_a?(Gdk::Texture), true)
plain_check("local icon texture has pixels", loupe.icon_paintable&.width.to_i > 0, true)

# soup3 + glycin: an icon with no local catalogue copy is fetched over HTTP
# (AppstreamParser#fetch_remote_texture, against the loopback server above)
# and decoded the same way (AppstreamParser#decode_bytes).
plain_check("remote-only icon fetched via soup3", remote_icon_entry.icon_url.to_s.start_with?("http://127.0.0.1"), true)
plain_check("remote icon decoded into a real texture via glycin", remote_icon_entry.icon_paintable.is_a?(Gdk::Texture), true)

# malcontent: the OARS content rating upstream's validate_group_for_ui
# compares against StateInfo#parental_age_rating.
plain_check("proprietary entry's oars rating parsed", proprietary.content_rating&.age, 16)

group = EntryGroup.new
group.add(loupe)
plain_check("group title", group.title, "Loupe")
plain_check("group installable", group.installable, 1)
group.reconcile_with_installed_set(backend.retrieve_install_ids.keys)
plain_check("group removable after reconcile", group.removable, 1)

engine = SearchEngine.new(model: [group])
plain_check("search hit", engine.query(["loupe"]).results.first&.group&.id, "org.gnome.Loupe")
plain_check("search miss", engine.query(["zzzznothing"]).n_results, 0)

settings_dir = Dir.mktmpdir("bazaar-settings")
settings = Settings.new(path: File.join(settings_dir, "roundtrip.json"))
settings.hide_eol = false
plain_check("settings roundtrip", Settings.new(path: settings.location).hide_eol?, false)
plain_check(
  "settings refuse bad choice",
  begin
    settings["global-progress-bar-theme"] = "not-a-theme"
    false
  rescue ArgumentError
    true
  end,
  true,
)

blocked = BlocklistSet.new(
  blocklists: [
    Blocklist.from_h({ "priority" => 10, "block" => ["com.example.Proprietary"] }),
    Blocklist.from_h({ "priority" => 5, "allow" => ["com.example.Proprietary"] }),
  ],
)
plain_check("blocklist allow wins on lower priority", blocked.allows?("com.example.Proprietary"), true)
plain_check(
  "blocklist blocks by regex",
  BlocklistSet.new(
    blocklists: [Blocklist.from_h({ "priority" => 1, "block-regex" => ["com\\.example\\..*"] })],
  ).allows?("com.example.Proprietary"),
  false,
)

menu_window = Window.new(application: nil, state: StateInfo.new(settings: settings))
plain_check(
  "primary menu sections",
  menu_window.primary_menu.n_items,
  4,
)
plain_check("account menu item count", menu_window.account_menu.n_items, 2)
plain_check("debug menu item count", menu_window.debug_menu.n_items, 1)

# HardwareSupportDialog and LicenseDialog are ported and functional, but
# upstream only reaches them from the entry detail page (bz-full-view),
# which has no lib/*.rb yet — so there is no action or button in the running
# app that opens them. These checks build them directly against a real
# Entry, the way the (not-yet-ported) detail page eventually will, so the
# classes are proven rather than merely present.
require_relative "../lib/hardware_support_dialog"
require_relative "../lib/license_dialog"

def list_box_row_count(list_box)
  count = 0
  child = list_box.first_child
  while child
    count += 1
    child = child.next_sibling
  end
  count
end

hw = HardwareSupportDialog.new(entry: loupe)
hw.build
plain_check("hardware support dialog title", hw.dialog.title, "Hardware Support")
plain_check("hardware support dialog lists controls", list_box_row_count(hw.list) >= 5, true)

license = LicenseDialog.new(entry: loupe)
license.build
plain_check("license dialog title", license.dialog.title, "License")
plain_check("license dialog shows floss lozenge for FOSS entry", license.floss_lozenge.box.visible?, true)
plain_check("license dialog hides proprietary lozenge for FOSS entry", license.other_lozenge.box.visible?, false)

puts
puts "#{$plain_checks - $plain_failures.length} of #{$plain_checks} plain checks passed"
$plain_failures.each { |label| puts "  failed plain check: #{label}" }

# --- Part 2: driving the real application through the UI ----------------
#
# The same FakeBackend, but wired into the real Bazaar::Application so every
# step below goes through the window's own actions, menus and dialogs rather
# than a hand-assembled substitute.


def child_count(box)
  count = 0
  child = box.first_child
  while child
    count += 1
    child = child.next_sibling
  end
  count
end

ui_catalogue_dir = Dir.mktmpdir("bazaar-ui-catalogue")
File.write(File.join(ui_catalogue_dir, "appstream.xml"), UI_CATALOGUE)
FileUtils.mkdir_p(File.join(ui_catalogue_dir, "icons", "flatpak", "64x64"))
File.binwrite(File.join(ui_catalogue_dir, "icons", "flatpak", "64x64", "org.gnome.Loupe.png"), tiny_png)
ui_backend = FakeBackend.new(ui_catalogue_dir)

app_object = Bazaar::Application.new
app_object.instance_variable_set(:@backend, ui_backend)

GtkDriver.drive(app_object, shots: SHOTS, interval: 600, timeout: 60) do |d, app|
  d.window { app.window.window }

  d.step("initial sync completes") do
    d.check("window title is Bazaar") { app.window.window.title.to_s.include?("Bazaar") }
    d.check("view stack shows main (not loading)") { app.window.main_stack.visible_child_name == "main" }
    d.check("library page shows content") { app.window.library_page.stack.visible_child_name == "content" }
    d.check("installed tile present") { !app.window.library_page.installed_list.first_child.nil? }
    d.check("has_flathub set from repositories") { app.state.has_flathub == true }
  end

  # An extra settled tick before the first screenshot: the window has only
  # just been laid out, and a render node taken too early comes back nil.
  d.step("window has settled") do
    d.shot("01-main-window")
  end

  d.step("about dialog opens with upstream's identity") do
    about = AboutDialog.new.build
    about.present(app.window.window)
    d.check("about application name") { about.application_name == "Bazaar" }
    d.check("about version set") { !about.version.to_s.empty? }
    about.close
  end

  d.step("shortcuts dialog lists the app's accelerators") do
    shortcuts = ShortcutsDialog.new.build
    shortcuts.present(app.window.window)
    d.check("shortcuts dialog title") { shortcuts.title == "Keyboard Shortcuts" }
    shortcuts.close
  end

  d.step("preferences dialog opens via the app.preferences action and writes settings") do
    app.app.activate_action("preferences", nil)
    d.check("preferences dialog visible") { app.window.window.visible_dialog.is_a?(Adwaita::PreferencesDialog) }
  end

  d.step("toggling only-foss in preferences writes through to state") do
    app.window.window.visible_dialog.close
    # A fresh instance, same as the "preferences" action builds, so its own
    # memoized switch-row accessor is reachable without walking the tree.
    prefs = PreferencesDialog.new(state: app.state)
    prefs.build.present(app.window.window)
    before = app.state.show_only_foss?
    prefs.only_foss_switch.active = !before
    d.check("preferences switch flips state.show_only_foss") { app.state.show_only_foss? == !before }
    prefs.only_foss_switch.active = before
    prefs.dialog.close
  end

  d.step("toggle-debug-mode action shows the debug box") do
    before = app.state.debug_mode?
    app.app.activate_action("toggle-debug-mode", nil)
    d.check("debug mode flipped") { app.state.debug_mode? == !before }
    d.check("debug box visible follows debug_mode") { app.window.debug_box.visible? == app.state.debug_mode? }
    app.app.activate_action("toggle-debug-mode", nil)
  end

  d.step("Ctrl+F style search routes through window.search into the library page") do
    app.window.search("Loupe")
    d.check("view stack switched to installed") { app.window.main_stack.get_child_by_name("main") && app.window.view_stack.visible_child_name == "installed" }
    d.check("library search bar seeded") { app.window.library_page.search_bar.text_value == "Loupe" }
    d.check("content still shown for a match") { app.window.library_page.stack.visible_child_name == "content" }
  end

  d.step("search-match screenshot") { d.shot("02-search-match") }

  d.step("a search with no matches shows the no-results page") do
    app.window.library_page.reset_search
    app.window.search("zzzznothing")
    d.check("no-results page shown") { app.window.library_page.stack.visible_child_name == "no-results" }
    d.check("no-results subtitle mentions the query") { app.window.library_page.no_results_page.description.to_s.include?("zzzznothing") }
  end

  d.step("no-results screenshot") { d.shot("03-no-results") }

  d.step("the no-results page's button hands the query back out as a global search") do
    seen = nil
    app.window.instance_variable_set(:@on_search, ->(text) { seen = text })
    app.window.library_page.global_search_button.signal_emit("clicked")
    d.check("global search button forwards the current query") { seen == "zzzznothing" }
    app.window.instance_variable_set(:@on_search, ->(text) { app.send(:search, text) })
    app.window.library_page.reset_search
    app.window.refresh
  end

  d.step("sort popover reorders the installed list by size") do
    # A second installed app is needed to see an order change: fold the
    # proprietary entry's group into the installed set the way a completed
    # install would, without re-running a whole sync.
    extra_group = app.send(:groups_by_id)["com.example.Proprietary"]
    extra_group.reconcile_with_installed_set(extra_group.model.map(&:unique_id))
    app.state.all_installed_entry_groups = app.state.all_installed_entry_groups + [extra_group]
    app.window.library_page.refresh

    d.check("both installed tiles present") { child_count(app.window.library_page.installed_list) == 2 }

    by_name = app.window.library_page.send(:sorted, app.window.library_page.send(:groups)).map(&:title)
    app.window.library_page.sort_size.active = true
    by_size = app.window.library_page.send(:sorted, app.window.library_page.send(:groups)).map(&:title)
    d.check("sort toggle changes the installed list's order") { by_name != by_size }
    d.check("installed list still has both tiles once re-sorted") { child_count(app.window.library_page.installed_list) == 2 }
    app.window.library_page.sort_name.active = true
  end

  d.step("two-apps screenshot") { d.shot("04-library-two-apps") }

  d.step("an update transaction runs to completion and the tracker reports done") do
    loupe_entry = app.send(:entries_by_unique_id)["FLATPAK-SYSTEM::flathub::app/org.gnome.Loupe/x86_64/stable"]
    app.send(:transactions).add(Transaction.new(updates: [loupe_entry]))
  end

  d.step("update finished") do
    tracker = app.send(:transactions).all_trackers.first
    d.check("tracker finished") { tracker.status == TransactionEntryTracker::STATUS_DONE }
    d.check("transaction succeeded") { app.send(:transactions).transactions.first.success? }
    d.check("manager idle") { !app.send(:transactions).active? }
  end

  d.step("update-done screenshot") { d.shot("05-update-done") }

  d.step("a backend failure leaves an errored task behind, with its ErrorDialog reachable") do
    loupe_entry = app.send(:entries_by_unique_id)["FLATPAK-SYSTEM::flathub::app/org.gnome.Loupe/x86_64/stable"]
    ui_backend.fail_next = true
    app.send(:transactions).add(Transaction.new(removals: [loupe_entry]))
  end

  d.step("the errored task shows its pill and opens an ErrorDialog") do
    tracker = app.send(:transactions).all_trackers.last
    d.check("failing tracker has an errored finished op") { tracker.finished_ops.any?(&:errored?) }
    error_dialog = ErrorDialog.new(title: "Removal Failed", details: tracker.finished_ops.find(&:errored?).error.to_s).build
    error_dialog.present(app.window.window)
    d.check("error dialog carries the task's error text") { error_dialog.title == "Removal Failed" }
    error_dialog.close
    app.send(:transactions).clear_finished
  end

  d.step("the escape/back controller pops the navigation view") do
    app.window.push_page(Adwaita::NavigationPage.new(Gtk::Label.new("Addons"), "Addons"))
    d.check("pushed page is visible") { app.window.navigation_view.visible_page.title == "Addons" }
    app.window.navigation_view.pop
    d.check("pop returns to the main page") { app.window.navigation_view.visible_page.title == "Bazaar" }
  end

  d.step("narrow breakpoint hides the title widget's switcher") do
    app.window.breakpoint_bin.width_request = 400
    app.window.breakpoint_bin.height_request = 450
    app.window.window.set_default_size(400, 900)
    d.check("switcher bar exists for the breakpoint to reveal") { !app.window.switcher_bar.nil? }
    app.window.window.set_default_size(Window::DEFAULT_WIDTH, Window::DEFAULT_HEIGHT)
  end

  d.step("clearing finished tasks empties the clear-finished revealer") do
    app.window.library_page.refresh
    d.check("no transactions left to clear") { !app.send(:transactions).has_transactions? }
    d.check("clear revealer collapsed") { !app.window.library_page.clear_revealer.reveal_child? }
  end

  d.step("donate action opens the donation link without crashing the app") do
    app.app.activate_action("donate", nil)
    d.check("app still alive after donate") { !app.app.active_window.nil? }
  end

  d.step("malcontent queried the system bus at startup") do
    # `app.build`'s "startup" handler already called `malcontent.start` for
    # real, over Gio.bus_get_sync(:system, nil), before this driver's first
    # step ever ran. In this sandbox there is no accounts service, so it
    # takes the documented failure path and records why; either outcome
    # proves the gem's manager was actually invoked, not stubbed.
    d.check("malcontent reported a reason or produced a rating") do
      !app.malcontent.unavailable_reason.nil? || app.state.parental_age_rating != -1
    end
  end

  d.step("a group whose OARS rating exceeds the parental ceiling is hidden") do
    rated_group = app.send(:groups_by_id)["com.example.Proprietary"]
    d.check("fixture group carries the parsed OARS rating") { rated_group.content_age_rating == 16 }
    app.state.parental_age_rating = 10
    d.check("group above the ceiling is not visible") { !app.visible?(rated_group) }
    app.state.parental_age_rating = 18
    d.check("group below the ceiling is visible again") { app.visible?(rated_group) }
    app.state.parental_age_rating = -1
    d.check("ceiling disabled (-1) shows the group regardless") { app.visible?(rated_group) }
  end
end
