# frozen_string_literal: true

require "adwaita"
require "libxmlb"
require_relative "appstream_description_render"

# DonationsDialog is the "What's New" dialog the app shows after an update:
# the latest release's notes plus a pitch to donate.
#
# Ported from upstream's src/bz-donations-dialog.c and
# src/bz-donations-dialog.blp. Upstream reads a generated
# src/release-notes.xml resource (the first `<release>` of the app's
# metainfo, lifted out at build time) through libxmlb; the port reads the
# same first release straight out of the shipped metainfo file with the
# `libxmlb` gem (`Xmlb`), which is the same library upstream links against.
class DonationsDialog
  DONATE_LINK = "https://ko-fi.com/kolunmi"
  METAINFO_PATH = File.join(__dir__, "..", "data", "io.github.kolunmi.Bazaar.metainfo.xml.in")

  def initialize
    @release_url = nil
  end

  def build
    dialog.tap do |d|
      d.child = toolbar_view
      toolbar_view.add_top_bar(header_bar)
      toolbar_view.content = scrolled_window
      scrolled_window.child = outer_box
      outer_box.append(release_box)
      outer_box.append(donate_bin)

      release_box.tap do |box|
        box.append(title_label)
        box.append(subtitle_label)
        box.append(description_render.build)
        box.append(release_button)
      end
      release_button.child = release_button_box
      release_button_box.tap do |box|
        box.append(Gtk::Label.new("Full Release Notes").tap { |l| l.wrap = true; l.wrap_mode = :word_char })
        box.append(Gtk::Image.new(icon_name: "external-link-symbolic"))
      end

      donate_bin.child = donate_box
      donate_box.tap do |box|
        box.append(donate_heading)
        box.append(donate_body)
        box.append(donate_button)
      end
      donate_button.child = Adwaita::ButtonContent.new.tap do |content|
        content.label = "Donate to Bazaar"
        content.icon_name = "heart-filled-symbolic"
      end

      load_release
    end
  end

  def dialog
    @dialog ||= Adwaita::Dialog.new.tap do |d|
      d.title = "Bazaar Release"
      d.width_request = 450
      d.follows_content_size = true
    end
  end

  def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new

  def header_bar
    @header_bar ||= Adwaita::HeaderBar.new.tap { |bar| bar.show_title = false }
  end

  def scrolled_window
    @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |win|
      win.hscrollbar_policy = :never
      win.vscrollbar_policy = :automatic
      win.propagate_natural_height = true
      win.min_content_height = 500
    end
  end

  def outer_box = @outer_box ||= Gtk::Box.new(:vertical, 0)

  def release_box
    @release_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.margin_start = 40
      box.margin_end = 40
      box.margin_top = 20
      box.margin_bottom = 20
    end
  end

  def title_label
    @title_label ||= Gtk::Label.new.tap do |label|
      label.add_css_class("title-1")
      label.wrap = true
      label.justify = :center
      label.margin_bottom = 5
      label.selectable = true
    end
  end

  def subtitle_label
    @subtitle_label ||= Gtk::Label.new.tap do |label|
      label.add_css_class("dimmed")
      label.wrap = true
      label.justify = :center
      label.margin_bottom = 15
      label.selectable = true
    end
  end

  def description_render = @description_render ||= AppstreamDescriptionRender.new.tap { |r| r.root.vexpand = true }

  def release_button
    @release_button ||= Gtk::Button.new.tap do |button|
      button.add_css_class("pill")
      button.margin_top = 15
      button.margin_start = 25
      button.margin_end = 20
      button.margin_bottom = 15
      button.halign = :center
      button.tooltip_text = @release_url
      button.signal_connect("clicked") { open_release_page }
    end
  end

  def release_button_box = @release_button_box ||= Gtk::Box.new(:horizontal, 10)

  def donate_bin
    @donate_bin ||= Adwaita::Bin.new.tap { |bin| bin.add_css_class("bz-donations-dialog") }
  end

  def donate_box
    @donate_box ||= Gtk::Box.new(:vertical, 0).tap do |box|
      box.margin_start = 25
      box.margin_end = 25
      box.margin_top = 20
      box.margin_bottom = 20
    end
  end

  def donate_heading
    @donate_heading ||= Gtk::Label.new("This release was made possible by users like you!").tap do |label|
      label.add_css_class("title-1")
      label.margin_top = 10
      label.margin_bottom = 20
      label.halign = :center
      label.wrap = true
      label.justify = :center
      label.selectable = true
    end
  end

  def donate_body
    @donate_body ||= Gtk::Label.new(
      "I love making Bazaar, but I cannot do it alone. Help support further development by donating on Ko-Fi.",
    ).tap do |label|
      label.margin_bottom = 20
      label.wrap = true
      label.justify = :center
      label.use_markup = true
      label.selectable = true
    end
  end

  def donate_button
    @donate_button ||= Gtk::Button.new.tap do |button|
      button.add_css_class("pill")
      button.margin_start = 20
      button.margin_end = 20
      button.margin_bottom = 20
      button.halign = :center
      button.tooltip_text = DONATE_LINK
      button.signal_connect("clicked") { open_uri(DONATE_LINK) }
    end
  end

  private

    def open_release_page
      open_uri(@release_url) if @release_url
    end

    def open_uri(uri)
      Gio::AppInfo.launch_default_for_uri(uri, nil)
    rescue StandardError
      nil
    end

    def load_release
      File.exist?(METAINFO_PATH).then do |exists|
        case exists
        when true then load_release_from_metainfo
        else nil
        end
      end
    rescue StandardError
      nil
    end

    def load_release_from_metainfo
      silo = compile_silo(File.read(METAINFO_PATH))
      node = silo.query_first("component/releases/release")
      node.then do |release|
        case release
        when nil then nil
        else apply_release(silo, release)
        end
      end
    end

    def compile_silo(xml)
      source = Xmlb::BuilderSource.new
      source.load_xml(xml, Xmlb::BuilderSourceFlags::LITERAL_TEXT)
      builder = Xmlb::Builder.new
      builder.import_source(source)
      builder.compile(Xmlb::BuilderCompileFlags::NONE, nil)
    end

    def apply_release(silo, release)
      version = release.get_attr("version")
      date = release.get_attr("date")
      version.then { |v| title_label.label = "What's New in #{v}?" if v }
      date.then { |d| subtitle_label.label = format_date(d) if d }
      url_node = silo.query_first("component/releases/release/url[@type='details']")
      @release_url = url_node&.text
      release_button.tooltip_text = @release_url
      description_node = silo.query_first("component/releases/release/description")
      description_render.description = description_node&.export(Xmlb::NodeExportFlags::NONE)
    end

    def format_date(iso_date)
      require "date"
      Date.parse(iso_date).strftime("Released %B %-d, %Y")
    rescue ArgumentError
      "Released #{iso_date}"
    end
end
