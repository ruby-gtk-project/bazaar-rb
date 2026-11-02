# frozen_string_literal: true

require "adwaita"

# PreferencesDialog is the app's preferences.
#
# Ported from upstream's src/bz-preferences-dialog.blp and
# src/bz-preferences-dialog.c: the metered-connection banner, the automatic /
# manual update choice, the auto-update notification switch, the four content
# filters and the grid of progress-bar themes. Every row is bound to the same
# settings key it is bound to upstream, so a change here is written straight
# through and picked up by the rest of the app.
#
# The themes are the full <choices> list of the global-progress-bar-theme key
# with the tooltips and style classes of the bar_themes table in that C file.
#
# Upstream's `auto_updates_toggled_cb` also asks the background portal to let
# the daemon autostart; the daemon is not part of this port, so toggling
# automatic updates writes the setting and nothing else.
class PreferencesDialog
  BAR_THEMES = [
    ["accent-color", "accent-color-theme", "Accent Color"],
    ["pride-rainbow-flag", "pride-rainbow-flag-theme", "Pride Colors"],
    ["lesbian-pride-flag", "lesbian-pride-flag-theme", "Lesbian Pride Colors"],
    ["gay-pride-flag", "gay-pride-flag-theme", "Male Homosexual Pride Colors"],
    ["transgender-flag", "transgender-flag-theme", "Transgender Pride Colors"],
    ["nonbinary-flag", "nonbinary-flag-theme", "Nonbinary Pride Colors"],
    ["bisexual-flag", "bisexual-flag-theme", "Bisexual Pride Colors"],
    ["asexual-flag", "asexual-flag-theme", "Asexual Pride Colors"],
    ["pansexual-flag", "pansexual-flag-theme", "Pansexual Pride Colors"],
    ["aromantic-flag", "aromantic-flag-theme", "Aromantic Pride Colors"],
    ["genderfluid-flag", "genderfluid-flag-theme", "Genderfluid Pride Colors"],
    ["polysexual-flag", "polysexual-flag-theme", "Polysexual Pride Colors"],
    ["omnisexual-flag", "omnisexual-flag-theme", "Omnisexual Pride Colors"],
    ["aroace-flag", "aroace-flag-theme", "Aroace Pride Colors"],
    ["agender-flag", "agender-flag-theme", "Agender Pride Colors"],
    ["genderqueer-flag", "genderqueer-flag-theme", "Genderqueer Pride Colors"],
    ["intersex-flag", "intersex-flag-theme", "Intersex Pride Colors"],
    ["demigender-flag", "demigender-flag-theme", "Demigender Pride Colors"],
    ["biromantic-flag", "biromantic-flag-theme", "Biromantic Pride Colors"],
    ["disability-flag", "disability-flag-theme", "Disability Pride Colors"],
    ["femboy-flag", "femboy-flag-theme", "Femboy Pride Colors"],
    ["neutrois-flag", "neutrois-flag-theme", "Neutrois Pride Colors"],
  ].freeze

  def initialize(state:)
    @state = state
    @settings = state.settings
    @flag_buttons = {}
  end

  def build
    dialog.tap do |root|
      root.add(page)

      page.tap do |prefs|
        prefs.banner = metered_banner
        prefs.add(auto_updates_group)
        prefs.add(notifications_group)
        prefs.add(filters_group)
        prefs.add(theme_group)
      end

      auto_updates_group.tap do |group|
        group.add(automatic_row)
        group.add(manual_row)
      end

      notifications_group.add(auto_notif_switch)

      filters_group.tap do |group|
        group.add(only_foss_switch)
        group.add(only_flathub_switch)
        group.add(only_verified_switch)
        group.add(hide_eol_switch)
      end

      theme_group.add(theme_row)
      theme_row.child = theme_box
      theme_box.append(flag_buttons_box)
      create_flag_buttons

      bind_settings
      refresh
    end
  end

  def refresh
    metered_banner.revealed = @state.metered_connection?
    metered_banner.sensitive = !@state.syncing?
  end

  def dialog
    @dialog ||= Adwaita::PreferencesDialog.new.tap do |root|
      root.content_height = 500
      root.search_enabled = true
      root.width_request = 350
      root.height_request = 100
    end
  end

  def page
    @page ||= Adwaita::PreferencesPage.new.tap do |prefs|
      prefs.title = "Preferences"
      prefs.use_underline = true
    end
  end

  def metered_banner
    @metered_banner ||= Adwaita::Banner.new(
      "Network connection is metered — automatic store data refresh is paused",
    ).tap do |banner|
      banner.button_label = "Refresh Manually"
      banner.action_name = "app.sync-remotes"
    end
  end

  def auto_updates_group
    @auto_updates_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = "App Updates"
      group.description = "Auto-updates will pause on metered networks or when power saving " \
                          "is on to save data and battery."
    end
  end

  def automatic_row
    @automatic_row ||= Adwaita::ActionRow.new.tap do |row|
      row.title = "_Automatic"
      row.subtitle = "Automatically check for and download app updates"
      row.use_underline = true
      row.activatable_widget = automatic_check
      row.add_prefix(automatic_check)
    end
  end

  def automatic_check
    @automatic_check ||= Gtk::CheckButton.new.tap do |check|
      check.valign = :center
    end
  end

  def manual_row
    @manual_row ||= Adwaita::ActionRow.new.tap do |row|
      row.title = "_Manual"
      row.subtitle = "Checking for and downloading app updates must be done manually"
      row.use_underline = true
      row.activatable_widget = manual_check
      row.add_prefix(manual_check)
    end
  end

  def manual_check
    @manual_check ||= Gtk::CheckButton.new.tap do |check|
      check.valign = :center
      check.group = automatic_check
      check.active = !automatic_check.active?
    end
  end

  def notifications_group
    @notifications_group ||= Adwaita::PreferencesGroup.new
  end

  def auto_notif_switch
    @auto_notif_switch ||= Adwaita::SwitchRow.new.tap do |row|
      row.use_underline = true
      row.title = "Automatic Update _Notifications"
      row.subtitle = "Notify when updates have been automatically installed"
    end
  end

  def filters_group
    @filters_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = "Content Filters"
    end
  end

  def only_foss_switch
    @only_foss_switch ||= switch_row(
      "_Free Software Only",
      "Hide proprietary apps when browsing and searching",
    )
  end

  def only_flathub_switch
    @only_flathub_switch ||= switch_row(
      "F_lathub Results Only",
      "Limit search and browse results to apps only available on Flathub",
    )
  end

  def only_verified_switch
    @only_verified_switch ||= switch_row(
      "_Verified Results Only",
      "Hide results that are not verified on Flathub",
    )
  end

  def hide_eol_switch
    @hide_eol_switch ||= switch_row(
      "Hide _End-of-Life Apps",
      "Hide apps which are no longer supported by their developers",
    )
  end

  def theme_group
    @theme_group ||= Adwaita::PreferencesGroup.new.tap do |group|
      group.title = "Progress Bar Theme"
    end
  end

  def theme_row = @theme_row ||= Adwaita::ActionRow.new

  def theme_box
    @theme_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.margin_top = 6
      box.margin_bottom = 6
      box.halign = :center
    end
  end

  def flag_buttons_box
    @flag_buttons_box ||= Gtk::FlowBox.new.tap do |box|
      box.add_css_class("accent-button-box")
      box.orientation = :horizontal
      box.column_spacing = 4
      box.row_spacing = 4
      box.halign = :center
      box.homogeneous = true
      box.max_children_per_line = 11
      box.selection_mode = :none
    end
  end

  private

    def switch_row(title, subtitle)
      Adwaita::SwitchRow.new.tap do |row|
        row.title = title
        row.subtitle = subtitle
        row.use_underline = true
      end
    end

    # One toggle per theme, all in the first one's radio group, each carrying
    # the theme's style class so the swatch shows its colours.
    def create_flag_buttons
      first = nil
      BAR_THEMES.each do |id, style_class, tooltip|
        Gtk::ToggleButton.new.tap do |button|
          button.tooltip_text = tooltip
          button.add_css_class("accent-button")
          button.add_css_class(style_class)

          case first
          when nil then first = button
          else button.group = first
          end

          button.signal_connect("toggled") { theme_toggled(button, id) }
          @flag_buttons[id] = button
          flag_buttons_box.append(button)
        end
      end
    end

    def theme_toggled(button, id)
      case button.active?
      when true then @settings["global-progress-bar-theme"] = id
      end
    end

    def bind_settings
      @settings.bind("show-only-foss", only_foss_switch, "active")
      @settings.bind("show-only-flathub", only_flathub_switch, "active")
      @settings.bind("show-only-verified", only_verified_switch, "active")
      @settings.bind("hide-eol", hide_eol_switch, "active")
      @settings.bind("auto-update", automatic_check, "active")
      @settings.bind("auto-update-notifications", auto_notif_switch, "active")
      @settings.on_change("global-progress-bar-theme") { |value| select_theme(value) }
      select_theme(@settings["global-progress-bar-theme"])
    end

    def select_theme(id)
      @flag_buttons[id]&.active = true
    end
end
