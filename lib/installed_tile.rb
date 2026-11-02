# frozen_string_literal: true

require "adwaita"
require_relative "list_tile"
require_relative "transact_icon"
require_relative "template_callbacks"

# InstalledTile is one row of the library: the app's icon, its name, its
# versions and size, and the buttons that act on it.
#
# Ported from upstream's src/bz-installed-tile.blp and
# src/bz-installed-tile.c. The donate button appears only for an app that
# declares a donation url, the add-ons button only for one that has add-ons,
# and the remove button is hidden for an app with nothing removable and
# insensitive while a transaction holds it — all exactly as the template's
# visibility bindings say.
#
# Upstream gives the donate button an accessibility label; the bindings
# cannot marshal the enum array gtk_accessible_update_property takes
# ("TODO: in Ruby -> GIArgument(array/C)[interface(enum)]"), so the button
# carries the donation url as its tooltip and no accessible label.
class InstalledTile < ListTile
  ICON_SIZE = 64

  attr_reader :group

  def initialize(group:, on_activated: nil, on_remove: nil, on_addons: nil)
    super(on_activated: on_activated)
    @group = group
    @on_remove = on_remove
    @on_addons = on_addons
  end

  def build
    super.tap do
      support_button.signal_connect("clicked") { support }
      addons_button.signal_connect("clicked") { @on_addons&.call(@group) }
      remove_button.signal_connect("clicked") { @on_remove&.call(@group) }
      @group.on_change { refresh }
      refresh
    end
  end

  def refresh
    title_label.label = @group.title.to_s
    title_label.tooltip_text = @group.id.to_s
    description_label.label = TemplateCallbacks.format_description(
      @group.installed_size,
      @group.installed_versions,
    )
    eol_label.visible = !@group.eol.nil?
    support_button.visible = !@group.donation_url.nil?
    support_button.tooltip_text = @group.donation_url.to_s
    addons_button.visible = @group.n_addons.to_i.positive?
    remove_button.visible = @group.removable.positive?
    remove_button.sensitive = @group.removable_and_available.positive?
    icon.paintable = @group.ui_entry&.icon_paintable
  end

  def child
    @child ||= Gtk::Box.new(:horizontal, 10).tap do |box|
      box.append(icon_root)
      box.append(text_box)
      box.append(support_button)
      box.append(button_box)
    end
  end

  private

    # Upstream opens the donation link with the default handler for its uri.
    def support
      @group.donation_url.then do |url|
        case url
        when nil then nil
        else Gio::AppInfo.launch_default_for_uri(url, nil)
        end
      end
    end

    def icon_root
      @icon_root ||= icon.build.tap do |widget|
        widget.margin_start = 10
        widget.margin_top = 10
        widget.margin_bottom = 10
        widget.width_request = ICON_SIZE
        widget.height_request = ICON_SIZE
        widget.valign = :center
        widget.halign = :center
      end
    end

    def icon
      @icon ||= TransactIcon.new(
        paintable: @group.ui_entry&.icon_paintable,
        size:      ICON_SIZE,
      )
    end

    def text_box
      @text_box ||= Gtk::Box.new(:vertical, 4).tap do |box|
        box.valign = :center
        box.append(title_label)
        box.append(description_label)
        box.append(eol_label)
      end
    end

    def title_label
      @title_label ||= Gtk::Label.new.tap do |label|
        label.xalign = 0.0
        label.ellipsize = :end
        label.single_line_mode = true
        label.has_tooltip = true
      end
    end

    def description_label
      @description_label ||= Gtk::Label.new.tap do |label|
        label.halign = :start
        label.ellipsize = :end
        label.single_line_mode = true
        label.add_css_class("dimmed")
        label.add_css_class("caption")
        label.add_css_class("installed-size")
      end
    end

    def eol_label
      @eol_label ||= Gtk::Label.new("Stopped Receiving Updates").tap do |label|
        label.xalign = 0.0
        label.ellipsize = :end
        label.single_line_mode = true
        label.add_css_class("warning")
        label.add_css_class("caption")
      end
    end

    def support_button
      @support_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = "heart-filled-symbolic"
        button.width_request = 32
        button.height_request = 32
        button.valign = :center
        button.has_tooltip = true
        ["circular", "flat", "suggested-action", "support"].each { |css| button.add_css_class(css) }
      end
    end

    def button_box
      @button_box ||= Gtk::Box.new(:horizontal, 8).tap do |box|
        box.margin_end = 8
        box.hexpand = true
        box.halign = :end
        box.append(addons_button)
        box.append(remove_button)
        box.append(chevron)
      end
    end

    def addons_button
      @addons_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = "application-x-addon-symbolic"
        button.tooltip_text = "Manage Add-Ons"
        button.valign = :center
        button.add_css_class("flat")
      end
    end

    def remove_button
      @remove_button ||= Gtk::Button.new.tap do |button|
        button.icon_name = "user-trash-symbolic"
        button.tooltip_text = "Remove"
        button.valign = :center
        button.add_css_class("flat")
      end
    end

    def chevron
      @chevron ||= Gtk::Image.new.tap do |image|
        image.icon_name = "go-next-symbolic"
        image.pixel_size = 14
        image.margin_end = 4
        image.add_css_class("dimmed")
      end
    end
end
