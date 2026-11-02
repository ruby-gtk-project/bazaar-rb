# frozen_string_literal: true

require "rexml/document"
require "zlib"
require "gtk4"
require_relative "entry"

# AppstreamParser reads an AppStream catalogue and copies what it finds onto
# an Entry.
#
# Ported from upstream's src/bz-appstream-parser.c. Upstream hands the XML to
# libappstream and reads AsComponent getters; the port walks the same
# catalogue XML with REXML, because the Ruby bindings carry no libappstream.
# Every mapping below — which url kinds become share links, how a screenshot
# is proxied through imgproxy.flathub.org, how an icon is chosen, how the
# control and display-length relations turn into bitfields — follows that
# file.
#
# Two deliberate differences, both because the logic lives inside
# libappstream rather than in Bazaar:
#
#   * search tokens are built here from the id, name, summary, developer and
#     keywords instead of coming from as_component_get_search_tokens;
#   * `is-floss` is decided by the SPDX ids in FOSS_LICENSES rather than by
#     libappstream's full licence table.
module AppstreamParser
  # Flathub serves screenshots through an image proxy; a URL under
  # dl.flathub.org is rewritten to the proxy, anything else is left alone.
  # The base64 of the source URL is produced with pack("m0") rather than the
  # base64 gem, which is no longer a default gem on Ruby 3.4.
  FLATHUB_SCREENSHOT_PREFIX = "https://dl.flathub.org/repo/screenshots/"
  FLATHUB_PREFIX = "https://dl.flathub.org/"
  IMGPROXY = "https://imgproxy.flathub.org/insecure"

  # The SPDX ids this port treats as free software. Upstream asks
  # libappstream, which knows the whole SPDX list; these are the ids that
  # actually appear across a Flathub catalogue.
  FOSS_LICENSES = [
    "0BSD", "AGPL-3.0", "AGPL-3.0-only", "AGPL-3.0-or-later", "Apache-2.0",
    "Artistic-2.0", "BSD-2-Clause", "BSD-3-Clause", "BSL-1.0", "CC0-1.0",
    "CC-BY-3.0", "CC-BY-4.0", "CC-BY-SA-3.0", "CC-BY-SA-4.0", "CECILL-2.1",
    "EPL-1.0", "EPL-2.0", "EUPL-1.2", "GPL-2.0", "GPL-2.0-only",
    "GPL-2.0-or-later", "GPL-3.0", "GPL-3.0-only", "GPL-3.0-or-later",
    "ISC", "LGPL-2.0-only", "LGPL-2.0-or-later", "LGPL-2.1", "LGPL-2.1-only",
    "LGPL-2.1-or-later", "LGPL-3.0", "LGPL-3.0-only", "LGPL-3.0-or-later",
    "MIT", "MPL-1.1", "MPL-2.0", "Unlicense", "WTFPL", "Zlib",
  ].freeze

  PROPRIETARY_PREFIX = "LicenseRef-proprietary"

  # One <component> element of a catalogue, with the accessors the parser
  # needs. Localised elements are read in their untranslated form, which is
  # the one without an xml:lang attribute.
  class Component
    attr_reader :element

    def initialize(element)
      @element = element
    end

    def id = text("id")
    def kind = @element.attributes["type"].to_s
    def name = localized("name")
    def summary = localized("summary")
    def description = markup("description")
    def project_license = text("project_license")
    def metadata_license = text("metadata_license")
    def project_group = text("project_group")
    def bundle = text("bundle")
    def pkgname = text("pkgname")

    def developer_name
      @element.elements["developer/name"]&.text || text("developer_name")
    end

    def developer_id = @element.elements["developer"]&.attributes&.[]("id")

    def keywords
      @element.get_elements("keywords/keyword").map { |e| e.text.to_s }.reject(&:empty?)
    end

    def categories
      @element.get_elements("categories/category").map { |e| e.text.to_s }.reject(&:empty?)
    end

    # The url kinds, keyed by the AppStream type attribute ("homepage",
    # "donation", "bugtracker", ...).
    def urls
      @element.get_elements("url").each_with_object({}) do |e, acc|
        case blank?(e.attributes["type"], e.text)
        when false then acc[e.attributes["type"].to_s] = e.text.to_s.strip
        end
      end
    end

    def icons
      @element.get_elements("icon").map do |e|
        {
          kind:   e.attributes["type"].to_s,
          value:  e.text.to_s.strip,
          width:  e.attributes["width"].to_i,
          height: e.attributes["height"].to_i,
        }
      end
    end

    def screenshots
      @element.get_elements("screenshots/screenshot").map do |e|
        {
          caption: e.elements["caption"]&.text.to_s,
          images:  e.get_elements("image").map do |image|
            {
              url:    image.text.to_s.strip,
              width:  image.attributes["width"].to_i,
              height: image.attributes["height"].to_i,
            }
          end,
        }
      end
    end

    def releases
      @element.get_elements("releases/release").map do |e|
        Release.new(
          version:     e.attributes["version"],
          timestamp:   e.attributes["timestamp"].to_i,
          description: e.elements["description"]&.to_s,
          url:         e.elements["url[@type='details']"]&.text || e.elements["url"]&.text,
        )
      end
    end

    def branding_colors
      @element.get_elements("branding/color").each_with_object({}) do |e, acc|
        scheme = e.attributes["scheme_preference"].to_s
        case e.attributes["type"].to_s == "primary" && !scheme.empty?
        when true then acc[scheme] = e.text.to_s.strip
        end
      end
    end

    # The newest OARS rating the component carries, preferring 1.1 over 1.0
    # exactly as upstream does.
    def content_rating
      (@element.elements["content_rating[@type='oars-1.1']"] ||
        @element.elements["content_rating[@type='oars-1.0']"] ||
        @element.elements["content_rating"]).then do |node|
        case node
        when nil then nil
        else
          ContentRating.new(
            kind:       node.attributes["type"].to_s,
            attributes: node.get_elements("content_attribute").to_h do |attribute|
              [attribute.attributes["id"].to_s, attribute.text.to_s.strip]
            end,
          )
        end
      end
    end

    def custom
      @element.get_elements("custom/value").to_h do |value|
        [value.attributes["key"].to_s, value.text.to_s.strip]
      end
    end

    # The <control> children of a relation element, as a control bitfield.
    def controls(relation)
      @element.get_elements("#{relation}/control").sum do |control|
        Entry::CONTROL_NAMES.fetch(control.text.to_s.strip, 0)
      end
    end

    # A <display_length> relation. AppStream defaults the comparison to "ge",
    # so a bare element is a minimum.
    def display_length(relation, compare)
      @element.get_elements("#{relation}/display_length").filter_map do |node|
        (node.attributes["compare"] || "ge").then do |node_compare|
          case node_compare == compare
          when true then node.text.to_i
          else nil
          end
        end
      end.max
    end

    def eol_date = @element.attributes["date_eol"] || text("end_of_life")

    private

      def text(name) = @element.elements[name]&.text&.strip

      def localized(name)
        (@element.elements["#{name}[not(@xml:lang)]"] || @element.elements[name])&.text&.strip
      end

      def markup(name)
        @element.elements["#{name}[not(@xml:lang)]"].then do |node|
          (node || @element.elements[name]).then do |chosen|
            case chosen
            when nil then nil
            else chosen.children.map(&:to_s).join.strip
            end
          end
        end
      end

      def blank?(type, text)
        type.nil? || text.to_s.strip.empty?
      end
  end

  class << self
    # Reads a catalogue file — plain XML or the gzipped form flatpak ships in
    # <remote>/appstream.xml.gz — and yields each component.
    def components(path)
      read(path).then do |xml|
        case xml
        when nil then []
        else
          REXML::Document.new(xml).then do |document|
            document.get_elements("//component").map { |element| Component.new(element) }
          end
        end
      end
    end

    # Fills `entry` from `component`, the port's bz_appstream_parser_populate_entry.
    #
    # `appstream_dir` is the remote's appstream directory, which is where a
    # local icon's "64x64/foo.png" filename resolves; `remote_name` decides
    # whether the Flathub-only fields (verification, share urls) apply.
    def populate_entry(entry, component, appstream_dir: nil, remote_name: nil, id: nil, kinds: 0)
      app_id = id || component.id
      entry.id = app_id
      entry.kinds = kinds
      entry.title = component.name || app_id
      entry.description = component.summary
      entry.long_description = component.description
      entry.metadata_license = component.metadata_license
      entry.project_license = component.project_license
      entry.is_floss = floss?(component.project_license)
      entry.project_group = component.project_group
      entry.developer = component.developer_name
      entry.developer_id = component.developer_id
      entry.keywords = component.keywords
      entry.version_history = component.releases
      entry.content_rating = component.content_rating
      entry.eol = component.eol_date

      apply_urls(
        entry,
        component,
        app_id,
        remote_name,
      )
      apply_icon(entry, component, appstream_dir)
      apply_screenshots(entry, component)
      apply_branding(entry, component)
      apply_relations(entry, component)
      apply_categories(entry, component)
      apply_verification(entry, component, remote_name)
      entry.search_tokens = search_tokens(entry, component)
      entry
    end

    # Upstream rewrites a Flathub screenshot URL to the image proxy: the
    # source URL is base64'd (url-safe, unpadded) and the proxy resizes it.
    def proxy_screenshot_url(url, high_quality)
      source = proxy_source(url)
      case source
      when nil then url
      else
        encoded = [source].pack("m0").delete("=").tr("+/", "-_")
        "#{IMGPROXY}/#{proxy_options(high_quality)}/#{encoded}"
      end
    end

    def floss?(license)
      case license.nil? || license.empty? || license.start_with?(PROPRIETARY_PREFIX)
      when true then false
      else
        license.split(%r{\s+(?:OR|AND)\s+|\s*/\s*}).map { |part| part.delete("()+") }
               .any? { |part| FOSS_LICENSES.include?(part) }
      end
    end

    private

      def read(path)
        case File.exist?(path)
        when false then nil
        else
          case File.extname(path)
          when ".gz" then Zlib::GzipReader.open(path, &:read)
          else File.read(path)
          end
        end
      rescue Zlib::GzipFile::Error, SystemCallError
        nil
      end

      def proxy_source(url)
        case url
        when %r{\A#{Regexp.escape(FLATHUB_SCREENSHOT_PREFIX)}}
          "https://dl.flathub.org/media/#{url.delete_prefix(FLATHUB_SCREENSHOT_PREFIX)}"
        when %r{\A#{Regexp.escape(FLATHUB_PREFIX)}} then url
        else nil
        end
      end

      def proxy_options(high_quality)
        case high_quality
        when true then "q:90/f:avif"
        else "dpr:1/f:avif/rs:fill-down"
        end
      end

      # Every url kind becomes a share link; the donation one is also kept on
      # its own, since the tiles show a donate button for it. Flathub entries
      # gain a link to their store page and, when that would leave an odd
      # number of links, a link to the manifest so the columns stay even.
      def apply_urls(entry, component, app_id, remote_name)
        urls = component.urls
        entry.url = urls["homepage"]
        entry.donation_url = urls["donation"]

        share = []
        case remote_name == "flathub" && (entry.kinds & Entry::KIND_APPLICATION) != 0
        when true
          share << Url.new(id: "flathub", url: "https://flathub.org/apps/#{app_id}")
        end
        urls.each { |kind, url| share << Url.new(id: kind, url: url) }
        case remote_name == "flathub" && share.length.odd?
        when true
          share << Url.new(id: "manifest", url: "https://github.com/flathub/#{app_id}")
        end
        entry.share_urls = share
      end

      # Prefers a local icon over a remote one, and the largest of either.
      # A local icon resolves under <appstream_dir>/icons/flatpak/<WxH>/.
      def apply_icon(entry, component, appstream_dir)
        best = nil
        component.icons.each do |icon|
          candidate = resolve_icon(icon, appstream_dir)
          case candidate.nil?
          when false then best = better_icon(best, candidate)
          end
        end

        case best
        when nil then nil
        else
          entry.icon_path = best[:path]
          entry.icon_url = best[:url]
          entry.icon_paintable = load_texture(best[:path])
        end
      end

      def resolve_icon(icon, appstream_dir)
        case icon[:kind]
        when "remote"
          { url: icon[:value], local: false, width: icon[:width], height: icon[:height] }
        else
          case appstream_dir.nil? || icon[:value].empty?
          when true then nil
          else
            File.join(
              appstream_dir,
              "icons",
              "flatpak",
              "#{icon[:width]}x#{icon[:height]}",
              icon[:value],
            ).then do |path|
              case File.exist?(path)
              when true then { path: path, local: true, width: icon[:width], height: icon[:height] }
              else nil
              end
            end
          end
        end
      end

      def better_icon(best, candidate)
        case best
        when nil then candidate
        else
          case candidate[:local] && !best[:local]
          when true then candidate
          else
            case candidate[:width] > best[:width] && candidate[:height] > best[:height]
            when true then candidate
            else best
            end
          end
        end
      end

      def load_texture(path)
        case path
        when nil then nil
        else Gdk::Texture.new(Gio::File.new_for_path(path))
        end
      rescue StandardError
        nil
      end

      # The thumbnail is the image closest to 400x300 of the first
      # screenshot; every screenshot also contributes its largest image,
      # Flathub-hosted ones for preference.
      def apply_screenshots(entry, component)
        urls = []
        captions = []

        component.screenshots.each_with_index do |screenshot, index|
          case index.zero?
          when true then entry.thumbnail_url = pick_image(
            screenshot[:images],
            400,
            300,
            false,
          )
          end

          pick_image(
            screenshot[:images],
            0,
            0,
            true,
          ).then do |url|
            case url
            when nil then nil
            else
              urls << url
              captions << screenshot[:caption]
            end
          end
        end

        entry.screenshot_urls = urls
        entry.screenshot_captions = captions
      end

      def pick_image(images, target_width, target_height, match_highest)
        flathub = images.select { |image| image[:url].to_s.start_with?(FLATHUB_PREFIX) }
        candidates = flathub
        case flathub.empty?
        when true then candidates = images
        end
        best = best_image(candidates, target_width * target_height, match_highest)
        case best
        when nil then nil
        else proxy_screenshot_url(best[:url], match_highest)
        end
      end

      def best_image(images, target_pixels, match_highest)
        usable = images.reject { |image| image[:url].to_s.empty? }
        case match_highest
        when true then usable.max_by { |image| image[:width] * image[:height] }
        else usable.min_by { |image| ((image[:width] * image[:height]) - target_pixels).abs }
        end
      end

      def apply_branding(entry, component)
        colors = component.branding_colors
        entry.light_accent_color = colors["light"]
        entry.dark_accent_color = colors["dark"]
      end

      def apply_relations(entry, component)
        entry.required_controls = component.controls("requires")
        entry.recommended_controls = component.controls("recommends")
        entry.supported_controls = component.controls("supports")
        entry.min_display_length = component.display_length("requires", "ge").to_i
        entry.max_display_length = component.display_length("supports", "le").to_i
      end

      # Mobile friendliness is not declared: it follows from any relation
      # mentioning touch, and it is then also a category so the mobile
      # section of the browser can filter on it.
      def apply_categories(entry, component)
        component.categories.each { |name| entry.add_category(name) }
        case entry.is_mobile_friendly
        when true then entry.add_category("mobile")
        end
      end

      def apply_verification(entry, component, remote_name)
        case remote_name == "flathub"
        when false then nil
        else
          custom = component.custom
          entry.verification_status = VerificationStatus.new(
            verified:              custom["flathub::verification::verified"] == "true",
            method:                custom["flathub::verification::method"],
            website:               custom["flathub::verification::website"],
            login_name:            custom["flathub::verification::login_name"],
            login_provider:        custom["flathub::verification::login_provider"],
            timestamp:             custom["flathub::verification::timestamp"],
            login_is_organization: custom["flathub::verification::login_is_organization"] == "true",
          )
        end
      end

      # The tokens the search engine matches against, in place of
      # libappstream's tokenizer: the id, the title, the developer, every
      # keyword and the words of the summary, lowercased and deduplicated.
      def search_tokens(entry, component)
        [
          entry.id.to_s.tr(".", " "),
          entry.title.to_s,
          entry.developer.to_s,
          component.keywords.join(" "),
          entry.description.to_s,
        ].join(" ").downcase.split(/[^[:alnum:]]+/).reject(&:empty?).uniq.join(" ")
      end
  end
end
