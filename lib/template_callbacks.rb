# frozen_string_literal: true

# TemplateCallbacks holds the small helpers the Blueprint templates call.
#
# Ported from upstream's src/template-callbacks.c, which binds all of these
# onto every widget class so a .blp file can write
# `$invert_boolean(template.state.busy)`. The port has no templates, so the
# same helpers are plain module functions the widget classes call directly —
# and the formatting ones (`format_size`, `format_title`,
# `format_install_count`) keep the exact wording their callers show.
module TemplateCallbacks
  SIZE_UNITS = ["bytes", "kB", "MB", "GB", "TB", "PB"].freeze

  module_function

  def invert_boolean(value) = !truthy(value)
  def logical_not(value) = !truthy(value)
  def is_zero(value) = value.to_i.zero?
  def is_double_zero(value) = value.to_f.zero?
  def is_null(value) = value.nil?
  def is_gt(value, other) = value > other
  def is_lt(value, other) = value < other
  def is_ge(value, other) = value >= other
  def is_le(value, other) = value <= other
  def logical_and(left, right) = truthy(left) && truthy(right)
  def logical_or(left, right) = truthy(left) || truthy(right)
  def is_positive(value) = value.to_i >= 0
  def is_empty(model) = model.nil? || model.length.zero?
  def is_empty_string(string) = string.nil? || string.to_s.empty?
  def is_valid_string(string) = !is_empty_string(string)
  def is_longer(model, value) = !model.nil? && model.length > value

  def bool_to_string(condition, if_true, if_false)
    case truthy(condition)
    when true then if_true
    else if_false
    end
  end

  def choose_object(condition, if_true, if_false)
    case truthy(condition)
    when true then if_true
    else if_false
    end
  end

  def format_int(value) = value.to_i.to_s
  def format_uint(value) = value.to_i.to_s
  def format_double(value) = format("%f", value.to_f)

  # g_format_size: SI units, one decimal place above a kilobyte.
  def format_size(bytes)
    value = bytes.to_i.to_f
    unit = 0
    while value >= 1000 && unit < SIZE_UNITS.length - 1
      value /= 1000
      unit += 1
    end

    case unit
    when 0 then "#{value.to_i} #{SIZE_UNITS[0]}"
    else format("%.1f %s", value, SIZE_UNITS[unit])
    end
  end

  # The window title: the app's name alone on the main page, and
  # "Bazaar — <page>" on a pushed page. Ported from format_title in
  # src/bz-window.c.
  def format_title(title)
    case is_empty_string(title) || title == "Bazaar"
    when true then "Bazaar"
    else "Bazaar — #{title}"
    end
  end

  # Ported from format_description in src/bz-installed-tile.c: the installed
  # versions, then the installed size.
  def format_description(size, versions)
    Array(versions).reject { |version| is_empty_string(version) }.join(" ").then do |joined|
      case joined.empty?
      when true then format_size(size)
      else "#{joined} • #{format_size(size)}"
      end
    end
  end

  # Ported from format_install_count in src/bz-library-page.c.
  def format_install_count(count)
    case count
    when 1 then "1 Installed App"
    else "#{count} Installed Apps"
    end
  end

  # Ported from format_update_count in src/bz-library-page.c.
  def format_update_count(count)
    case count
    when 1 then "1 Available Update"
    else "#{count} Available Updates"
    end
  end

  # Ported from no_results_found_subtitle in src/bz-library-page.c.
  def no_results_found_subtitle(text)
    "No matches found for \"#{text}\" in the list of installed apps"
  end

  def truthy(value)
    case value
    when nil, false then false
    when 0 then false
    else true
    end
  end
end
