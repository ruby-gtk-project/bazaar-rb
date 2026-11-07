# frozen_string_literal: true

require "appstream"

# Spdx answers the small set of license questions the license dialog needs.
#
# Ported from upstream's src/spdx.c, which is itself a thin wrapper over
# libappstream's as_get_license_url / as_license_to_spdx_id. The port calls
# the same functions through the `appstream` gem's `AppStream` module
# instead of hand-rolling an SPDX table.
module Spdx
  def self.valid?(license_id) = !AppStream.get_license_url(license_id.to_s).to_s.empty?

  def self.url(license_id) = AppStream.get_license_url(license_id.to_s)

  # Matches upstream bz_spdx_get_name exactly: a proprietary id is reported
  # as "Proprietary", everything else is normalised through
  # as_license_to_spdx_id (falling back to the id itself).
  def self.name(license_id)
    case proprietary?(license_id)
    when true then "Proprietary"
    else AppStream.license_to_spdx_id(license_id.to_s) || license_id.to_s
    end
  end

  def self.proprietary?(license_id) = license_id.to_s.start_with?("LicenseRef-proprietary")
end
