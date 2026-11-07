# frozen_string_literal: true

require "gtk4"
require "adwaita"

# Importance is BzImportance: the five-step scale the context/safety/
# hardware dialogs use to colour a row or a lozenge.
#
# Ported from upstream's src/bz-context-row.c (bz_importance_get_type and
# bz_context_row_importance_to_css_class).
module Importance
  UNIMPORTANT = :unimportant
  NEUTRAL = :neutral
  INFORMATION = :information
  WARNING = :warning
  IMPORTANT = :important

  ORDER = [IMPORTANT, WARNING, INFORMATION, NEUTRAL, UNIMPORTANT].freeze

  CSS_CLASSES = {
    UNIMPORTANT => "green",
    NEUTRAL     => "grey",
    INFORMATION => "yellow",
    WARNING     => "orange",
    IMPORTANT   => "red",
  }.freeze

  def self.css_class(importance) = CSS_CLASSES.fetch(importance, "grey")
end

# ContextRow builds the Adw::ActionRow the safety, hardware-support and
# app-size dialogs list: an icon coloured by importance, a title and a
# subtitle.
#
# Ported from upstream's src/bz-context-row.c (bz_context_row_new). There is
# no .blp — upstream builds the row entirely in C.
module ContextRow
  def self.build(icon_name:, importance:, title:, subtitle: nil)
    Adwaita::ActionRow.new.tap do |row|
      row.title = title
      row.subtitle = subtitle.to_s if subtitle
      row.add_prefix(
        Gtk::Image.new(icon_name: icon_name).tap do |icon|
          icon.valign = :center
          icon.add_css_class("circular-lozenge")
          icon.add_css_class(Importance.css_class(importance))
        end,
      )
    end
  end
end
