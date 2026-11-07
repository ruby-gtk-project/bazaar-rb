# frozen_string_literal: true

require "adwaita"
require_relative "entry"
require_relative "context_row"
require_relative "lozenge"

# HardwareSupportDialog shows which input methods and form factors an entry
# declares support for.
#
# Ported from upstream's src/bz-hardware-support-dialog.c and
# src/bz-hardware-support-dialog.blp: a lozenge header summarizing whether
# the app works on most devices, over a boxed list of context rows for
# mobile support, desktop support, and each of keyboard/mouse/touchscreen at
# whatever level (required/recommended/supported/unsupported) the entry
# declares.
class HardwareSupportDialog
  CONTROL_INFOS = [
    {
      icon_name:  "input-keyboard-symbolic",
      title:      "Keyboard support",
      control:    Entry::CONTROL_KEYBOARD,
      required:   "Requires keyboards",
      recommends: "Recommends keyboards",
      supports:   "Supports keyboards",
      neutral:    "Unknown support for keyboards",
    },
    {
      icon_name:  "input-mouse-symbolic",
      title:      "Mouse support",
      control:    Entry::CONTROL_POINTING,
      required:   "Requires mice or pointing devices",
      recommends: "Recommends mice or pointing devices",
      supports:   "Supports mice or pointing devices",
      neutral:    "Unknown support for mice or pointing devices",
    },
    {
      icon_name:  "device-support-touch-symbolic",
      title:      "Touchscreen support",
      control:    Entry::CONTROL_TOUCH,
      required:   "Requires touchscreens",
      recommends: "Recommends touchscreens",
      supports:   "Supports touchscreens",
      neutral:    "Unknown support for touchscreens",
    },
  ].freeze

  def initialize(entry:)
    @entry = entry
  end

  def build
    dialog.tap do |d|
      d.child = toolbar_view
      toolbar_view.add_top_bar(header_bar)
      toolbar_view.content = scrolled_window
      scrolled_window.child = clamp
      clamp.child = content_box
      content_box.append(lozenge.build)
      content_box.append(list)
      update
    end
  end

  def dialog
    @dialog ||= Adwaita::Dialog.new.tap do |d|
      d.title = "Hardware Support"
      d.content_width = 640
      d.content_height = 530
    end
  end

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

  def header_bar
    @header_bar ||= Adwaita::HeaderBar.new.tap do |bar|
      bar.show_title = false
    end
  end

  def scrolled_window
    @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |win|
      win.hscrollbar_policy = :never
    end
  end

  def clamp
    @clamp ||= Adwaita::Clamp.new.tap do |c|
      c.maximum_size = 600
      c.tightening_threshold = 400
    end
  end

  def content_box
    @content_box ||= Gtk::Box.new(:vertical, 24).tap do |box|
      box.margin_start = 24
      box.margin_end = 24
      box.margin_top = 24
      box.margin_bottom = 24
    end
  end

  def lozenge
    @lozenge ||= Lozenge.new.tap do |l|
      l.title = "Hardware Support"
      l.icon_names = ["device-supported-symbolic"]
      l.importance = Importance::UNIMPORTANT
    end
  end

  def list
    @list ||= Gtk::ListBox.new.tap do |box|
      box.selection_mode = :none
      box.add_css_class("boxed-list")
    end
  end

  private

    def update
      clear_list
      append_row("phone-symbolic", mobile_friendly? ? Importance::UNIMPORTANT : Importance::NEUTRAL,
        "Mobile support", mobile_friendly? ? "Works on mobile devices" : "May not work well on mobile devices")
      append_row("device-support-desktop-symbolic", Importance::UNIMPORTANT,
        "Desktop support", "Works well on large screens")
      CONTROL_INFOS.each { |info| append_control_row(info) }
      update_lozenge
    end

    def clear_list
      while (child = list.first_child)
        list.remove(child)
      end
    end

    def append_row(icon_name, importance, title, subtitle)
      list.append(ContextRow.build(icon_name: icon_name, importance: importance, title: title, subtitle: subtitle))
    end

    def append_control_row(info)
      importance = control_importance(info[:control])
      subtitle = case importance
      when Importance::IMPORTANT then info[:required]
      when Importance::INFORMATION then info[:recommends]
      when Importance::UNIMPORTANT then info[:supports]
      else info[:neutral]
      end
      append_row(info[:icon_name], importance, info[:title], subtitle)
    end

    def control_importance(control)
      case
      when (@entry.required_controls.to_i & control) != 0 then Importance::IMPORTANT
      when (@entry.recommended_controls.to_i & control) != 0 then Importance::INFORMATION
      when (@entry.supported_controls.to_i & control) != 0 then Importance::UNIMPORTANT
      else Importance::NEUTRAL
      end
    end

    def mobile_friendly? = @entry.mobile_friendly?

    def update_lozenge
      works_best = @entry.required_controls.to_i != Entry::CONTROL_NONE || !mobile_friendly?
      case works_best
      when true
        lozenge.icon_names = ["dialog-warning-symbolic"]
        lozenge.title = "#{@entry.title} works best on specific hardware"
        lozenge.importance = Importance::NEUTRAL
      else
        lozenge.icon_names = ["device-supported-symbolic"]
        lozenge.title = "#{@entry.title} works on most devices"
        lozenge.importance = Importance::UNIMPORTANT
      end
    end
end
