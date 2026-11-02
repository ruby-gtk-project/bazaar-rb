# frozen_string_literal: true

# StateInfo is the single object every page, dialog and tile reads the app's
# state from.
#
# Ported from upstream's src/bz-state-info.txt, the declaration a code
# generator turns into a GObject with one property per line. Blueprint binds
# straight to those properties ("template.state as <$BzStateInfo>.busy"); the
# port keeps the same names as accessors and offers `on_change`, which the
# widgets use in place of a property binding.
#
# Only the properties the port has something behind are listed here; as the
# remaining services land (Flathub state, the content provider, the entry
# cache) their field joins this list.
class StateInfo
  # name => default. Mirrors the property lines of bz-state-info.txt.
  FIELDS = {
    all_entries:                [],
    all_entry_groups:           [],
    filtered_entry_groups:      [],
    all_installed_entry_groups: [],
    all_user_data_entry_groups: [],
    available_updates:          [],
    repositories:               [],
    blocklists:                 [],
    txt_blocklists:             [],
    curated_configs:            [],
    parental_blocked_ids:       [],
    allow_manual_sync:          true,
    application_factory:        nil,
    entry_factory:              nil,
    auth_state:                 nil,
    backend:                    nil,
    background_task_label:      nil,
    busy:                       false,
    busy_progress:              0.0,
    busy_progress_label:        nil,
    busy_step_label:            nil,
    checking_for_updates:       false,
    debug_mode:                 false,
    disable_blocklists:         false,
    donation_prompt_dismissed:  false,
    has_flathub:                false,
    have_connection:            true,
    hide_eol:                   true,
    metered_connection:         false,
    online:                     true,
    recently_synced:            false,
    search_engine:              nil,
    settings:                   nil,
    show_only_flathub:          false,
    show_only_foss:             false,
    show_only_verified:         false,
    syncing:                    false,
    system_icon_theme:          nil,
    user_icon_theme:            nil,
    transaction_manager:        nil,
    parental_age_rating:        -1,
  }.freeze

  def initialize(**overrides)
    @values = FIELDS.merge(overrides)
    @listeners = {}
  end

  FIELDS.each_key do |name|
    define_method(name) { @values[name] }

    define_method(:"#{name}=") do |value|
      @values[name] = value
      notify(name)
      value
    end

    case FIELDS[name]
    when true, false
      define_method(:"#{name}?") { @values[name] == true }
    end
  end

  # Runs the block whenever one of `names` changes, or on every change when
  # no name is given. This is the port's "notify::<property>".
  def on_change(*names, &block)
    case names.empty?
    when true then (@listeners[:any] ||= []) << block
    else names.each { |name| (@listeners[name.to_sym] ||= []) << block }
    end
    block
  end

  # Sets several fields and notifies once per field, which keeps a page from
  # rebuilding itself halfway through a batch of changes.
  def update(**values)
    values.each { |name, value| @values[name] = value }
    values.each_key { |name| notify(name) }
    self
  end

  private

    def notify(name)
      @listeners.fetch(name, []).each { |block| block.call(@values[name]) }
      @listeners.fetch(:any, []).each { |block| block.call(name) }
    end
end
