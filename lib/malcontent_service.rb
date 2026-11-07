# frozen_string_literal: true

require "gio2"
require "malcontent"
require_relative "entry"

# MalcontentService asks malcontentd, over the system bus, for the parental
# controls filter of the user running the app, and turns it into the single
# "parental_age_rating" ceiling StateInfo exposes.
#
# Ported from upstream's src/bz-malcontent-service.c, which does the same
# over MctManager directly and re-queries on the service's
# "notify::parental-age-rating" signal. The port has no change notification
# yet -- malcontentd itself does not emit one the gem surfaces -- so `start`
# is a one-shot read taken at application startup, same as the value
# bz-application.c falls back to until the first filter arrives.
class MalcontentService
  # `unavailable_reason` is set when `start` could not reach malcontentd;
  # the preferences dialog can surface this instead of pretending parental
  # controls were checked.
  attr_reader :state, :unavailable_reason

  def initialize(state:)
    @state = state
  end

  # Connects to the system bus and loads the current user's app filter.
  #
  # Any failure here -- no system bus, no accounts service, no polkit
  # authority -- is the same "parental controls are simply off" case
  # bz_application_init takes when bz_malcontent_service_new returns NULL
  # (self->malcontent stays NULL and validate_group_for_ui never checks it).
  # The port records *why* instead of swallowing it silently.
  def start
    manager = Malcontent::Manager.new(Gio.bus_get_sync(:system, nil))
    filter = manager.get_app_filter(Process.uid, :none, nil)
    state.parental_age_rating = filter.oars_sections.filter_map { |section| ContentRating::AGE_BY_VALUE[filter.get_oars_value(section).to_s] }.max || -1
    true
  rescue GLib::Error, Malcontent::ManagerError => e
    @unavailable_reason = e.message
    state.parental_age_rating = -1
    false
  end
end
