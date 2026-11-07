# frozen_string_literal: true

require "adwaita"
require_relative "entry"
require_relative "lozenge"
require_relative "spdx"

# LicenseDialog explains how an entry is licensed: whether it is
# community-built FOSS, proprietary, or under a special license, with a
# "Get Involved" link for FOSS apps and a "Learn More" link to the EULA for
# a proprietary one that declares it.
#
# Ported from upstream's src/bz-license-dialog.c and
# src/bz-license-dialog.blp.
class LicenseDialog
  def initialize(entry:)
    @entry = entry
  end

  def build
    dialog.tap do |d|
      d.child = toolbar_view
      toolbar_view.add_top_bar(header_bar)
      toolbar_view.content = clamp
      clamp.child = content_box
      content_box.append(lozenge_box)
      lozenge_box.append(floss_lozenge.build)
      lozenge_box.append(other_lozenge.build)
      content_box.append(info_box)
      info_box.append(info_label)
      info_box.append(contribute_button)
      info_box.append(eula_button)
      contribute_button.child = labelled_link_box("Get Involved")
      eula_button.child = labelled_link_box("Learn More")
      update
    end
  end

  def dialog
    @dialog ||= Adwaita::Dialog.new.tap do |d|
      d.title = "License"
      d.content_width = 425
    end
  end

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

  def header_bar
    @header_bar ||= Adwaita::HeaderBar.new.tap { |bar| bar.show_title = false }
  end

  def clamp = @clamp ||= Adwaita::Clamp.new.tap { |c| c.maximum_size = 600 }

  def content_box
    @content_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.margin_top = 6
      box.margin_bottom = 18
      box.margin_start = 18
      box.margin_end = 18
    end
  end

  def lozenge_box
    @lozenge_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.margin_bottom = 16
      box.valign = :center
      box.vexpand = true
    end
  end

  def floss_lozenge
    @floss_lozenge ||= Lozenge.new.tap do |l|
      l.icon_names = ["heart-outline-thick-symbolic", "community-symbolic", "thumbs-up-outline-symbolic"]
      l.importance = Importance::UNIMPORTANT
    end
  end

  def other_lozenge
    @other_lozenge ||= Lozenge.new.tap do |l|
      l.icon_names = ["hand-openyay-symbolic", "proprietary-code-symbolic", "license-symbolic"]
      l.importance = Importance::INFORMATION
    end
  end

  def info_box
    @info_box ||= Gtk::Box.new(:vertical, 6).tap { |box| box.margin_bottom = 12 }
  end

  def info_label
    @info_label ||= Gtk::Label.new.tap do |label|
      label.valign = :start
      label.margin_bottom = 18
      label.margin_start = 18
      label.margin_end = 18
      label.use_markup = true
      label.xalign = 0.5
      label.wrap = true
      label.wrap_mode = :word_char
      label.justify = :center
    end
  end

  def contribute_button
    @contribute_button ||= Gtk::Button.new.tap do |button|
      button.add_css_class("pill")
      button.halign = :center
      button.signal_connect("clicked") { contribute }
    end
  end

  def eula_button
    @eula_button ||= Gtk::Button.new.tap do |button|
      button.add_css_class("pill")
      button.halign = :center
      button.signal_connect("clicked") { open_eula }
    end
  end

  private

    def labelled_link_box(text)
      Gtk::Box.new(:horizontal, 10).tap do |box|
        box.append(Gtk::Label.new(text).tap { |l| l.wrap = true; l.wrap_mode = :word_char; l.justify = :right })
        box.append(Gtk::Image.new(icon_name: "external-link-symbolic"))
      end
    end

    def is_floss? = @entry.is_floss

    def license = @entry.project_license

    def update
      update_lozenges
      info_label.label = license_info
      contribute_button.visible = is_floss?
      contribute_button.tooltip_text = involved_url
      eula_button.visible = !eula_url.nil?
      eula_button.tooltip_text = eula_url
    end

    def update_lozenges
      floss_lozenge.title = label_text
      floss_lozenge.box.visible = is_floss?
      other_lozenge.title = label_text
      other_lozenge.box.visible = !is_floss?
    end

    def label_text
      case
      when license.to_s.empty? then "Unknown License"
      when is_floss? then "Community Built"
      when Spdx.proprietary?(license) then "Proprietary"
      else "Special License"
      end
    end

    def license_info
      case
      when license.to_s.empty? && is_floss?
        "This app is developed in the open by an international community.\n\n" \
          "You can participate and help make it even better."
      when license.to_s.empty?
        "The license of this app is not known"
      when is_floss?
        "This app is developed in the open by an international community, " \
          "and released under the #{license_link} license.\n\n" \
          "You can participate and help make it even better."
      when Spdx.proprietary?(license)
        "This app is not developed in the open, so only its developers know how it works. " \
          "It may be insecure in ways that are hard to detect, and it may change without oversight.\n\n" \
          "You may or may not be able to contribute to this app."
      else
        "This app is developed under the special license #{license_link}.\n\n" \
          "You may or may not be able to contribute to this app."
      end
    end

    def license_link
      case Spdx.valid?(license)
      when false then license
      else "<a href=\"#{Spdx.url(license)}\">#{Spdx.name(license)}</a>"
      end
    end

    # Upstream reads the SECOND share url (index 1), not the first — ported
    # exactly, quirk and all.
    def second_share_url
      Array(@entry.share_urls)[1]&.url
    end

    def involved_url = second_share_url

    def contribute
      involved_url.then { |url| open_uri(url) if url && !url.empty? }
    end

    def eula_url
      license.to_s.start_with?("LicenseRef-proprietary=").then do |has_eula|
        case has_eula
        when false then nil
        else
          license.to_s.delete_prefix("LicenseRef-proprietary=").then { |u| u.empty? ? nil : u }
        end
      end
    end

    def open_eula
      eula_url.then { |url| open_uri(url) if url }
    end

    def open_uri(uri)
      Gio::AppInfo.launch_default_for_uri(uri, nil)
    rescue StandardError
      nil
    end
end
