# frozen_string_literal: true

# Drives the ported window against a fake backend, so the parts that need a
# real Flatpak installation can still be exercised headlessly:
#
#   nix develop --command xvfb-run -a ruby test/drive_library.rb
#
# It builds two entries out of an AppStream catalogue snippet, folds them
# into groups, shows them in the library page, runs a transaction through the
# transaction manager and checks what the widgets say afterwards.

require "tmpdir"
require "bazaar"

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
    </component>
  </components>
XML

# A backend that answers out of the catalogue above instead of talking to
# flatpak, and that reports progress for every op it is given.
class FakeBackend < Backend
  REFS = {
    "app/org.gnome.Loupe/x86_64/stable"         => { download_size: 4_500_000, installed_size: 9_000_000 },
    "app/com.example.Proprietary/x86_64/stable" => { download_size: 1_000_000, installed_size: 2_000_000 },
  }.freeze

  def initialize(catalogue_dir)
    @catalogue_dir = catalogue_dir
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
          remote_name: "flathub",
          kinds:       Entry::KIND_APPLICATION,
        )
      end
    end
  end

  def schedule_transaction(installs:, updates:, removals:, channel:)
    (installs + updates + removals).each do |entry|
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
    channel.close
    true
  end
end

def check(label, actual, expected)
  case actual == expected
  when true then puts "ok   #{label}: #{actual.inspect}"
  else
    puts "FAIL #{label}: #{actual.inspect} != #{expected.inspect}"
    $failures += 1
  end
end

$failures = 0

Dir.mktmpdir do |dir|
  File.write(File.join(dir, "appstream.xml"), CATALOGUE)

  backend = FakeBackend.new(dir)
  entries = backend.retrieve_remote_entries
  loupe = entries.first

  check("parsed entries", entries.length, 2)
  check("title", loupe.title, "Loupe")
  check("developer", loupe.developer, "The GNOME Project")
  check("summary", loupe.description, "Browse images")
  check("donation url", loupe.donation_url, "https://donate.gnome.org")
  check("foss", loupe.is_foss, true)
  check("proprietary", entries.last.is_foss, false)
  check("verified", loupe.verified?, true)
  check("mobile friendly", loupe.is_mobile_friendly, true)
  check("graphics category", loupe.has_category?("graphics"), true)
  check("mobile category", loupe.has_category?("mobile"), true)
  check("releases", loupe.version_history.first.version, "48.1")
  check("share urls", loupe.share_urls.map(&:id).first, "flathub")
  check("usefulness beats proprietary", loupe.calc_usefulness > entries.last.calc_usefulness, true)

  group = EntryGroup.new
  group.add(loupe)
  check("group title", group.title, "Loupe")
  check("group installable", group.installable, 1)
  group.reconcile_with_installed_set(backend.retrieve_install_ids.keys)
  check("group removable after reconcile", group.removable, 1)

  engine = SearchEngine.new(model: [group])
  check("search hit", engine.query(["loupe"]).results.first&.group&.id, "org.gnome.Loupe")
  check("search miss", engine.query(["zzzznothing"]).n_results, 0)

  state = StateInfo.new(settings: Settings.new(path: File.join(dir, "settings.json")))
  state.backend = backend
  manager = TransactionManager.new(backend: backend)
  state.transaction_manager = manager
  state.all_installed_entry_groups = [group]
  state.available_updates = [loupe]

  settings = Settings.new(path: File.join(dir, "roundtrip.json"))
  settings.hide_eol = false
  check("settings roundtrip", Settings.new(path: settings.location).hide_eol?, false)
  check(
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
  check("blocklist allow wins on lower priority", blocked.allows?("com.example.Proprietary"), true)
  check(
    "blocklist blocks by regex",
    BlocklistSet.new(
      blocklists: [Blocklist.from_h({ "priority" => 1, "block-regex" => ["com\\.example\\..*"] })],
    ).allows?("com.example.Proprietary"),
    false,
  )

  app = Gtk::Application.new("org.rubygtkproject.BazaarDrive", :default_flags)
  app.signal_connect("activate") do
    window = Window.new(application: app, state: state)
    window.build
    window.present

    render = AppstreamDescriptionRender.new(description: loupe.long_description).build
    check(
      "description rendered",
      render.child.buffer.text.include?("A simple image viewer.") &&
        render.child.buffer.text.include?("• Fast"),
      true,
    )

    preferences = PreferencesDialog.new(state: state).build
    state.settings.then do |store|
      preferences_switch = PreferencesDialog.new(state: state)
      preferences_switch.build
      preferences_switch.only_foss_switch.active = true
      check("preferences writes setting", store["show-only-foss"], true)
    end
    check("preferences dialog title", preferences.title, "Preferences")

    check("library content page", window.library_page.stack.visible_child_name, "content")
    check("installed tile present", !window.library_page.installed_list.first_child.nil?, true)

    manager.add(Transaction.new(updates: [loupe]))

    GLib::Timeout.add(1200) do
      tracker = manager.all_trackers.first
      check("tracker finished", tracker.status, TransactionEntryTracker::STATUS_DONE)
      check("transaction succeeded", manager.transactions.first.success?, true)
      check("manager idle", manager.active?, false)
      check("download tile shown", !window.library_page.install_list.first_child.nil?, true)
      app.quit
      GLib::Source::REMOVE
    end
  end
  app.run([])
end

puts($failures.zero? ? "all checks passed" : "#{$failures} checks failed")
exit($failures.zero? ? 0 : 1)
