# frozen_string_literal: true

require "glib2"

# AuthState tracks the signed-in Flathub session: a display name, a token,
# when that token expires, and a profile icon URL.
#
# Ported from upstream's src/bz-auth-state.c and src/bz-auth-state.h.
# Upstream persists the session in the system keyring through libsecret and
# loads it back on construction; there is no GObject-Introspection binding
# for libsecret on the Gemfile, so this port keeps the session in memory for
# the life of the process instead of across restarts. Everything downstream
# of that — the expiry timer that clears the session automatically, the
# change notifications on name/token/icon/authenticated, and
# `authenticated?` deriving from whether a non-empty token is present — is
# ported as-is. The profile icon is kept as the resolved URL rather than a
# loaded texture, matching how the port represents remote images elsewhere
# until BzAsyncTexture's own component is ported.
class AuthState
  attr_reader :name, :token, :token_expires, :profile_icon_url

  def initialize
    @name = nil
    @token = nil
    @token_expires = nil
    @profile_icon_url = nil
    @expiration_timeout = nil
    @listeners = []
  end

  # Registers a block called whenever name/token/icon/authenticated changes.
  def on_change(&block)
    @listeners << block
  end

  def authenticated? = !@token.nil? && !@token.empty?

  def set_authenticated(name:, token:, token_expires: nil, profile_icon_url: nil)
    was_authenticated = authenticated?

    @name = name
    @token = token
    @token_expires = token_expires
    @profile_icon_url = profile_icon_url

    schedule_token_expiration
    notify_listeners unless was_authenticated == authenticated?
    notify_listeners
  end

  def clear
    cancel_expiration_timeout
    set_authenticated(name: nil, token: nil, token_expires: nil, profile_icon_url: nil)
  end

  private

  def cancel_expiration_timeout
    GLib::Source.remove(@expiration_timeout) if @expiration_timeout
    @expiration_timeout = nil
  end

  def schedule_token_expiration
    cancel_expiration_timeout
    return unless @token_expires

    seconds_until_expiration = (@token_expires - Time.now).to_i
    return clear if seconds_until_expiration <= 0

    @expiration_timeout = GLib::Timeout.add_seconds(seconds_until_expiration) do
      @expiration_timeout = nil
      clear
      GLib::Source::REMOVE
    end
  end

  def notify_listeners
    @listeners.each(&:call)
  end
end
