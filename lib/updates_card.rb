# frozen_string_literal: true

require "adwaita"
require_relative "entry"
require_relative "releases_list"
require_relative "template_callbacks"

# UpdatesCard is the boxed list at the top of the library page: an expander
# titled with the number of available updates, an "Update All" button, one
# row per application with an update waiting, and a single row standing in
# for all the runtime and add-on updates.
#
# Ported from upstream's src/bz-updates-card.blp and src/bz-updates-card.c,
# including the subtitle that reads "installed → new" when the versions
# differ, the version-history button that opens the releases dialog, the
# per-app Update button, and the rule that the expander starts open only
# when there are three updates or fewer and the user has not closed it.
class UpdatesCard
  AUTO_EXPAND_LIMIT = 3
  ICON_SIZE = 48
  FALLBACK_ICON = "application-x-executable"

  def initialize(state:, on_update: nil)
    @state = state
    @on_update = on_update
    @has_closed = false
    @app_rows = []
  end

  def build
    root.tap do |bin|
      bin.child = list_box
      list_box.append(expander_row)
      update_all_button.signal_connect("clicked") { @on_update&.call(@state.available_updates) }
      expander_row.signal_connect("notify::expanded") do
        case expander_row.expanded?
        when false then @has_closed = true
        end
      end
      @state.on_change(:available_updates) { refresh }
      refresh
    end
  end

  def refresh
    expander_row.title = TemplateCallbacks.format_update_count(updates.length)
    repopulate
  end

  def root = @root ||= Adwaita::Bin.new

  def list_box
    @list_box ||= Gtk::ListBox.new.tap do |box|
      box.selection_mode = :none
      box.margin_start = 4
      box.margin_end = 4
      box.margin_bottom = 4
      box.add_css_class("boxed-list")
    end
  end

  def expander_row
    @expander_row ||= Adwaita::ExpanderRow.new.tap do |row|
      row.add_suffix(suffix_box)
    end
  end

  def suffix_box
    @suffix_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.height_request = 60
      box.append(update_all_button)
    end
  end

  def update_all_button
    @update_all_button ||= Gtk::Button.new(label: "_Update All").tap do |button|
      button.use_underline = true
      button.valign = :center
      button.add_css_class("suggested-action")
    end
  end

  private

    def updates = Array(@state.available_updates)

    def app_updates = updates.select(&:application?)

    # Runtimes and add-ons are collapsed into one row, which is upstream's
    # filter_runtimes.
    def runtime_updates = updates.select { |entry| entry.runtime? || entry.addon? }

    def repopulate
      @app_rows.each { |row| expander_row.remove(row) }
      @app_rows = []
      @runtimes_row.then do |row|
        case row
        when nil then nil
        else
          expander_row.remove(row)
          @runtimes_row = nil
        end
      end

      app_updates.each do |entry|
        app_row(entry).tap do |row|
          expander_row.add_row(row)
          @app_rows << row
        end
      end

      @runtimes_row = runtimes_row
      expander_row.add_row(@runtimes_row)
      refresh_runtimes_row

      case @has_closed
      when false then expander_row.expanded = updates.length <= AUTO_EXPAND_LIMIT
      end
    end

    def app_row(entry)
      Adwaita::ActionRow.new.tap do |row|
        row.title = entry.title.to_s
        subtitle_for(entry).then do |subtitle|
          case subtitle
          when nil then nil
          else row.subtitle = subtitle
          end
        end
        row.add_prefix(row_icon(entry))
        row.add_suffix(history_button(entry))
        row.add_suffix(update_button(entry))
      end
    end

    def row_icon(entry)
      Gtk::Image.new.tap do |image|
        case entry.icon_paintable
        when nil then image.icon_name = FALLBACK_ICON
        else image.paintable = entry.icon_paintable
        end
        image.pixel_size = ICON_SIZE
        image.set_size_request(ICON_SIZE, ICON_SIZE)
        image.margin_top = 6
        image.margin_bottom = 6
        image.valign = :center
        image.add_css_class("icon-dropshadow")
      end
    end

    # "1.2 → 1.3" when the newest release differs from what is installed,
    # and just the version when it does not.
    def subtitle_for(entry)
      installed = entry.installed_version
      newest = entry.version_history.first&.version
      case installed.nil? || newest.nil?
      when true then nil
      else
        case installed == newest
        when true then newest
        else "#{installed} → #{newest}"
        end
      end
    end

    def history_button(entry)
      Gtk::Button.new.tap do |button|
        button.icon_name = "view-list-bullet-symbolic"
        button.valign = :center
        button.tooltip_text = "Version History"
        button.add_css_class("flat")
        button.visible = !entry.version_history.empty?
        button.signal_connect("clicked") { present_history(button, entry) }
      end
    end

    def present_history(button, entry)
      ReleasesDialog.new(
        version_history:    entry.version_history,
        installed_versions: [entry.installed_version].compact,
      ).build.present(button.root)
    end

    def update_button(entry)
      Gtk::Button.new(label: "Update").tap do |button|
        button.valign = :center
        button.signal_connect("clicked") { @on_update&.call([entry]) }
      end
    end

    def runtimes_row
      Adwaita::ActionRow.new.tap do |row|
        row.visible = false
        row.add_suffix(
          Gtk::Button.new(label: "Update").tap do |button|
            button.valign = :center
            button.signal_connect("clicked") { @on_update&.call(runtime_updates) }
          end,
        )
      end
    end

    def refresh_runtimes_row
      runtime_updates.length.then do |count|
        @runtimes_row.visible = count.positive?
        case count.positive?
        when true then @runtimes_row.title = runtimes_title(count)
        end
      end
    end

    def runtimes_title(count)
      case count
      when 1 then "1 Runtime Update"
      else "#{count} Runtime Updates"
      end
    end
end
