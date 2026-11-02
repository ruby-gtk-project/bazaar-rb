# frozen_string_literal: true

require "adwaita"

# SearchBar is the rounded search box used by the search page and the
# library page: an icon, the text, an optional spinner, a slot for an extra
# widget and a clear button.
#
# Ported from upstream's src/bz-search-bar.blp and src/bz-search-bar.c. The
# clear button appears only once there is text, the spinner only while the
# `busy` flag is set, and the two signals the pages connect to —
# search-changed and search-activated — are the `on_changed` and
# `on_activated` callbacks here.
class SearchBar
  attr_reader :placeholder

  def initialize(placeholder: nil, end_widget: nil, on_changed: nil, on_activated: nil)
    @placeholder = placeholder
    @end_widget = end_widget
    @on_changed = on_changed
    @on_activated = on_activated
    @busy = false
  end

  def build
    root.tap do |box|
      box.append(search_icon)
      box.append(text)
      box.append(spinner)
      box.append(end_bin)
      box.append(clear_button)

      end_bin.child = @end_widget

      text.signal_connect("changed") do
        clear_button.visible = !self.text_value.empty?
        @on_changed&.call(self)
      end
      text.signal_connect("activate") { @on_activated&.call(self) }
      clear_button.signal_connect("clicked") { self.text_value = "" }

      clear_button.visible = false
      spinner.visible = @busy
    end
  end

  def text_value = text.text.to_s

  def text_value=(value)
    text.text = value.to_s
  end

  def busy=(value)
    @busy = value == true
    spinner.visible = @busy
  end

  def end_widget=(widget)
    @end_widget = widget
    end_bin.child = widget
  end

  def grab_focus
    text.grab_focus
  end

  # Upstream's bz_search_bar_ensure_active: focus the box and seed it, which
  # is how `app.search('term')` arrives at a page.
  def seed(initial)
    text.grab_focus
    self.text_value = initial.to_s
    text.position = initial.to_s.length
  end

  def root
    @root ||= Gtk::Box.new(:horizontal, 8).tap do |box|
      box.height_request = 40
      box.add_css_class("search-box")
    end
  end

  def search_icon
    @search_icon ||= Gtk::Image.new.tap do |image|
      image.icon_name = "system-search-symbolic"
    end
  end

  def text
    @text ||= Gtk::Text.new.tap do |entry|
      entry.hexpand = true
      entry.placeholder_text = @placeholder.to_s
    end
  end

  def spinner
    @spinner ||= Adwaita::Spinner.new.tap do |widget|
      widget.width_request = 16
      widget.height_request = 16
    end
  end

  def end_bin = @end_bin ||= Adwaita::Bin.new

  def clear_button
    @clear_button ||= Gtk::Button.new.tap do |button|
      button.icon_name = "edit-clear"
      button.valign = :center
      button.focusable = false
      ["flat", "circular", "searchbar-button"].each { |css| button.add_css_class(css) }
    end
  end
end
