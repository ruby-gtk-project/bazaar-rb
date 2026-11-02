# frozen_string_literal: true

require "adwaita"

# ListTile is the base of every clickable tile in the app: a card that
# highlights on hover, takes keyboard focus and reports activation.
#
# Ported from upstream's src/bz-list-tile.c, which is a GtkWidget with a bin
# layout, the "card" and "activatable" style classes, a click gesture and
# shortcuts on Space / Return / Enter.
#
# The port composes rather than subclasses: `build` returns the card and the
# subclass supplies `child`. Upstream's activation shortcuts are bound with
# a key controller here, since Gtk::SignalAction has no Ruby constructor that
# takes a signal name.
class ListTile
  ACTIVATE_KEYS = [
    Gdk::Keyval::KEY_space,
    Gdk::Keyval::KEY_KP_Space,
    Gdk::Keyval::KEY_Return,
    Gdk::Keyval::KEY_ISO_Enter,
    Gdk::Keyval::KEY_KP_Enter,
  ].freeze

  def initialize(on_activated: nil)
    @on_activated = on_activated
  end

  def build
    root.tap do |tile|
      tile.child = child

      tile.add_controller(click_gesture)
      tile.add_controller(key_controller)

      click_gesture.signal_connect("released") do |gesture, _n_press, x, y|
        case tile.contains?(x, y)
        when true
          gesture.set_state(:claimed)
          activate
        else gesture.set_state(:denied)
        end
      end

      key_controller.signal_connect("key-pressed") do |_controller, keyval, _code, _state|
        case ACTIVATE_KEYS.include?(keyval)
        when true
          activate
          true
        else false
        end
      end
    end
  end

  # The widget the card wraps. Subclasses override this.
  def child = @child ||= Gtk::Box.new(:horizontal, 0)

  def activate
    @on_activated&.call(self)
  end

  def root
    @root ||= Adwaita::Bin.new.tap do |bin|
      bin.add_css_class("card")
      bin.add_css_class("activatable")
      bin.focusable = true
      bin.receives_default = true
    end
  end

  def click_gesture = @click_gesture ||= Gtk::GestureClick.new
  def key_controller = @key_controller ||= Gtk::EventControllerKey.new
end
