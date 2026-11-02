# frozen_string_literal: true

require "adwaita"

# ErrorDialog shows what went wrong, with the details in a monospaced view
# and a button that copies them.
#
# Ported from upstream's src/bz-error-dialog.blp and
# src/bz-error-dialog.c, including the "Copied!" toast the copy button
# raises.
class ErrorDialog
  def initialize(title:, details:)
    @title = title
    @details = details
  end

  def build
    dialog.tap do |root|
      root.child = toast_overlay

      toast_overlay.tap do |overlay|
        overlay.child = toolbar_view

        toolbar_view.tap do |view|
          view.add_top_bar(header_bar)
          view.content = content_box
        end
      end

      copy_button.signal_connect("clicked") { copy }
    end
  end

  def dialog
    @dialog ||= Adwaita::Dialog.new.tap do |root|
      root.content_width = 500
      root.content_height = 400
      root.title = @title.to_s
    end
  end

  def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new
  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def content_box
    @content_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.margin_start = 24
      box.margin_end = 24
      box.margin_top = 12
      box.margin_bottom = 24
      box.append(title_label)
      box.append(details_header)
      box.append(scroller)
    end
  end

  def title_label
    @title_label ||= Gtk::Label.new(@title.to_s).tap do |label|
      label.halign = :center
      label.wrap = true
      label.add_css_class("title-1")
    end
  end

  def details_header
    @details_header ||= Gtk::Box.new(:horizontal, 6).tap do |box|
      box.margin_top = 12
      box.margin_bottom = 6
      box.append(
        Gtk::Label.new("Details").tap do |label|
          label.halign = :start
          label.hexpand = true
          label.add_css_class("heading")
        end,
      )
      box.append(copy_button)
    end
  end

  def copy_button
    @copy_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = "edit-copy-symbolic"
      button.tooltip_text = "Copy"
      button.add_css_class("flat")
    end
  end

  def scroller
    @scroller ||= Gtk::ScrolledWindow.new.tap do |window|
      window.vexpand = true
      window.hscrollbar_policy = :automatic
      window.vscrollbar_policy = :automatic
      window.child = text_view
    end
  end

  def text_view
    @text_view ||= Gtk::TextView.new.tap do |view|
      view.editable = false
      view.wrap_mode = :word_char
      view.monospace = true
      view.left_margin = 6
      view.right_margin = 6
      view.top_margin = 6
      view.bottom_margin = 6
      view.add_css_class("card")
      view.buffer.text = @details.to_s
    end
  end

  private

    def copy
      Gdk::Display.default.clipboard.set(@details.to_s)
      toast_overlay.add_toast(Adwaita::Toast.new("Copied!"))
    end
end
