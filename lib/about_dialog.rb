# frozen_string_literal: true

require "adwaita"
require_relative "bazaar/rb/version"

# AboutDialog is the dialog the app.about action presents.
#
# Ported from bz_application_about_action in upstream's
# src/bz-application.c: the same application name and icon, developer name,
# developer list, copyright, licence, website and issue url, plus the
# "Special Thanks" acknowledgement section.
class AboutDialog
  APPLICATION_NAME = "Bazaar"
  APPLICATION_ICON = "io.github.kolunmi.Bazaar"
  DEVELOPER_NAME = "The Bazaar Contributors"
  COPYRIGHT = "© 2025-2026 The Bazaar Contributors"
  WEBSITE = "https://usebazaar.org"
  ISSUE_URL = "https://github.com/bazaar-org/bazaar/issues"

  DEVELOPERS = [
    "Adam Masciola <kolunmi@posteo.net>",
    "Alexander Vanhee",
  ].freeze

  SPECIAL_THANKS = [
    "arewelibadwaitayet https://arewelibadwaitayet.com/",
  ].freeze

  def build
    dialog.tap do |about|
      about.add_acknowledgement_section("Special Thanks", SPECIAL_THANKS)
    end
  end

  def dialog
    @dialog ||= Adwaita::AboutDialog.new.tap do |about|
      about.application_name = APPLICATION_NAME
      about.application_icon = APPLICATION_ICON
      about.developer_name = DEVELOPER_NAME
      about.developers = DEVELOPERS
      about.translator_credits = "translator-credits"
      about.version = Bazaar::Rb::VERSION
      about.copyright = COPYRIGHT
      about.license_type = Gtk::License::GPL_3_0
      about.website = WEBSITE
      about.issue_url = ISSUE_URL
    end
  end
end
