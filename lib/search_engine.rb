# frozen_string_literal: true

require_relative "entry_group"

# SearchBias rewrites or re-weights a query.
#
# Ported from upstream's src/bz-search-bias.txt and the bias handling in
# src/bz-search-engine.c. A bias whose regex matches the query can rewrite
# the query (`convert_to`) and boost the apps it names, either linearly
# (score * slope + intercept) or exponentially (factor ** score * intercept).
class SearchBias
  LINEAR = :linear
  EXPONENTIAL = :exponential

  attr_reader :regex,
    :convert_to,
    :boost_appids,
    :boost_kind,
    :slope,
    :y_intercept,
    :factor

  def initialize(regex:, convert_to: nil, boost_appids: [], boost_kind: nil,
                 slope: 1.0, y_intercept: 0.0, factor: 1.0)
    @regex = Regexp.new(regex)
    @convert_to = convert_to
    @boost_appids = boost_appids.to_a
    @boost_kind = boost_kind
    @slope = slope
    @y_intercept = y_intercept
    @factor = factor
    @boost = @boost_appids.to_h { |id| [id, true] }
  rescue RegexpError
    @invalid = true
  end

  def invalid? = @invalid == true

  def matches?(query) = !invalid? && !@regex.match(query).nil?

  def rewrite(query)
    case @convert_to
    when nil then query
    else query.gsub(@regex, @convert_to)
    end
  end

  def boosts?(id) = @boost.key?(id)

  def boost(score)
    case @boost_kind
    when LINEAR then (@slope * score) + @y_intercept
    when EXPONENTIAL then (@factor**score) * @y_intercept
    else score
    end
  end
end

# SearchResult is one hit: the group, its position in the engine's model and
# the score it earned.
#
# Ported from upstream's src/bz-search-result.txt.
class SearchResult
  attr_reader :group, :original_index, :score

  def initialize(group:, original_index:, score:)
    @group = group
    @original_index = original_index
    @score = score
  end
end

# FinishedSearchQuery is what a query returns: the interpreted query after
# any bias rewrote it, the results, and how long it took.
#
# Ported from upstream's src/bz-finished-search-query.txt. The debug rows on
# the search page show all three.
class FinishedSearchQuery
  attr_reader :interpreted_query, :results, :elapsed

  def initialize(interpreted_query:, results:, elapsed:)
    @interpreted_query = interpreted_query
    @results = results
    @elapsed = elapsed
  end

  def n_results = @results.length
end

# SearchEngine scores every entry group against a query.
#
# Ported from upstream's src/bz-search-engine.c, including the scoring in
# `test_strings`: a query token scores against a target token as
# (query_length² / target_length) wherever it appears inside it, and a query
# token that matches nothing at all zeroes the whole score. The field weights
# and their minimum token lengths are upstream's too — title x2 (tokens of 2
# or more), developer x1 (2 or more), description x1 (3 or more) and the
# search tokens x1.5 (any length) — as is the shortcut that an exact id or
# title match beats everything else.
#
# Upstream splits the work across the thread pool with libdex; the port
# scores on the calling thread, which the search page drives from the main
# loop as the user types.
class SearchEngine
  THRESHOLD = 1.0
  EXACT_SCORE = (2**31) - 1

  attr_accessor :model, :biases

  def initialize(model: [], biases: [])
    @model = model
    @biases = biases
  end

  # Runs a query and returns a FinishedSearchQuery.
  #
  # `terms` is the list of words the search bar collected, joined with
  # spaces, exactly as upstream joins its terms strv.
  def query(terms)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    interpreted = interpret(Array(terms).join(" "))
    active = @biases.select { |bias| bias.matches?(interpreted) }

    results = @model.each_with_index.filter_map do |group, index|
      score_group(group, interpreted, active).then do |score|
        case score > THRESHOLD
        when true then SearchResult.new(group: group, original_index: index, score: score)
        else nil
        end
      end
    end

    FinishedSearchQuery.new(
      interpreted_query: interpreted,
      results:           results.sort_by { |result| -result.score },
      elapsed:           Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
    )
  end

  # The score one target string earns for a query, upstream's test_strings.
  #
  # `accept_min_size` drops target tokens shorter than it, so a two-letter
  # word in a description cannot carry a match on its own; a negative value
  # accepts every token.
  def self.test_strings(query, against, accept_min_size)
    score = 0.0
    tokenize(query).each do |query_token|
      matched = false
      tokenize(against).each do |against_token|
        case accept_min_size.positive? && against_token.length < accept_min_size
        when true then next
        end
        case against_token.downcase.include?(query_token.downcase)
        when true
          score += (query_token.length**2).fdiv(against_token.length)
          matched = true
        end
      end

      case matched
      when false
        score = 0.0
        break
      end
    end
    score
  end

  # Upstream walks the string with GUnicodeType and treats every
  # space-separator run as a boundary.
  def self.tokenize(text) = text.to_s.split(/[[:space:]]+/).reject(&:empty?)

  private

    def interpret(query)
      @biases.select { |bias| bias.matches?(query) }
             .reduce(query) { |current, bias| bias.rewrite(current) }
    end

    def score_group(group, query, active_biases)
      case group.searchable?
      when false then 0.0
      else
        apply_biases(group, base_score(group, query), active_biases)
      end
    end

    def base_score(group, query)
      case exact?(group, query)
      when true then EXACT_SCORE.to_f
      else
        [
          [group.title, 2, 2.0],
          [group.developer, 2, 1.0],
          [group.description, 3, 1.0],
          [group.search_tokens, -1, 1.5],
        ].sum { |value, minimum, weight| evaluate(query, value, minimum) * weight }
      end
    end

    def exact?(group, query)
      group.id == query || group.title.to_s.downcase == query.downcase
    end

    def evaluate(query, against, minimum)
      case against.nil?
      when true then 0.0
      else self.class.test_strings(query, against, minimum)
      end
    end

    def apply_biases(group, score, active_biases)
      active_biases.reduce(score) do |current, bias|
        case bias.boosts?(group.id)
        when true then bias.boost(current)
        else current
        end
      end
    end
end
