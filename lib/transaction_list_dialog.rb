# frozen_string_literal: true

require "adwaita"
require_relative "entry"

# TransactionListDialog is an Adw.AlertDialog that lists the entries a
# pending transaction (an install, an update, a removal) is about to touch,
# with a cancel/confirm response pair.
#
# Ported from upstream's src/bz-transaction-list-dialog.c and
# src/bz-transaction-list-dialog.blp. Upstream filters the entries through a
# GtkFilterListModel bound to a GtkListView; the port is handed a plain
# Ruby array of Entry (the shape every other list in this port already
# uses) and builds the same rows with a ListBox, which is also how upstream
# styles it ("navigation-sidebar"). The body text switches to
# `body_no_apps` when no application-kind entry survives the filter, and
# the count of everything else (addons, runtimes) that is folded out of the
# list goes into `secondary_label` when upstream supplies one.
class TransactionListDialog
  def initialize(entries:, heading:, body:, body_no_apps: nil, secondary_label: nil,
    cancel_label: "Cancel", confirm_label: "Confirm")
    @entries = Array(entries)
    @app_entries = @entries.select(&:application?)
    @heading = heading
    @body = body
    @body_no_apps = body_no_apps
    @secondary_label_format = secondary_label
    @cancel_label = cancel_label
    @confirm_label = confirm_label
    @confirmed = false
  end

  def confirmed? = @confirmed

  def build
    dialog.tap do |d|
      d.heading = @heading
      d.add_response("cancel", @cancel_label)
      d.add_response("confirm", @confirm_label)
      d.set_response_appearance("confirm", :suggested)
      d.default_response = "confirm"
      d.close_response = "cancel"
      d.signal_connect("response") { |_, response| @confirmed = (response == "confirm") }

      apply_body(d)
    end
  end

  def dialog = @dialog ||= Adwaita::AlertDialog.new

  def scrolled_window
    @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |win|
      win.width_request = 300
      win.propagate_natural_height = true
      win.overflow = :hidden
      win.vexpand = true
      win.hscrollbar_policy = :never
    end
  end

  def content_box = @content_box ||= Gtk::Box.new(:vertical, 5)

  def app_list
    @app_list ||= Gtk::ListBox.new.tap do |list|
      list.add_css_class("navigation-sidebar")
      list.selection_mode = :none
      @app_entries.each { |entry| list.append(row_for(entry)) }
    end
  end

  def secondary_label
    @secondary_label ||= Gtk::Label.new.tap do |label|
      label.add_css_class("dimmed")
      label.visible = false
      label.wrap = true
      label.justify = :center
    end
  end

  private

    def row_for(entry)
      Gtk::Box.new(:horizontal, 6).tap do |box|
        box.margin_top = 5
        box.margin_bottom = 5
        box.append(entry_icon(entry))
        box.append(Gtk::Box.new(:vertical, 3).tap do |inner|
          inner.append(Gtk::Label.new(entry.title.to_s).tap do |label|
            label.add_css_class("heading")
            label.hexpand = true
            label.xalign = 0.0
            label.ellipsize = :end
            label.single_line_mode = true
          end)
          inner.append(Gtk::Label.new(entry.id.to_s).tap do |label|
            label.add_css_class("dimmed")
            label.hexpand = true
            label.xalign = 0.0
            label.wrap = true
            label.wrap_mode = :word_char
            label.single_line_mode = true
            label.selectable = true
          end)
        end)
      end
    end

    def entry_icon(entry)
      case entry.icon_paintable
      when nil then Gtk::Image.new(icon_name: "application-x-executable").tap { |image| image.icon_size = :large }
      else Gtk::Image.new(paintable: entry.icon_paintable).tap { |image| image.icon_size = :large }
      end
    end

    def apply_body(d)
      n_total = @entries.length
      n_apps = @app_entries.length
      n_other = n_total - n_apps

      case n_total.zero?
      when true then nil
      else
        case n_apps.zero? && !@body_no_apps.nil?
        when true then d.body = @body_no_apps % n_other
        else
          d.body = @body
          d.extra_child = extra_child(n_other)
        end
      end
    end

    def extra_child(n_other)
      scrolled_window.tap do |win|
        win.child = content_box
        content_box.tap do |box|
          box.append(app_list)
          case n_other.positive? && !@secondary_label_format.nil?
          when true
            secondary_label.label = @secondary_label_format % n_other
            secondary_label.visible = true
          end
          box.append(secondary_label)
        end
      end
    end
end
