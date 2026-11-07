# frozen_string_literal: true

require "gtk4"
require_relative "context_row"

# Lozenge is the big circular icon/label-plus-title header used at the top
# of the safety and hardware-support dialogs.
#
# Ported from upstream's src/bz-lozenge.c. There is no .blp — upstream builds
# it entirely in C as a vertical GtkBox: a row of icons (or a text label),
# each wrapped in the "circular-lozenge" + importance CSS classes, above a
# title label.
class Lozenge
  attr_reader :importance

  def initialize
    @title = nil
    @label = nil
    @icon_names = []
    @importance = Importance::NEUTRAL
  end

  def build
    box.tap do |b|
      b.append(inner_box)
      inner_box.append(icon_box)
      inner_box.append(label_widget)
      b.append(title_label)
    end
  end

  def title=(title)
    @title = title
    rebuild
  end

  def label=(label)
    @label = label
    rebuild
  end

  def icon_names=(names)
    @icon_names = Array(names)
    rebuild
  end

  def importance=(importance)
    @importance = importance
    rebuild
  end

  def box
    @box ||= Gtk::Box.new(:vertical, 12).tap do |b|
      b.halign = :center
    end
  end

  def inner_box
    @inner_box ||= Gtk::Box.new(:vertical, 12).tap do |b|
      b.halign = :center
    end
  end

  def icon_box
    @icon_box ||= Gtk::Box.new(:horizontal, 12).tap do |b|
      b.halign = :center
    end
  end

  def label_widget
    @label_widget ||= Gtk::Label.new.tap do |label|
      label.halign = :center
      label.add_css_class("circular-lozenge")
      label.add_css_class("large")
      label.visible = false
    end
  end

  def title_label
    @title_label ||= Gtk::Label.new.tap do |label|
      label.justify = :center
      label.wrap = true
      label.wrap_mode = :word_char
      label.xalign = 0.5
      label.add_css_class("title-2")
      label.visible = false
    end
  end

  private

    def rebuild
      clear_icon_box
      case @icon_names.any?
      when true then rebuild_icons
      else rebuild_label
      end
      rebuild_title
    end

    def clear_icon_box
      while (child = icon_box.first_child)
        icon_box.remove(child)
      end
    end

    def rebuild_icons
      icon_box.visible = true
      label_widget.visible = false
      css_class = Importance.css_class(@importance)
      @icon_names.each do |name|
        icon_box.append(
          Gtk::Image.new(icon_name: name).tap do |icon|
            icon.pixel_size = 24
            icon.halign = :center
            icon.add_css_class("circular-lozenge")
            icon.add_css_class(css_class)
            icon.add_css_class("large")
          end,
        )
      end
    end

    def rebuild_label
      case @label.to_s.empty?
      when true
        icon_box.visible = false
        label_widget.visible = false
      else
        icon_box.visible = false
        label_widget.visible = true
        label_widget.set_markup(@label)
        label_widget.css_classes = ["circular-lozenge", "large", Importance.css_class(@importance)]
      end
    end

    def rebuild_title
      case @title.to_s.empty?
      when true then title_label.visible = false
      else
        title_label.text = @title
        title_label.visible = true
      end
    end
end
