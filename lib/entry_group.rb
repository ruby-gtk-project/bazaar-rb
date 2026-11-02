# frozen_string_literal: true

require "gtk4"
require_relative "entry"

# EntryGroup folds every entry that describes the same app — one per remote,
# plus the installed one — into the single row or tile the UI shows.
#
# Ported from upstream's src/bz-entry-group.c, src/bz-entry-group.h and
# src/bz-entry-group-util.c.
#
# The fields come from whichever member entry carries the most usable
# metadata: `add` scores each entry with Entry#calc_usefulness and the
# winner's title, developer, icon and colours become the group's. The
# installable / updatable / removable counts drive the install controls, and
# the "_and_available" variants drop entries a running transaction is holding,
# which is how a button goes insensitive mid-install.
class EntryGroup < GLib::Object
  type_register

  INSTALLABLE           = 1 << 0
  INSTALLABLE_AVAILABLE = 1 << 1
  UPDATABLE             = 1 << 2
  UPDATABLE_AVAILABLE   = 1 << 3
  REMOVABLE             = 1 << 4
  REMOVABLE_AVAILABLE   = 1 << 5

  attr_reader :id,
    :title,
    :developer,
    :description,
    :mini_icon,
    :eol,
    :search_tokens,
    :light_accent_color,
    :dark_accent_color,
    :installed_size,
    :donation_url,
    :categories,
    :content_rating,
    :n_addons,
    :addon_group_ids,
    :unique_ids,
    :installed_versions

  def initialize(factory: nil)
    super()
    @factory = factory
    @unique_ids = []
    @installed_versions = []
    @state_flags = []
    @addon_group_ids = []
    @max_usefulness = -(2**31)
    @installable = 0
    @installable_available = 0
    @updatable = 0
    @updatable_available = 0
    @removable = 0
    @removable_available = 0
    @n_addons = 0
    @installed_size = 0
    @categories = CategoryFlags::NONE
    @is_floss = false
    @is_flathub = false
    @is_verified = false
    @is_mobile_friendly = false
    @searchable = false
    @is_addon = false
    @read_only = false
    @entries = {}
    @listeners = []
  end

  # A group built around one entry the app already holds, used for a local
  # bundle file and for the standalone pages that show a single entry.
  def self.for_single_entry(entry)
    new.tap do |group|
      group.standalone_entry = entry
      group.add(entry)
    end
  end

  # A group with no entries behind it at all: the curated config can name an
  # app that no configured remote carries, and it still gets a tile.
  def self.manual(id:, title:, subtitle: nil)
    new.tap do |group|
      group.assign_manual(id, title, subtitle)
    end
  end

  attr_accessor :standalone_entry
  attr_writer :factory

  def assign_manual(id, title, subtitle)
    @id = id
    @title = title
    @description = subtitle
    notify
  end

  def is_floss = @is_floss
  alias floss? is_floss

  def is_flathub = @is_flathub
  alias flathub? is_flathub

  def is_verified = @is_verified
  alias verified? is_verified

  def is_mobile_friendly = @is_mobile_friendly
  alias mobile_friendly? is_mobile_friendly

  def searchable? = @searchable
  def addon? = @is_addon
  def read_only? = @read_only

  # Upstream returns 0 for an app the user cannot install or remove — Bazaar
  # itself, which must not uninstall the running process.
  def installable
    case @read_only
    when true then 0
    else @installable
    end
  end

  def updatable = @updatable

  def removable
    case @read_only
    when true then 0
    else @removable
    end
  end

  def installable_and_available = @installable_available
  def updatable_and_available = @updatable_available
  def removable_and_available = @removable_available

  def has_category?(name) = CategoryFlags.has_name?(@categories, name)

  def append_addon_group_id(id)
    @addon_group_ids << id
    notify
    id
  end

  # The entry the UI reads its fields from: the most useful one, which `add`
  # keeps at the head of the unique-id list.
  def ui_entry
    case @standalone_entry
    when nil
      ui_entry_id.then do |unique_id|
        case unique_id
        when nil then nil
        else @entries[unique_id] || @factory&.convert_one(unique_id)
        end
      end
    else @standalone_entry
    end
  end

  def ui_entry_id = @unique_ids.first

  def model = @unique_ids.map { |unique_id| @entries[unique_id] }.compact

  # Registers a block to run whenever the group's fields or counts change,
  # standing in for the property notifications upstream emits.
  def on_change(&block)
    @listeners << block
    block
  end

  # Folds one more entry into the group. `runtime` is the entry the app runs
  # on, consulted only for its EOL marker; `ignore_eol` is how the library
  # page shows an installed app whose runtime has gone end-of-life.
  def add(entry, runtime: nil, ignore_eol: false)
    is_addon = entry.addon?
    @is_addon = if_addon(is_addon)

    case @id
    when nil
      @id = entry.id
      @read_only = @id == Gio::Application.default&.application_id
    end

    unique_id = entry.unique_id
    installed_version = entry.installed_version

    case ignore_eol
    when false then absorb_eol(entry, runtime)
    end

    usefulness = entry.calc_usefulness
    existing = @unique_ids.index(unique_id)

    case usefulness >= @max_usefulness
    when true then absorb_preferred(
      entry,
      unique_id,
      installed_version,
      existing,
      is_addon,
    )
    else absorb_secondary(
      entry,
      unique_id,
      installed_version,
      existing,
      is_addon,
    )
    end

    @entries[unique_id] = entry
    revert_state_flags(existing)
    record_state_flags(entry, existing)

    @searchable = if_searchable(!is_addon && entry.searchable?)
    notify
    entry
  end

  # Recomputes the installable / removable counts against the set of unique
  # ids the backend reports as installed, and answers whether any member of
  # the group is installed. The library page's model is built from the groups
  # this returns true for.
  def reconcile_with_installed_set(installed_set)
    @installable = 0
    @removable = 0
    @installable_available = 0
    @removable_available = 0
    any_installed = false

    @unique_ids.each_with_index do |unique_id, index|
      flags = 0
      case installed_set.include?(unique_id)
      when true
        flags |= REMOVABLE | REMOVABLE_AVAILABLE
        @removable += 1
        @removable_available += 1
        any_installed = true
      else
        flags |= INSTALLABLE | INSTALLABLE_AVAILABLE
        @installable += 1
        @installable_available += 1
      end
      @state_flags[index] = flags
    end

    notify
    any_installed
  end

  # Marks the group as having an update waiting, which is what puts the badge
  # on the Library tab and the app in the updates card.
  def mark_updatable(unique_id)
    @unique_ids.index(unique_id).then do |index|
      case index
      when nil then false
      else
        @state_flags[index] = @state_flags.fetch(index, 0) | UPDATABLE | UPDATABLE_AVAILABLE
        @updatable += 1
        @updatable_available += 1
        notify
        true
      end
    end
  end

  def serialize
    {
      "id"                 => @id,
      "title"              => @title,
      "developer"          => @developer,
      "description"        => @description,
      "eol"                => @eol,
      "search-tokens"      => @search_tokens,
      "installed-size"     => @installed_size,
      "donation-url"       => @donation_url,
      "categories"         => @categories,
      "unique-ids"         => @unique_ids,
      "installed-versions" => @installed_versions,
      "addon-group-ids"    => @addon_group_ids,
      "is-floss"           => @is_floss,
      "is-flathub"         => @is_flathub,
      "is-verified"        => @is_verified,
      "is-addon"           => @is_addon,
    }.compact
  end

  def self.deserialize(hash, factory: nil)
    new(factory: factory).tap do |group|
      group.load_serialized(hash)
    end
  end

  def load_serialized(hash)
    @id = hash["id"]
    @title = hash["title"]
    @developer = hash["developer"]
    @description = hash["description"]
    @eol = hash["eol"]
    @search_tokens = hash["search-tokens"]
    @installed_size = hash.fetch("installed-size", 0)
    @donation_url = hash["donation-url"]
    @categories = hash.fetch("categories", CategoryFlags::NONE)
    @unique_ids = hash.fetch("unique-ids", [])
    @installed_versions = hash.fetch("installed-versions", [])
    @addon_group_ids = hash.fetch("addon-group-ids", [])
    @state_flags = Array.new(@unique_ids.length, 0)
    @is_floss = hash.fetch("is-floss", false)
    @is_flathub = hash.fetch("is-flathub", false)
    @is_verified = hash.fetch("is-verified", false)
    @is_addon = hash.fetch("is-addon", false)
    notify
    self
  end

  private

    def notify
      @listeners.each(&:call)
    end

    def if_addon(is_addon)
      case is_addon
      when true then true
      else @is_addon
      end
    end

    def if_searchable(searchable)
      case searchable
      when true then true
      else @searchable
      end
    end

    # The group inherits an EOL marker from the entry or, failing that, from
    # the runtime the entry needs: an app on a dead runtime is dead too.
    def absorb_eol(entry, runtime)
      (entry.eol || runtime&.eol).then do |eol|
        case eol
        when nil then nil
        else @eol = eol
        end
      end
    end

    # This entry carries at least as much metadata as the best one so far, so
    # it becomes the group's face: its unique id goes to the head of the list
    # and its fields overwrite the group's.
    def absorb_preferred(entry, unique_id, installed_version, existing, is_addon)
      case existing
      when nil then nil
      else
        @unique_ids.delete_at(existing)
        @installed_versions.delete_at(existing)
        @state_flags.delete_at(existing)
      end
      @unique_ids.unshift(unique_id)
      @installed_versions.unshift(installed_version || "")
      @state_flags.unshift(0)

      @title = unless_nil(entry.title, @title)
      @description = unless_nil(entry.description, @description)
      @installed_size = entry.installed_size
      @is_flathub = entry.is_flathub
      @is_floss = entry.is_foss
      @is_verified = verified_for(entry, is_addon)

      case is_addon
      when false then absorb_app_fields(entry)
      end

      @max_usefulness = entry.calc_usefulness
    end

    # A less useful entry still contributes any field the group is missing,
    # and still counts towards the install / remove totals.
    def absorb_secondary(entry, unique_id, installed_version, existing, is_addon)
      case existing
      when nil
        @unique_ids << unique_id
        @installed_versions << (installed_version || "")
        @state_flags << 0
      end

      @title ||= entry.title
      @description ||= entry.description
      @installed_size = if_zero(@installed_size, entry.installed_size)

      case is_addon
      when false
        @developer ||= entry.developer
        @mini_icon ||= entry.mini_icon
        @search_tokens ||= entry.search_tokens
        @light_accent_color ||= entry.light_accent_color
        @dark_accent_color ||= entry.dark_accent_color
        @donation_url ||= entry.donation_url
      end
    end

    def absorb_app_fields(entry)
      @developer = unless_nil(entry.developer, @developer)
      @mini_icon = unless_nil(entry.mini_icon, @mini_icon)
      @search_tokens = unless_nil(entry.search_tokens, @search_tokens)
      @light_accent_color = unless_nil(entry.light_accent_color, @light_accent_color)
      @dark_accent_color = unless_nil(entry.dark_accent_color, @dark_accent_color)
      @donation_url = unless_nil(entry.donation_url, @donation_url)
      @is_mobile_friendly = entry.is_mobile_friendly
      @n_addons = entry.addons.length
      @content_rating = unless_nil(entry.content_rating, @content_rating)
      case entry.categories != CategoryFlags::NONE
      when true then @categories = entry.categories
      end
    end

    def unless_nil(value, fallback)
      case value.nil?
      when true then fallback
      else value
      end
    end

    def if_zero(current, replacement)
      case current.zero? && replacement.to_i.positive?
      when true then replacement
      else current
      end
    end

    # An add-on is always treated as verified, because the verified-only
    # filter would otherwise hide every add-on of a verified app.
    def verified_for(entry, is_addon)
      case is_addon
      when true then true
      else entry.verified?
      end
    end

    def revert_state_flags(existing)
      case existing
      when nil then nil
      else
        @state_flags.fetch(existing, 0).then do |previous|
          @installable -= if_flag(previous, INSTALLABLE)
          @installable_available -= if_flag(previous, INSTALLABLE_AVAILABLE)
          @updatable -= if_flag(previous, UPDATABLE)
          @updatable_available -= if_flag(previous, UPDATABLE_AVAILABLE)
          @removable -= if_flag(previous, REMOVABLE)
          @removable_available -= if_flag(previous, REMOVABLE_AVAILABLE)
        end
      end
    end

    def if_flag(flags, flag)
      case (flags & flag) != 0
      when true then 1
      else 0
      end
    end

    def record_state_flags(entry, existing)
      flags = 0
      case entry.installed?
      when true
        @removable += 1
        flags |= REMOVABLE
        case entry.holding?
        when false
          @removable_available += 1
          flags |= REMOVABLE_AVAILABLE
        end
      else
        case entry.reinstallable?
        when true
          @installable += 1
          flags |= INSTALLABLE
          case entry.holding?
          when false
            @installable_available += 1
            flags |= INSTALLABLE_AVAILABLE
          end
        end
      end

      (existing || @unique_ids.index(entry.unique_id)).then do |index|
        case index
        when nil then nil
        else @state_flags[index] = flags
        end
      end
      flags
    end
end
