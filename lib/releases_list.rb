# frozen_string_literal: true

require "adwaita"
require_relative "appstream_description_render"

# ReleaseRow is one release: its version, an "Installed" lozenge when that
# version is the installed one, how long ago it came out, its notes, and a
# link to more information.
#
# Ported from create_release_row in upstream's src/bz-releases-list.c. The
# preview form (`clamped: true`) is the one the full view shows above the
# version-history button; upstream fades the notes out at 270px with
# BzFadingClamp, which is not ported, so the preview clips them to ten lines
# instead.
class ReleaseRow
  PREVIEW_LINES = 10

  def initialize(release:, installed_versions: [], clamped: false)
    @release = release
    @installed_versions = installed_versions
    @clamped = clamped
  end

  def build
    row.tap do |list_row|
      list_row.child = content_box
    end
  end

  def row
    @row ||= Adwaita::ActionRow.new.tap do |list_row|
      list_row.activatable = false
    end
  end

  def content_box
    @content_box ||= Gtk::Box.new(:vertical, 3).tap do |box|
      box.margin_top = 15
      box.margin_bottom = 15
      box.margin_start = 15
      box.margin_end = 15
      box.append(header_box)
      box.append(body)
      case !@clamped && !@release.url.to_s.empty?
      when true then box.append(more_info_box)
      end
    end
  end

  def header_box
    @header_box ||= Gtk::Box.new(:horizontal, 8).tap do |box|
      box.height_request = 24
      box.append(version_label)
      case installed?
      when true then box.append(installed_label)
      end
      box.append(date_label)
    end
  end

  def version_label
    @version_label ||= Gtk::Label.new("Version #{@release.version}").tap do |label|
      label.add_css_class("accent")
      label.add_css_class("heading")
      label.ellipsize = :end
      label.halign = :start
      label.hexpand = !installed?
    end
  end

  def installed_label
    @installed_label ||= Gtk::Label.new("Installed").tap do |label|
      label.add_css_class("lozenge")
      label.add_css_class("small")
      label.halign = :start
      label.hexpand = true
    end
  end

  def date_label
    @date_label ||= Gtk::Label.new(relative_date.to_s).tap do |label|
      label.add_css_class("dim-label")
      label.halign = :end
      absolute_date.then do |tooltip|
        case tooltip
        when nil then nil
        else label.tooltip_text = tooltip
        end
      end
    end
  end

  def body
    @body ||= begin
      case @release.description.to_s.empty?
      when true then fallback_label
      else description_widget
      end
    end
  end

  def description_widget
    @description_widget ||= AppstreamDescriptionRender
                            .new(description: @release.description)
                            .build
                            .tap do |widget|
      widget.margin_top = 10
      case @clamped
      when true then widget.height_request = PREVIEW_LINES * 20
      end
    end
  end

  def fallback_label
    @fallback_label ||= Gtk::Label.new("No details for this release").tap do |label|
      label.margin_top = 5
      label.selectable = true
      label.add_css_class("dim-label")
      label.xalign = 0.0
      label.wrap = true
    end
  end

  def more_info_box
    @more_info_box ||= Gtk::Box.new(:horizontal, 4).tap do |box|
      box.append(more_info_label)
      box.append(more_info_icon)
    end
  end

  def more_info_label
    @more_info_label ||= Gtk::Label.new.tap do |label|
      url = GLib.markup_escape_text(@release.url.to_s)
      label.markup = "<a href=\"#{url}\" title=\"#{url}\">Get More Information</a>"
      label.tooltip_text = @release.url.to_s
    end
  end

  def more_info_icon
    @more_info_icon ||= Gtk::Image.new.tap do |image|
      image.icon_name = "external-link-symbolic"
      image.pixel_size = 12
      image.add_css_class("accent")
    end
  end

  private

    def installed? = @installed_versions.map(&:to_s).include?(@release.version.to_s)

    # Ported from format_timestamp: "Today", "Yesterday", then days, weeks,
    # months and years ago.
    def relative_date
      case @release.timestamp.to_i.zero?
      when true then nil
      else describe_age(((Time.now - Time.at(@release.timestamp.to_i)) / 86_400).to_i)
      end
    end

    def describe_age(days)
      weeks = days / 7
      months = days / 30
      years = weeks / 52

      case
      when days < 1 then "Today"
      when days < 2 then "Yesterday"
      when days < 15 then plural(days, "day")
      when weeks < 8 then plural(weeks, "week")
      when years < 1 then plural(months, "month")
      else plural(years, "year")
      end
    end

    def plural(count, unit)
      case count
      when 1 then "1 #{unit} ago"
      else "#{count} #{unit}s ago"
      end
    end

    # Ported from format_timestamp_tooltip: "22 March 2026".
    def absolute_date
      case @release.timestamp.to_i.zero?
      when true then nil
      else Time.at(@release.timestamp.to_i).utc.strftime("%-d %B %Y")
      end
    end
end

# ReleasesDialog lists an app's whole version history.
#
# Ported from upstream's src/bz-releases-dialog.blp and the
# bz_releases_dialog_new half of src/bz-releases-list.c.
class ReleasesDialog
  def initialize(version_history:, installed_versions: [])
    @version_history = version_history
    @installed_versions = installed_versions
  end

  def build
    dialog.tap do |root|
      root.child = toolbar_view

      toolbar_view.tap do |view|
        view.add_top_bar(header_bar)
        view.content = scroller

        scroller.child = clamp
        clamp.child = releases_box

        @version_history.each do |release|
          releases_box.append(
            ReleaseRow.new(release: release, installed_versions: @installed_versions).build,
          )
        end
      end
    end
  end

  def dialog
    @dialog ||= Adwaita::Dialog.new.tap do |root|
      root.title = "Version History"
      root.content_width = 550
      root.content_height = 600
    end
  end

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

  def header_bar
    @header_bar ||= Adwaita::HeaderBar.new.tap do |bar|
      bar.show_title = true
    end
  end

  def scroller
    @scroller ||= Gtk::ScrolledWindow.new.tap do |window|
      window.propagate_natural_height = true
      window.vexpand = true
      window.hscrollbar_policy = :never
    end
  end

  def clamp
    @clamp ||= Adwaita::Clamp.new.tap do |widget|
      widget.maximum_size = 500
      widget.tightening_threshold = 600
      widget.margin_top = 24
      widget.margin_bottom = 24
      widget.margin_start = 12
      widget.margin_end = 12
    end
  end

  def releases_box
    @releases_box ||= Gtk::ListBox.new.tap do |box|
      box.add_css_class("boxed-list")
      box.valign = :start
      box.selection_mode = :none
    end
  end
end

# ReleasesList is the preview of the newest release plus the button that
# opens the whole history.
#
# Ported from upstream's src/bz-releases-list.blp and src/bz-releases-list.c.
class ReleasesList
  def initialize(version_history: [], installed_versions: [])
    @version_history = version_history
    @installed_versions = installed_versions
  end

  def build
    root.tap do |bin|
      bin.child = box
      box.append(preview_box)
      box.append(show_all_box)
      show_all_box.append(show_all_row)

      show_all_row.signal_connect("activated") { present_dialog }
      refresh
    end
  end

  def version_history=(history)
    @version_history = history
    refresh
    history
  end

  def installed_versions=(versions)
    @installed_versions = versions
    refresh
    versions
  end

  def refresh
    while preview_box.first_child
      preview_box.remove(preview_box.first_child)
    end

    @version_history.first.then do |release|
      case release
      when nil then nil
      else
        preview_box.append(
          ReleaseRow.new(
            release:            release,
            installed_versions: @installed_versions,
            clamped:            true,
          ).build,
        )
      end
    end

    show_all_box.visible = !@version_history.empty?
    root.visible = !@version_history.empty?
  end

  def root
    @root ||= Adwaita::Bin.new.tap do |bin|
      bin.visible = false
    end
  end

  def box = @box ||= Gtk::Box.new(:vertical, 12)

  def preview_box
    @preview_box ||= Gtk::ListBox.new.tap do |list|
      list.add_css_class("boxed-list")
      list.selection_mode = :none
      list.valign = :start
    end
  end

  def show_all_box
    @show_all_box ||= Gtk::ListBox.new.tap do |list|
      list.visible = false
      list.add_css_class("boxed-list")
      list.selection_mode = :none
    end
  end

  def show_all_row
    @show_all_row ||= Adwaita::ButtonRow.new.tap do |row|
      row.title = "_Version History"
      row.use_underline = true
      row.end_icon_name = "go-next-symbolic"
    end
  end

  private

    def present_dialog
      ReleasesDialog.new(
        version_history:    @version_history,
        installed_versions: @installed_versions,
      ).build.present(root)
    end
end
