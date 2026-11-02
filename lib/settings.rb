# frozen_string_literal: true

require "json"
require "fileutils"

# Settings holds the keys of upstream's io.github.kolunmi.Bazaar GSettings
# schema (data/io.github.kolunmi.Bazaar.gschema.xml).
#
# Upstream uses GSettings, which needs a compiled schema installed into a
# directory on XDG_DATA_DIRS before the app will even start. Requiring an
# install step to run the port from a checkout is worse than the alternative,
# so the same keys, defaults, types and choices are backed by a small JSON
# file under XDG_CONFIG_HOME instead.
#
# The "changed" notification GSettings emits is kept, because the preferences
# dialog and the window both lean on it: `on_change` registers a listener and
# `bind` ties a widget property to a key in both directions, the way
# g_settings_bind does.
class Settings
  DEFAULTS = {
    "hide-eol"                  => true,
    "show-only-foss"            => false,
    "show-only-flathub"         => false,
    "show-only-verified"        => false,
    "global-progress-bar-theme" => "accent-color",
    "window-dimensions"         => [1220, 900],
    "force-adwaita-icons"       => true,
    "show-permission-banner"    => true,
    "check-for-ubuntu"          => true,
    "auto-update"               => false,
    "auto-update-notifications" => true,
    "last-update-check"         => 0,
    "update-check-hour-offset"  => -1,
    "last-refresh-time"         => 0,
    "last-stale-notification"   => 0,
  }.freeze

  # The <choices> list on the global-progress-bar-theme key. A value outside
  # this set is refused, exactly as GSettings would refuse it.
  PROGRESS_BAR_THEMES = [
    "accent-color",
    "pride-rainbow-flag",
    "lesbian-pride-flag",
    "gay-pride-flag",
    "transgender-flag",
    "nonbinary-flag",
    "bisexual-flag",
    "asexual-flag",
    "pansexual-flag",
    "aromantic-flag",
    "genderfluid-flag",
    "polysexual-flag",
    "omnisexual-flag",
    "aroace-flag",
    "agender-flag",
    "genderqueer-flag",
    "intersex-flag",
    "demigender-flag",
    "biromantic-flag",
    "disability-flag",
    "femboy-flag",
    "neutrois-flag",
  ].freeze

  CHOICES = { "global-progress-bar-theme" => PROGRESS_BAR_THEMES }.freeze

  def initialize(path: nil)
    @path = path || default_path
    @values = DEFAULTS.merge(read)
    @listeners = {}
  end

  def location = @path

  def [](key) = @values.fetch(key.to_s, DEFAULTS[key.to_s])

  def []=(key, value)
    name = key.to_s
    DEFAULTS.fetch(name)
    validate(name, value)
    @values[name] = value
    write
    notify(name)
    value
  end

  # Named accessors so callers do not repeat the string keys. A boolean key
  # also gets a `?` reader.
  DEFAULTS.each_key do |key|
    method_name = key.tr("-", "_")
    define_method(method_name) { self[key] }
    define_method(:"#{method_name}=") { |value| self[key] = value }
    case DEFAULTS[key]
    when true, false
      define_method(:"#{method_name}?") { self[key] == true }
    end
  end

  # Registers a listener for one key, like "changed::<key>" does on GSettings.
  # The block is called with the new value.
  def on_change(key, &block)
    (@listeners[key.to_s] ||= []) << block
    block
  end

  # The port's stand-in for g_settings_bind with G_SETTINGS_BIND_DEFAULT: the
  # widget property takes the stored value now, writes back on every change,
  # and follows later writes from elsewhere in the app.
  def bind(key, object, property)
    object.set_property(property.to_s, self[key])
    object.signal_connect("notify::#{property}") do
      object.get_property(property.to_s).then do |value|
        case value == self[key]
        when false then self[key] = value
        end
      end
    end
    on_change(key) { |value| object.set_property(property.to_s, value) }
  end

  # Window geometry is a single (ii) tuple upstream; keep the pair together
  # but let callers ask for either half.
  def window_width = window_dimensions[0]
  def window_height = window_dimensions[1]

  def remember_window_size(width, height)
    self["window-dimensions"] = [width, height]
  end

  private

    def notify(name)
      @listeners.fetch(name, []).each { |block| block.call(@values[name]) }
    end

    def validate(name, value)
      CHOICES.fetch(name, nil).then do |choices|
        case choices.nil? || choices.include?(value)
        when false
          raise ArgumentError, "#{value.inspect} is not a valid value for #{name}"
        end
      end
    end

    def default_path
      File.join(
        ENV.fetch("XDG_CONFIG_HOME", File.join(Dir.home, ".config")),
        "bazaar-rb",
        "settings.json",
      )
    end

    def read
      case File.exist?(@path)
      when false then {}
      else
        JSON.parse(File.read(@path)).select { |key, _| DEFAULTS.key?(key) }
      end
    rescue JSON::ParserError, SystemCallError
      {}
    end

    def write
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, "#{JSON.pretty_generate(@values)}\n")
    rescue SystemCallError
      nil
    end
end
