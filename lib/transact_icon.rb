# frozen_string_literal: true

require "adwaita"

# TransactIcon is an app icon with a progress ring around it.
#
# Ported from upstream's src/bz-transact-icon.c and
# src/bz-transact-icon.wdgt. The .wdgt spec draws the icon, then strokes the
# segment of a circle from `start` to `end` around it, rotated so the ring
# grows clockwise from the top; the port draws the same ring with Cairo in a
# GtkDrawingArea overlaid on the icon, because the .wdgt rendering engine
# (bge/) is not part of this port.
#
# The icon is shown at its natural size and the ring appears only while the
# tracker is active, which is upstream's behaviour — the icon's slight
# scale-down during a transaction is the one visual detail left out.
class TransactIcon
  RING_WIDTH = 4.0
  FALLBACK_ICON = "application-x-executable"

  attr_reader :size

  def initialize(paintable: nil, tracker: nil, size: 64)
    @paintable = paintable
    @tracker = tracker
    @size = size
  end

  def build
    overlay.tap do |root|
      root.child = icon
      root.add_overlay(ring)

      ring.set_draw_func { |_area, cairo, width, height| draw_ring(cairo, width, height) }

      @tracker&.on_change { refresh }
      refresh
    end
  end

  def tracker=(tracker)
    @tracker = tracker
    @tracker&.on_change { refresh }
    refresh
  end

  def paintable=(paintable)
    @paintable = paintable
    apply_paintable
  end

  def refresh
    ring.visible = active?
    ring.queue_draw
  end

  def overlay = @overlay ||= Gtk::Overlay.new

  def icon
    @icon ||= Gtk::Image.new.tap do |image|
      image.icon_name = FALLBACK_ICON
      image.pixel_size = @size
      image.add_css_class("icon-dropshadow")
      apply_paintable
    end
  end

  def ring
    @ring ||= Gtk::DrawingArea.new.tap do |area|
      area.content_width = @size
      area.content_height = @size
      area.can_target = false
      area.add_css_class("transact-icon-flag")
    end
  end

  private

    def apply_paintable
      case @paintable
      when nil then @icon&.icon_name = FALLBACK_ICON
      else @icon&.paintable = @paintable
      end
    end

    def active? = @tracker&.active? == true

    def progress = @tracker&.progress.to_f.clamp(0.0, 1.0)

    # The ring starts at the top and sweeps clockwise, which is the -90°
    # rotation the .wdgt spec applies before stroking the segment.
    def draw_ring(cairo, width, height)
      radius = ([width, height].min / 2.0) - (RING_WIDTH / 2.0)
      case radius <= 0 || !active?
      when true then nil
      else
        cairo.set_line_width(RING_WIDTH)
        cairo.set_line_cap(:round)
        cairo.set_source_rgba(
          0.21,
          0.52,
          0.89,
          0.9,
        )
        cairo.arc(
          width / 2.0,
          height / 2.0,
          radius,
          -Math::PI / 2,
          (-Math::PI / 2) + (2 * Math::PI * progress),
        )
        cairo.stroke
      end
    end
end
