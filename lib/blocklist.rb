# frozen_string_literal: true

# BlocklistCondition decides whether a blocklist applies to this machine at
# all: it matches an environment variable or the user's locale, optionally
# inverted.
#
# Ported from upstream's src/bz-blocklist-condition.txt and the condition
# evaluation in blocklists_changed (src/bz-application.c). Both matchers are
# anchored, as upstream compiles them with G_REGEX_ANCHORED.
class BlocklistCondition
  IDENTITY = :identity
  INVERT   = :invert

  attr_reader :match_envvar, :match_locale, :post_process

  def initialize(match_envvar: nil, match_locale: nil, post_process: IDENTITY)
    @match_envvar = match_envvar
    @match_locale = match_locale
    @post_process = post_process
  end

  # An empty condition is ignored rather than failing the blocklist, which is
  # what upstream warns about and skips.
  def empty? = @match_envvar.nil? && @match_locale.nil?

  def satisfied?(locales: self.class.language_names, env: ENV)
    post_processed(matches_envvar?(env) || matches_locale?(locales))
  end

  # The locales g_get_language_names would report, most specific first.
  def self.language_names
    ENV.values_at("LC_ALL", "LC_MESSAGES", "LANG").compact.reject(&:empty?)
       .flat_map { |value| [value, value.split(".").first, value.split("_").first] }
       .compact.uniq + ["C"]
  end

  private

    def matches_envvar?(env)
      case @match_envvar
      when nil then false
      else
        anchored(@match_envvar[:regex] || @match_envvar["regex"]).then do |regex|
          variable = @match_envvar[:var] || @match_envvar["var"]
          case regex.nil? || variable.nil?
          when true then false
          else !regex.match(env[variable].to_s).nil? && !env[variable].nil?
          end
        end
      end
    end

    def matches_locale?(locales)
      case @match_locale
      when nil then false
      else
        anchored(@match_locale[:regex] || @match_locale["regex"]).then do |regex|
          case regex
          when nil then false
          else locales.any? { |locale| !regex.match(locale).nil? }
          end
        end
      end
    end

    def anchored(pattern)
      case pattern
      when nil then nil
      else Regexp.new("\\A(?:#{pattern})")
      end
    end

    def post_processed(result)
      case @post_process
      when INVERT then !result
      else result
      end
    end
end

# Blocklist is one list of ids to allow or block, with a priority and the
# conditions under which it applies.
#
# Ported from upstream's src/bz-blocklist.txt and
# src/blocklist-schema.xml. The plain `allow` / `block` entries are literal
# ids and the `*_regex` ones are patterns; upstream escapes the literals,
# joins each group with "|" and anchors the result with "^(...)$", which is
# what `allow_regex`/`block_regex` build here.
class Blocklist
  attr_reader :priority, :conditions

  def initialize(priority: 0, conditions: [], allow: [], allow_regex: [], block: [], block_regex: [])
    @priority = priority
    @conditions = conditions
    @allow = allow
    @allow_patterns = allow_regex
    @block = block
    @block_patterns = block_regex
  end

  # Upstream warns about and ignores a blocklist with nothing in it.
  def empty? = @allow.empty? && @allow_patterns.empty? && @block.empty? && @block_patterns.empty?

  def applies? = @conditions.reject(&:empty?).all?(&:satisfied?)

  def allow_matcher = @allow_matcher ||= matcher(@allow, @allow_patterns)
  def block_matcher = @block_matcher ||= matcher(@block, @block_patterns)

  def allows?(id) = matches?(allow_matcher, id)
  def blocks?(id) = matches?(block_matcher, id)

  def self.from_h(hash)
    new(
      priority:    hash["priority"].to_i,
      conditions:  Array(hash["conditions"]).map { |condition| condition_from_h(condition) },
      allow:       Array(hash["allow"]),
      allow_regex: Array(hash["allow-regex"] || hash["allow_regex"]),
      block:       Array(hash["block"]),
      block_regex: Array(hash["block-regex"] || hash["block_regex"]),
    )
  end

  def self.condition_from_h(hash)
    BlocklistCondition.new(
      match_envvar: hash["match-envvar"] || hash["match_envvar"],
      match_locale: hash["match-locale"] || hash["match_locale"],
      post_process: post_process_from(hash["post-process"] || hash["post_process"]),
    )
  end

  def self.post_process_from(value)
    case value.to_s
    when "invert" then BlocklistCondition::INVERT
    else BlocklistCondition::IDENTITY
    end
  end

  private

    def matcher(literals, patterns)
      (literals.map { |literal| Regexp.escape(literal) } + valid(patterns)).then do |all|
        case all.empty?
        when true then nil
        else Regexp.new("^(#{all.join("|")})$")
        end
      end
    end

    # An invalid pattern is dropped with a warning upstream rather than
    # taking the whole blocklist down.
    def valid(patterns)
      patterns.select do |pattern|
        Regexp.new(pattern)
        true
      rescue RegexpError
        warn("Blocklist file has an invalid regular expression '#{pattern}'")
        false
      end
    end

    def matches?(regex, id)
      case regex
      when nil then false
      else !regex.match(id.to_s).nil?
      end
    end
end

# BlocklistSet is every blocklist the app loaded, plus the plain-text lists
# of ids, and the verdict they reach together.
#
# Ported from the blocklist half of upstream's validate_group_for_ui: a txt
# list blocks outright, and otherwise the lowest-priority allow wins over the
# lowest-priority block (ties going to allow).
class BlocklistSet
  def initialize(blocklists: [], blocked_id_sets: [])
    @blocklists = blocklists.reject(&:empty?).select(&:applies?)
    @blocked_id_sets = blocked_id_sets
  end

  def empty? = @blocklists.empty? && @blocked_id_sets.empty?

  def allows?(id)
    case @blocked_id_sets.any? { |set| set.include?(id) }
    when true then false
    else allowed_priority(id) <= blocked_priority(id)
    end
  end

  # Reads a newline-separated list of ids, upstream's txt blocklist format
  # (src/bz-newline-parser.c): one id per line, blank lines and "#" comments
  # ignored.
  def self.read_id_list(path)
    File.readlines(path, chomp: true)
        .map { |line| line.sub(/#.*\z/, "").strip }
        .reject(&:empty?)
        .to_h { |id| [id, true] }
        .keys
  rescue SystemCallError
    []
  end

  private

    def allowed_priority(id)
      @blocklists.select { |list| list.allows?(id) }.map(&:priority).min || Float::INFINITY
    end

    def blocked_priority(id)
      @blocklists.select { |list| list.blocks?(id) }.map(&:priority).min || Float::INFINITY
    end
end
