# frozen_string_literal: true

require "gtk4"
require "adwaita"

require_relative "../settings"
require_relative "../state_info"
require_relative "../entry"
require_relative "../entry_group"
require_relative "../application_map_factory"
require_relative "../blocklist"
require_relative "../backend"
require_relative "../flatpak_backend"
require_relative "../malcontent_service"
require_relative "../transaction"
require_relative "../transaction_manager"
require_relative "../search_engine"
require_relative "../window"
require_relative "../about_dialog"
require_relative "../shortcuts_dialog"
require_relative "../preferences_dialog"
require_relative "../error_dialog"
require_relative "../donations_dialog"

module Bazaar
  # Application is Bazaar's GApplication: it owns the state every page reads,
  # the Flatpak backend, the transaction manager and the search engine, and
  # it installs the app-level actions the menus and accelerators address.
  #
  # Ported from upstream's src/bz-application.c — the same action set and
  # accelerators, the same "refresh" flow (ask the backend for the remote
  # entries, the installed ids and the pending updates, then fold the entries
  # into groups and filter them), and the same group filter
  # (`validate_group_for_ui`): hide end-of-life apps, non-free apps,
  # non-Flathub apps and unverified apps according to the settings, then let
  # the blocklists have the last word.
  #
  # House style (see .claude/skills/ruby-gtk): every widget is a memoized
  # method, all configuration lives in its `tap`, assembly happens only in
  # `build`, and the launcher is one expression.
  class Application
    APP_ID = "org.rubygtkproject.Bazaar"
    STYLESHEET = File.expand_path("../style.css", __dir__)

    # Upstream's gtk_application_set_accels_for_action calls, in order.
    ACCELERATORS = {
      "app.quit"              => ["<primary>q"],
      "app.preferences"       => ["<primary>comma"],
      "app.sync-remotes"      => ["<primary>r"],
      "app.toggle-debug-mode" => ["<primary><alt>d"],
    }.freeze

    def build
      app.tap do
        app.signal_connect("startup") do
          load_stylesheet
          install_actions
          malcontent.start
        end

        app.signal_connect("activate") do
          window.build
          window.present
          sync_remotes
        end
      end
    end

    def run = app.run([])

    # Adwaita::Application is broken in the Ruby bindings; the application
    # object comes from Gtk and only the window is Adwaita.
    def app = @app ||= Gtk::Application.new(APP_ID, :default_flags)

    def settings = @settings ||= Settings.new

    def backend = @backend ||= FlatpakBackend.new

    def malcontent = @malcontent ||= MalcontentService.new(state: state)

    def transactions
      @transactions ||= TransactionManager.new(backend: backend).tap do |manager|
        manager.on_failure { |transaction| report_failure(transaction) }
        manager.on_success { refresh_installed }
      end
    end

    def search_engine = @search_engine ||= SearchEngine.new

    # Unique id -> Entry, the factory the groups resolve their UI entry with.
    def entry_factory
      @entry_factory ||= ApplicationMapFactory.new { |unique_id| entries_by_unique_id[unique_id] }
    end

    # Application id -> EntryGroup, which is what the window's actions and
    # the tiles look an app up by.
    def application_factory
      @application_factory ||= ApplicationMapFactory.new { |id| groups_by_id[id] }
    end

    def state
      @state ||= StateInfo.new(
        settings:            settings,
        backend:             backend,
        transaction_manager: transactions,
        search_engine:       search_engine,
        application_factory: application_factory,
        entry_factory:       entry_factory,
        hide_eol:            settings.hide_eol?,
        show_only_foss:      settings.show_only_foss?,
        show_only_flathub:   settings.show_only_flathub?,
        show_only_verified:  settings.show_only_verified?,
      ).tap do |info|
        bind_settings_to_state(info)
      end
    end

    def window
      @window ||= Window.new(
        application: app,
        state:       state,
        on_update:   ->(entries) { update_entries(entries) },
        on_search:   ->(text) { search(text) },
        on_sync:     -> { sync_remotes },
      )
    end

    def blocklists
      @blocklists ||= BlocklistSet.new(
        blocklists:      Array(state.blocklists),
        blocked_id_sets: Array(state.txt_blocklists),
      )
    end

    # Ported from validate_group_for_ui.
    def visible?(group)
      case
      when state.hide_eol? && !group.eol.nil? then false
      when state.show_only_foss? && !group.is_floss then false
      when state.show_only_flathub? && !group.is_flathub then false
      when state.show_only_verified? && !group.is_verified then false
      when state.parental_age_rating != -1 && group.content_age_rating > state.parental_age_rating then false
      when state.disable_blocklists? then true
      else blocklists.allows?(group.id)
      end
    end

    private

      def entries_by_unique_id = @entries_by_unique_id ||= {}
      def groups_by_id = @groups_by_id ||= {}

      def load_stylesheet
        Gtk::CssProvider.new.tap do |provider|
          provider.load(path: STYLESHEET)
          Gtk::StyleContext.add_provider_for_display(
            Gdk::Display.default,
            provider,
            Gtk::StyleProvider::PRIORITY_APPLICATION,
          )
        end
      end

      # Ported from the app_actions table of src/bz-application.c. The actions
      # whose pages are not ported yet are not installed, so a menu item for
      # one is shown insensitive rather than doing nothing.
      def install_actions
        action("quit") { app.quit }
        action("about") { AboutDialog.new.build.present(active_window) }
        action("shortcuts") { ShortcutsDialog.new.build.present(active_window) }
        action("preferences") { PreferencesDialog.new(state: state).build.present(active_window) }
        action("sync-remotes") { sync_remotes }
        action("toggle-debug-mode") { state.debug_mode = !state.debug_mode? }
        action("donate") { present_donations_dialog }
        string_action("search") { |text| search(text) }
        string_action("show-app-id") { |id| show_app_id(id) }
        string_action("open-location") { |uri| open_location(uri) }

        ACCELERATORS.each { |name, accels| app.set_accels_for_action(name, accels) }
      end

      def action(name, &block)
        Gio::SimpleAction.new(name).tap do |simple|
          simple.signal_connect("activate") { block.call }
          app.add_action(simple)
        end
      end

      def string_action(name, &block)
        Gio::SimpleAction.new(name, GLib::VariantType.new("s")).tap do |simple|
          simple.signal_connect("activate") { |_action, parameter| block.call(parameter.get_string) }
          app.add_action(simple)
        end
      end

      def active_window = app.active_window

      # The four filter settings live on the state as well, because every
      # page reads them from there; a change in the preferences dialog has to
      # reach both.
      def bind_settings_to_state(info)
        {
          "hide-eol"           => :hide_eol=,
          "show-only-foss"     => :show_only_foss=,
          "show-only-flathub"  => :show_only_flathub=,
          "show-only-verified" => :show_only_verified=,
        }.each do |key, setter|
          settings.on_change(key) do |value|
            info.public_send(setter, value)
            refresh_groups
          end
        end
      end

      def search(text)
        window.search(text)
      end

      def show_app_id(id)
        groups_by_id[id].then do |group|
          case group
          when nil then nil
          else window.search(group.title.to_s)
          end
        end
      end

      # Ported from bz_application_donate_action: shows the "What's New"
      # dialog and marks the donations banner dismissed, rather than opening
      # a URL directly.
      def present_donations_dialog
        DonationsDialog.new.build.present(active_window)
        state.donation_prompt_dismissed = true
      end

      def open_location(uri)
        Gio::AppInfo.launch_default_for_uri(uri, nil)
      rescue StandardError => error
        window.add_toast(Adwaita::Toast.new(error.message))
      end

      def update_entries(entries)
        Array(entries).then do |list|
          case list.empty?
          when true then nil
          else transactions.add(Transaction.new(updates: list))
          end
        end
      end

      def report_failure(transaction)
        window.add_toast(Adwaita::Toast.new("#{transaction.name} failed"))
      end

      # Upstream spawns a refresh worker and awaits it; the port reads the
      # backend on a thread and folds the result in on the main loop.
      def sync_remotes
        case @syncing
        when true then nil
        else start_sync
        end
      end

      def start_sync
        @syncing = true
        state.update(busy: true, syncing: true, background_task_label: "Refreshing remotes")

        worker = Thread.new { collect }
        GLib::Timeout.add(100) do
          case worker.alive?
          when true then GLib::Source::CONTINUE
          else
            finish_sync(worker.value)
            GLib::Source::REMOVE
          end
        end
      end

      # Runs on the worker thread: everything here is plain Ruby, no widgets.
      def collect
        {
          entries:   backend.retrieve_remote_entries,
          installed: backend.retrieve_install_ids,
          updates:   backend.retrieve_update_ids,
        }
      rescue Backend::Unsupported, Backend::Failure => error
        { error: error.message }
      end

      def finish_sync(result)
        @syncing = false
        result[:error].then do |message|
          case message
          when nil then absorb(result)
          else state.background_task_label = message
          end
        end
        state.update(busy: false, syncing: false, recently_synced: true, allow_manual_sync: true)
      end

      def absorb(result)
        index_entries(result[:entries], result[:installed])
        build_groups(result[:installed])
        state.all_entries = entries_by_unique_id.values
        state.available_updates = Array(result[:updates]).filter_map { |id| entries_by_unique_id[id] }
        state.repositories = backend.list_repositories
        state.has_flathub = state.repositories.any? { |repo| repo.name == "flathub" }
        refresh_groups
      end

      def index_entries(entries, installed)
        entries_by_unique_id.clear
        Array(entries).each do |entry|
          installed.fetch(entry.unique_id, nil).then do |version|
            case version
            when nil then nil
            else
              entry.installed = true
              entry.installed_version = version
            end
          end
          entries_by_unique_id[entry.unique_id] = entry
        end
      end

      # One group per application id, each fed every entry that names it.
      def build_groups(installed)
        groups_by_id.clear
        entries_by_unique_id.each_value do |entry|
          (groups_by_id[entry.id] ||= EntryGroup.new(factory: entry_factory)).add(entry)
        end
        groups_by_id.each_value { |group| group.reconcile_with_installed_set(installed.keys) }
      end

      def refresh_groups
        groups = groups_by_id.values
        visible = groups.select { |group| visible?(group) }
        search_engine.model = visible
        state.update(
          all_entry_groups:           groups,
          filtered_entry_groups:      visible,
          all_installed_entry_groups: visible.select { |group| group.removable.positive? },
        )
      end

      def refresh_installed
        state.all_installed_entry_groups = state.filtered_entry_groups.select do |group|
          group.removable.positive?
        end
      end
  end
end
