# frozen_string_literal: true

require "gtk4"
require "adwaita"
require_relative "entry"
require_relative "backend"

# EntrySelectionRow is one candidate in the "same app, multiple remotes"
# picker: a radio button, the repository's title, and a subtitle giving the
# entry's version and whether the remote is user- or system-wide.
#
# Ported from upstream's src/bz-entry-selection-row.c and
# src/bz-entry-selection-row.blp. The row is activatable through its radio
# (clicking anywhere on the row toggles it, same as the template's
# `activatable-widget: radio`), and the trailing person icon only appears
# for a user remote, matching the template's visibility binding on
# `repository.is-user`.
class EntrySelectionRow
  def initialize(entry:, repository:)
    @entry = entry
    @repository = repository
  end

  attr_reader :entry, :repository

  def radio = @radio ||= Gtk::CheckButton.new.tap { |button| button.valign = :center }

  def build
    row.tap do |r|
      r.add_prefix(radio)
      r.add_suffix(user_icon)
      r.activatable_widget = radio
    end
  end

  def row
    @row ||= Adwaita::ActionRow.new.tap do |r|
      r.title = @repository&.title.to_s
      r.subtitle = subtitle
    end
  end

  def user_icon
    @user_icon ||= Gtk::Image.new(icon_name: "person-symbolic").tap do |icon|
      icon.visible = @repository&.user? == true
      icon.tooltip_text = "For This User Only"
      icon.has_tooltip = true
    end
  end

  private

  def subtitle
    version = @entry&.version_history&.first&.version
    scope = @repository&.user? ? "this user" : "all users"
    version ? "#{version} • #{scope}" : scope
  end
end
