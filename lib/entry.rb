# frozen_string_literal: true

require "digest"
require "gtk4"

# CategoryFlags is the bitfield upstream uses to tag an entry with the
# AppStream categories the app browser filters on.
#
# Ported from upstream's src/bz-category-flags.c and src/bz-category-flags.h,
# including the name -> flag table those two files share.
module CategoryFlags
  NONE = 0

  NAMES = {
    "audiovideo"       => 1 << 0,
    "development"      => 1 << 1,
    "education"        => 1 << 2,
    "game"             => 1 << 3,
    "graphics"         => 1 << 4,
    "network"          => 1 << 5,
    "office"           => 1 << 6,
    "science"          => 1 << 7,
    "system"           => 1 << 8,
    "utility"          => 1 << 9,
    "trending"         => 1 << 10,
    "popular"          => 1 << 11,
    "recently-added"   => 1 << 12,
    "recently-updated" => 1 << 13,
    "mobile"           => 1 << 14,
    "adwaita"          => 1 << 15,
    "kde"              => 1 << 16,
  }.freeze

  # Upstream lowercases the incoming name before looking it up, so
  # "AudioVideo" straight out of an AppStream catalogue matches.
  def self.add(flags, name)
    NAMES.fetch(name.to_s.downcase, NONE).then { |flag| flags | flag }
  end

  # The name is NOT lowercased here, matching bz_category_flags_has_name:
  # callers pass the canonical spelling.
  def self.has_name?(flags, name)
    NAMES.fetch(name.to_s, nil).then do |flag|
      case flag
      when nil then false
      else (flags & flag) != 0
      end
    end
  end

  def self.from_name(name) = NAMES.fetch(name.to_s.downcase, NONE)

  def self.names(flags) = NAMES.select { |_, flag| (flags & flag) != 0 }.keys
end

# ContentRating is an OARS content rating: the id -> value pairs an AppStream
# component declares, such as "violence-cartoon" => "mild".
#
# Upstream holds an AsContentRating here; the port keeps the same pairs in a
# hash so the dialogs that explain a rating can read them back.
class ContentRating
  VALUES = ["none", "mild", "moderate", "intense"].freeze

  attr_reader :kind, :attributes

  def initialize(kind: "oars-1.1", attributes: {})
    @kind = kind
    @attributes = attributes.transform_keys(&:to_s).transform_values(&:to_s)
  end

  # The age, in years, the strictest declared attribute corresponds to.
  # Upstream's as_content_rating_attribute_get_csm_age carries a different
  # threshold per OARS id (e.g. "language-profanity: mild" is 8, but
  # "violence-cartoon: mild" is 3); the port keeps a single VALUES ->
  # age scale instead of reproducing that whole table, which is enough to
  # drive malcontent's "show nothing above the parental ceiling" gate.
  AGE_BY_VALUE = { "none" => 0, "mild" => 3, "moderate" => 7, "intense" => 16 }.freeze

  def [](id) = @attributes[id.to_s]
  def empty? = @attributes.empty?

  # The ids whose value is anything other than "none", which is what the
  # dialogs list.
  def declared = @attributes.reject { |_, value| value == "none" }

  def age = @attributes.values.filter_map { |value| AGE_BY_VALUE[value] }.max || 0

  def to_h = { kind: @kind, attributes: @attributes }

  def self.from_h(hash)
    new(
      kind:       hash[:kind] || hash["kind"] || "oars-1.1",
      attributes: hash[:attributes] || hash["attributes"] || {},
    )
  end
end

# VerificationStatus records how Flathub verified an app's developer.
#
# Ported from upstream's src/bz-verification-status.c, which the AppStream
# parser fills from the flathub::verification::* custom fields.
class VerificationStatus
  attr_accessor :verified, :method, :website, :login_name, :login_provider, :timestamp, :login_is_organization

  def initialize(**attributes)
    @verified = attributes.fetch(:verified, false)
    @method = attributes[:method]
    @website = attributes[:website]
    @login_name = attributes[:login_name]
    @login_provider = attributes[:login_provider]
    @timestamp = attributes[:timestamp]
    @login_is_organization = attributes.fetch(:login_is_organization, false)
  end

  def verified? = @verified == true

  def to_h
    {
      verified:              @verified,
      method:                @method,
      website:               @website,
      login_name:            @login_name,
      login_provider:        @login_provider,
      timestamp:             @timestamp,
      login_is_organization: @login_is_organization,
    }
  end

  def self.from_h(hash)
    new(**hash.transform_keys(&:to_sym))
  end
end

# Release is one entry in an app's version history.
#
# Ported from upstream's src/bz-release.c.
class Release
  attr_accessor :version, :timestamp, :description, :url

  def initialize(version: nil, timestamp: 0, description: nil, url: nil)
    @version = version
    @timestamp = timestamp
    @description = description
    @url = url
  end

  def to_h
    {
      version:     @version,
      timestamp:   @timestamp,
      description: @description,
      url:         @url,
    }
  end

  def self.from_h(hash) = new(**hash.transform_keys(&:to_sym))
end

# Url is a labelled link: the id is the AppStream url kind ("homepage",
# "donation", "flathub", "manifest", ...).
#
# Ported from upstream's src/bz-url.c.
class Url
  attr_accessor :id, :url

  def initialize(id: nil, url: nil)
    @id = id
    @url = url
  end

  def to_h = { id: @id, url: @url }
  def self.from_h(hash) = new(**hash.transform_keys(&:to_sym))
end

# Entry is one installable thing: an application, a runtime or an add-on, as
# a single remote describes it.
#
# Ported from upstream's src/bz-entry.c and src/bz-entry.h. Upstream makes
# every field a GObject property so Blueprint can bind to it; the port keeps
# the same field set as plain accessors, since the widgets here read them in
# Ruby rather than through a template binding.
#
# A single app usually produces several entries — one per remote, plus the
# installed one — which EntryGroup then folds together.
class Entry < GLib::Object
  type_register

  # BzEntryKind
  KIND_APPLICATION = 1 << 0
  KIND_RUNTIME     = 1 << 1
  KIND_ADDON       = 1 << 2

  # BzControlType
  CONTROL_NONE      = 0
  CONTROL_POINTING  = 1 << 0
  CONTROL_KEYBOARD  = 1 << 1
  CONTROL_CONSOLE   = 1 << 2
  CONTROL_TABLET    = 1 << 3
  CONTROL_TOUCH     = 1 << 4
  CONTROL_GAMEPAD   = 1 << 5
  CONTROL_TV_REMOTE = 1 << 6
  CONTROL_VOICE     = 1 << 7
  CONTROL_VISION    = 1 << 8

  CONTROL_NAMES = {
    "pointing"  => CONTROL_POINTING,
    "keyboard"  => CONTROL_KEYBOARD,
    "console"   => CONTROL_CONSOLE,
    "tablet"    => CONTROL_TABLET,
    "touch"     => CONTROL_TOUCH,
    "gamepad"   => CONTROL_GAMEPAD,
    "tv-remote" => CONTROL_TV_REMOTE,
    "voice"     => CONTROL_VOICE,
    "vision"    => CONTROL_VISION,
  }.freeze

  # BzRelationType
  RELATION_REQUIRES   = :requires
  RELATION_RECOMMENDS = :recommends
  RELATION_SUPPORTS   = :supports

  attr_accessor :id,
    :unique_id,
    :title,
    :eol,
    :description,
    :long_description,
    :remote_repo_name,
    :remote_repo_icon,
    :url,
    :size,
    :installed_size,
    :icon_paintable,
    :icon_path,
    :mini_icon,
    :search_tokens,
    :metadata_license,
    :project_license,
    :is_floss,
    :project_group,
    :developer,
    :developer_id,
    :donation_url,
    :ratings_summary,
    :light_accent_color,
    :dark_accent_color,
    :verification_status,
    :required_controls,
    :recommended_controls,
    :supported_controls,
    :min_display_length,
    :max_display_length,
    :content_rating,
    :kinds,
    :categories,
    :permissions,
    :recent_downloads,
    :total_downloads,
    :favorites_count

  attr_accessor :screenshot_paintables,
    :screenshot_captions,
    :thumbnail_paintable,
    :share_urls,
    :version_history,
    :keywords,
    :download_stats,
    :download_stats_per_country,
    :developer_apps,
    :similar_apps

  # Upstream wraps every remote image in a BzAsyncTexture, which downloads it
  # in the background and caches it on disk. Until that component is ported
  # the resolved URLs are kept here, beside the paintables a local icon can
  # already supply.
  attr_accessor :icon_url, :screenshot_urls, :thumbnail_url

  attr_writer :reinstallable, :unique_id_checksum

  def initialize(**attributes)
    super()
    @hold = 0
    @installed = false
    @installed_version = nil
    @reinstallable = true
    @addons = []
    @kinds = 0
    @size = 0
    @installed_size = 0
    @is_floss = false
    @required_controls = CONTROL_NONE
    @recommended_controls = CONTROL_NONE
    @supported_controls = CONTROL_NONE
    @min_display_length = 0
    @max_display_length = 0
    @categories = CategoryFlags::NONE
    @screenshot_paintables = []
    @screenshot_captions = []
    @screenshot_urls = []
    @share_urls = []
    @version_history = []
    @keywords = []
    @recent_downloads = 0
    @total_downloads = 0
    @favorites_count = 0
    attributes.each { |key, value| public_send(:"#{key}=", value) }
  end

  # A transaction "holds" every entry it touches, so the install and remove
  # buttons for that app go insensitive until it finishes.
  def hold
    @hold += 1
  end

  def release
    @hold = [@hold - 1, 0].max
  end

  def holding? = @hold.positive?

  def installed? = @installed == true

  def installed=(value)
    @installed = value == true
  end

  attr_reader :installed_version

  def installed_version=(version)
    @installed_version = version
  end

  # Runtimes and add-ons installed as a dependency must not be offered for
  # install on their own; the backend marks those not reinstallable.
  def reinstallable? = @reinstallable == true

  # Upstream returns the supported-controls bitfield here: an entry with no
  # declared controls at all carries no usable UI metadata and is kept out of
  # the search index.
  def searchable? = @supported_controls != CONTROL_NONE

  def of_kinds?(kinds) = (@kinds & kinds) == kinds

  def application? = of_kinds?(KIND_APPLICATION)
  def runtime? = of_kinds?(KIND_RUNTIME)
  def addon? = of_kinds?(KIND_ADDON)

  def append_addon(id)
    @addons << id
    id
  end

  attr_reader :addons

  # MD5 of the unique id, which is what names this entry's directory in the
  # texture cache (bz_flatpak_entry_new_for_ref computes the same digest).
  def unique_id_checksum
    @unique_id_checksum ||= Digest::MD5.hexdigest(@unique_id.to_s)
  end

  def is_flathub = remote_repo_name == "flathub"
  alias flathub? is_flathub

  def is_foss = @is_floss == true
  alias foss? is_foss

  def verified? = @verification_status&.verified? == true

  def is_mobile_friendly
    [@required_controls, @recommended_controls, @supported_controls]
      .any? { |controls| (controls & CONTROL_TOUCH) != 0 }
  end
  alias mobile_friendly? is_mobile_friendly

  def has_control?(control, relation)
    case relation
    when RELATION_REQUIRES then (@required_controls & control) != 0
    when RELATION_RECOMMENDS then (@recommended_controls & control) != 0
    when RELATION_SUPPORTS then (@supported_controls & control) != 0
    else false
    end
  end

  # True when this app can be driven by the controls the current device has,
  # on a display this wide.
  def supports_form_factor?(available_controls, display_length)
    satisfied = true
    case @required_controls != CONTROL_NONE
    when true
      satisfied = (@required_controls & available_controls) == @required_controls
    end
    case @min_display_length.positive? && display_length < @min_display_length
    when true then satisfied = false
    end
    case @max_display_length.positive? && display_length > @max_display_length
    when true then satisfied = false
    end
    satisfied
  end

  def has_category?(name) = CategoryFlags.has_name?(@categories, name)

  def add_category(name)
    @categories = CategoryFlags.add(@categories, name)
  end

  # How much usable metadata this entry carries. When several remotes offer
  # the same app, the group shows the fields of whichever entry scores
  # highest, and an EOL entry is pushed to the back.
  def calc_usefulness
    score = 0
    score += present_when(is_flathub, 1000)
    score += present(@title, 5)
    score += present(@description, 1)
    score += present(@long_description, 5)
    score += present(@url, 1)
    score += present_when(@size.to_i.positive?, 1)
    score += present(@icon_paintable || @icon_path, 15)
    score += present(@remote_repo_icon, 1)
    score += present(@metadata_license, 1)
    score += present(@project_license, 1)
    score += present(@project_group, 1)
    score += present(@developer, 1)
    score += present(@developer_id, 1)
    score += present_when(!@screenshot_paintables.empty?, 5)
    score += present_when(!@share_urls.empty?, 5)
    score -= present(@eol, 500)
    score
  end

  # The on-disk form the entry cache stores and the search provider reads
  # back. Upstream builds a GVariant dictionary (bz_entry_real_serialize);
  # the port writes the same keys into a hash.
  def serialize
    {
      "id"                   => @id,
      "unique-id"            => @unique_id,
      "unique-id-checksum"   => unique_id_checksum,
      "kinds"                => @kinds,
      "title"                => @title,
      "eol"                  => @eol,
      "description"          => @description,
      "long-description"     => @long_description,
      "remote-repo-name"     => @remote_repo_name,
      "url"                  => @url,
      "size"                 => @size,
      "installed-size"       => @installed_size,
      "icon-path"            => @icon_path,
      "icon-url"             => @icon_url,
      "screenshot-urls"      => @screenshot_urls,
      "thumbnail-url"        => @thumbnail_url,
      "search-tokens"        => @search_tokens,
      "metadata-license"     => @metadata_license,
      "project-license"      => @project_license,
      "is-floss"             => @is_floss,
      "project-group"        => @project_group,
      "developer"            => @developer,
      "developer-id"         => @developer_id,
      "donation-url"         => @donation_url,
      "light-accent-color"   => @light_accent_color,
      "dark-accent-color"    => @dark_accent_color,
      "required-controls"    => @required_controls,
      "recommended-controls" => @recommended_controls,
      "supported-controls"   => @supported_controls,
      "min-display-length"   => @min_display_length,
      "max-display-length"   => @max_display_length,
      "categories"           => @categories,
      "installed"            => @installed,
      "installed-version"    => @installed_version,
      "reinstallable"        => @reinstallable,
      "addons"               => @addons,
      "keywords"             => @keywords,
      "screenshot-captions"  => @screenshot_captions,
      "share-urls"           => @share_urls.map(&:to_h),
      "version-history"      => @version_history.map(&:to_h),
      "content-rating"       => @content_rating&.to_h,
      "verification-status"  => @verification_status&.to_h,
    }.compact
  end

  def self.deserialize(hash)
    new.tap do |entry|
      entry.id = hash["id"]
      entry.unique_id = hash["unique-id"]
      entry.unique_id_checksum = hash["unique-id-checksum"]
      entry.kinds = hash.fetch("kinds", 0)
      entry.title = hash["title"]
      entry.eol = hash["eol"]
      entry.description = hash["description"]
      entry.long_description = hash["long-description"]
      entry.remote_repo_name = hash["remote-repo-name"]
      entry.url = hash["url"]
      entry.size = hash.fetch("size", 0)
      entry.installed_size = hash.fetch("installed-size", 0)
      entry.icon_path = hash["icon-path"]
      entry.icon_url = hash["icon-url"]
      entry.screenshot_urls = hash.fetch("screenshot-urls", [])
      entry.thumbnail_url = hash["thumbnail-url"]
      entry.search_tokens = hash["search-tokens"]
      entry.metadata_license = hash["metadata-license"]
      entry.project_license = hash["project-license"]
      entry.is_floss = hash.fetch("is-floss", false)
      entry.project_group = hash["project-group"]
      entry.developer = hash["developer"]
      entry.developer_id = hash["developer-id"]
      entry.donation_url = hash["donation-url"]
      entry.light_accent_color = hash["light-accent-color"]
      entry.dark_accent_color = hash["dark-accent-color"]
      entry.required_controls = hash.fetch("required-controls", CONTROL_NONE)
      entry.recommended_controls = hash.fetch("recommended-controls", CONTROL_NONE)
      entry.supported_controls = hash.fetch("supported-controls", CONTROL_NONE)
      entry.min_display_length = hash.fetch("min-display-length", 0)
      entry.max_display_length = hash.fetch("max-display-length", 0)
      entry.categories = hash.fetch("categories", CategoryFlags::NONE)
      entry.installed = hash.fetch("installed", false)
      entry.installed_version = hash["installed-version"]
      entry.reinstallable = hash.fetch("reinstallable", true)
      entry.keywords = hash.fetch("keywords", [])
      entry.screenshot_captions = hash.fetch("screenshot-captions", [])
      entry.share_urls = hash.fetch("share-urls", []).map { |url| Url.from_h(url) }
      entry.version_history = hash.fetch("version-history", []).map { |r| Release.from_h(r) }
      hash.fetch("addons", []).each { |addon| entry.append_addon(addon) }
      hash["content-rating"].then do |rating|
        case rating
        when nil then nil
        else entry.content_rating = ContentRating.from_h(rating)
        end
      end
      hash["verification-status"].then do |status|
        case status
        when nil then nil
        else entry.verification_status = VerificationStatus.from_h(status)
        end
      end
    end
  end

  private

    def present(value, score)
      case value.nil? || value == ""
      when true then 0
      else score
      end
    end

    def present_when(condition, score)
      case condition
      when true then score
      else 0
      end
    end
end
