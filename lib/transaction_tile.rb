# frozen_string_literal: true

require "adwaita"
require_relative "list_tile"
require_relative "progress_bar"
require_relative "template_callbacks"
require_relative "transaction"
require_relative "error_dialog"

# TransactionTile is one row of the library's download or uninstall list: an
# app being installed, updated or removed, with its progress, its state pill
# and the list of operations it has finished.
#
# Ported from upstream's src/bz-transaction-tile.blp and
# src/bz-transaction-tile.c, including which pill shows for which state
# (add-on, runtime, in queue, done, cancelled, error, and the freed size of a
# completed removal), the Open button that appears once an installed
# application is done, the stop button while it runs, and the details toggle
# that reveals the finished operations with their errors.
class TransactionTile < ListTile
  ICON_SIZE = 64
  FALLBACK_ICON = "application-x-executable"

  attr_reader :tracker

  def initialize(tracker:, on_activated: nil, on_cancel: nil, on_run: nil)
    super(on_activated: on_activated)
    @tracker = tracker
    @on_cancel = on_cancel
    @on_run = on_run
  end

  def build
    super.tap do
      cancel_button.signal_connect("clicked") { @on_cancel&.call(@tracker) }
      open_button.signal_connect("clicked") { @on_run&.call(@tracker) }
      details_toggle.signal_connect("toggled") { details_revealer.reveal_child = details_toggle.active? }
      @tracker.on_change { refresh }
      refresh
    end
  end

  def refresh
    title_label.label = entry.title.to_s
    icon_image.paintable = entry.icon_paintable
    case entry.icon_paintable
    when nil then icon_image.icon_name = FALLBACK_ICON
    end

    refresh_progress
    refresh_pills
    refresh_buttons
  end

  def child
    @child ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.append(header_box)
      box.append(details_revealer)
    end
  end

  private

    def entry = @tracker.entry

    def refresh_progress
      progress_revealer.reveal_child = !@tracker.current_ops.empty?
      pills_revealer.reveal_child = @tracker.current_ops.empty?
      progress_bar.fraction = @tracker.progress.to_f
      progress_label.label = download_progress
    end

    # Ported from format_download_progress: the transferred size alone when
    # the total is unknown, which is what an update reports.
    def download_progress
      @tracker.current_ops.last.then do |task|
        case task
        when nil then ""
        else format_transfer(task)
        end
      end
    end

    def format_transfer(task)
      transferred = TemplateCallbacks.format_size(task.last_progress&.bytes_transferred.to_i)
      case task.op.download_size
      when nil then transferred
      else "#{transferred} / #{TemplateCallbacks.format_size(task.op.download_size)}"
      end
    end

    def refresh_pills
      addon_pill.visible = entry.addon?
      runtime_pill.visible = entry.runtime? && !entry.addon?
      queued_pill.visible = @tracker.status == TransactionEntryTracker::STATUS_QUEUED
      done_pill.visible = @tracker.status == TransactionEntryTracker::STATUS_DONE
      cancelled_pill.visible = @tracker.status == TransactionEntryTracker::STATUS_CANCELLED
      error_pill.visible = @tracker.finished_ops.any?(&:errored?)
      freed_pill.visible = removal? && @tracker.done?
      freed_label.label = TemplateCallbacks.format_size(entry.installed_size)
    end

    def refresh_buttons
      open_button.visible = entry.application? && @tracker.done? && installing? && entry.installed?
      cancel_button.visible = @tracker.status == TransactionEntryTracker::STATUS_ONGOING
      details_toggle.sensitive = !@tracker.finished_ops.empty?
      rebuild_operations
    end

    def installing? = @tracker.kind == TransactionEntryTracker::KIND_INSTALL

    def removal? = @tracker.kind == TransactionEntryTracker::KIND_REMOVAL

    # The finished-operations list is rebuilt from the tracker rather than
    # bound to it, which is the port's stand-in for the template's
    # NoSelection model over `finished-ops`.
    def rebuild_operations
      operations_box.tap do |box|
        while box.first_child
          box.remove(box.first_child)
        end
        @tracker.finished_ops.each { |task| box.append(operation_row(task)) }
      end
    end

    def operation_row(task)
      Gtk::Box.new(:horizontal, 10).tap do |row|
        row.margin_start = 7
        row.margin_end = 7
        row.append(operation_icon(task))
        row.append(operation_label(task))
        case task.errored?
        when true then row.append(error_button(task))
        end
      end
    end

    def operation_icon(task)
      Gtk::Image.new.tap do |image|
        image.valign = :center
        case task.errored?
        when true
          image.icon_name = "cross-large-circle-filled-symbolic"
          image.add_css_class("error")
        else
          image.icon_name = "check-plain-symbolic"
          image.add_css_class("success")
        end
      end
    end

    def operation_label(task)
      Gtk::Label.new(task.op.name.to_s).tap do |label|
        label.valign = :center
        label.hexpand = true
        label.xalign = 0.0
        label.ellipsize = :end
        label.single_line_mode = true
        case task.errored?
        when true
          label.add_css_class("error")
          label.has_tooltip = true
          label.tooltip_text = task.error.to_s
        else label.add_css_class("dimmed")
        end
      end
    end

    def error_button(task)
      Gtk::Button.new.tap do |button|
        button.icon_name = "info-outline-symbolic"
        button.has_tooltip = true
        button.tooltip_text = "Show Error Info"
        button.add_css_class("error")
        button.add_css_class("flat")
        button.signal_connect("clicked") { present_error(button, task) }
      end
    end

    def present_error(button, task)
      ErrorDialog.new(
        title:   "#{task.op.name} Failed",
        details: task.error.to_s,
      ).build.present(button.root)
    end

    def header_box
      @header_box ||= Gtk::Box.new(:horizontal, 10).tap do |box|
        box.margin_top = 10
        box.margin_bottom = 10
        box.margin_start = 10
        box.margin_end = 4
        box.append(icon_image)
        box.append(middle_box)
        box.append(action_box)
      end
    end

    def icon_image
      @icon_image ||= Gtk::Image.new.tap do |image|
        image.pixel_size = ICON_SIZE
        image.valign = :start
        image.halign = :start
        image.add_css_class("icon-dropshadow")
      end
    end

    def middle_box
      @middle_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.valign = :center
        box.hexpand = true
        box.append(title_label)
        box.append(progress_revealer)
        box.append(pills_revealer)
      end
    end

    def title_label
      @title_label ||= Gtk::Label.new.tap do |label|
        label.hexpand = true
        label.ellipsize = :end
        label.xalign = 0.0
        label.add_css_class("transaction-tile-title")
      end
    end

    def progress_revealer
      @progress_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.transition_type = :slide_down
        revealer.add_css_class("no-min-height")
        revealer.child = progress_box
      end
    end

    def progress_box
      @progress_box ||= Gtk::Box.new(:vertical, 3).tap do |box|
        box.append(progress_bar.build)
        box.append(progress_label)
      end
    end

    def progress_bar = @progress_bar ||= ProgressBar.new

    def progress_label
      @progress_label ||= Gtk::Label.new.tap do |label|
        label.hexpand = true
        label.xalign = 0
        label.ellipsize = :end
        label.single_line_mode = true
        ["dimmed", "caption-heading", "numeric"].each { |css| label.add_css_class(css) }
      end
    end

    def pills_revealer
      @pills_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.child = pills_box
      end
    end

    def pills_box
      @pills_box ||= Gtk::Box.new(:horizontal, 4).tap do |box|
        box.append(addon_pill)
        box.append(runtime_pill)
        box.append(queued_pill)
        box.append(done_pill)
        box.append(cancelled_pill)
        box.append(error_pill)
        box.append(freed_pill)
      end
    end

    def addon_pill
      @addon_pill ||= pill("App Add-On", "green", icon: "puzzle-piece-symbolic")
    end

    def runtime_pill
      @runtime_pill ||= pill("Runtime", "blue", icon: "application-x-sharedlib-symbolic")
    end

    def queued_pill = @queued_pill ||= pill("In Queue", "grey")
    def done_pill = @done_pill ||= pill("Done", "grey")
    def cancelled_pill = @cancelled_pill ||= pill("Cancelled", "grey")
    def error_pill = @error_pill ||= pill("Error", "error")

    def freed_pill
      @freed_pill ||= Gtk::Box.new(:horizontal, 4).tap do |box|
        box.halign = :start
        box.margin_top = 8
        ["installed-pill", "small-pill", "download-size-pill"].each { |css| box.add_css_class(css) }
        box.append(freed_label)
      end
    end

    def freed_label
      @freed_label ||= Gtk::Label.new.tap do |label|
        label.valign = :center
        label.xalign = 0.0
        label.add_css_class("caption-heading")
      end
    end

    def pill(text, color, icon: nil)
      Gtk::Box.new(:horizontal, 4).tap do |box|
        box.halign = :start
        box.margin_top = 8
        [color, "colored", "small-pill", "download-size-pill"].each { |css| box.add_css_class(css) }

        case icon
        when nil then nil
        else
          box.append(
            Gtk::Image.new.tap do |image|
              image.icon_name = icon
              image.pixel_size = 12
            end,
          )
        end

        box.append(
          Gtk::Label.new(text).tap do |label|
            label.valign = :center
            label.xalign = 0.0
            label.add_css_class("caption-heading")
          end,
        )
      end
    end

    def action_box
      @action_box ||= Gtk::Box.new(:horizontal, 5).tap do |box|
        box.append(open_button)
        box.append(cancel_button)
        box.append(details_toggle)
      end
    end

    def open_button
      @open_button ||= Gtk::Button.new(label: "Open").tap do |button|
        button.valign = :center
        button.add_css_class("medium-pill")
      end
    end

    def cancel_button
      @cancel_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = "media-playback-stop-symbolic"
        button.has_tooltip = true
        button.valign = :center
        button.tooltip_text = "Cancel Transaction"
        button.add_css_class("flat")
      end
    end

    def details_toggle
      @details_toggle ||= Gtk::ToggleButton.new.tap do |toggle|
        toggle.tooltip_text = "Show Details"
        toggle.valign = :center
        ["flat", "circular", "ops-toggle"].each { |css| toggle.add_css_class(css) }
        toggle.child = Gtk::Image.new.tap do |image|
          image.pixel_size = 14
          image.icon_name = "go-next-symbolic"
          image.add_css_class("accent")
        end
      end
    end

    def details_revealer
      @details_revealer ||= Gtk::Revealer.new.tap do |revealer|
        revealer.child = details_box
      end
    end

    def details_box
      @details_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.add_css_class("operations")
        box.append(Gtk::Separator.new(:horizontal))
        box.append(operations_box)
      end
    end

    def operations_box
      @operations_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
        box.add_css_class("installed-list-view")
      end
    end
end
