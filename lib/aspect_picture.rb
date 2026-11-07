# frozen_string_literal: true

require "adwaita"

# AspectPicture shows a paintable cropped to fill a box, optionally forcing
# a fixed aspect ratio instead of the paintable's own.
#
# Ported from upstream's src/bz-aspect-picture.c, a GtkWidget subclass that
# overrides measure/snapshot: with no ratio set it sizes height-for-width
# from the paintable's intrinsic aspect (falling back to a square), and it
# always draws the paintable scaled up to cover the whole allocation
# (`scale = MAX(scale_x, scale_y)`), centered and clipped to the widget's
# bounds. There is no Ruby binding for overriding `GtkWidget#measure` and
# `#snapshot` on a custom subclass, so this port reaches the same picture
# with stock widgets instead: a `Gtk::Picture` in `content_fit: :cover`
# mode reproduces the cropped-to-fill draw exactly, and a `Gtk::AspectFrame`
# around it reproduces the forced-ratio sizing. When no ratio is set the
# frame's ratio tracks the paintable's own intrinsic aspect, which is what
# upstream's `ratio == 0` branch does.
class AspectPicture
  DEFAULT_RATIO = 1.0

  def initialize(paintable: nil, ratio: 0.0)
    @paintable = paintable
    @ratio = ratio
  end

  attr_reader :paintable, :ratio

  def build
    frame.tap do |f|
      f.child = picture
    end
  end

  def paintable=(value)
    @paintable = value
    picture.paintable = value
    frame.ratio = effective_ratio
    value
  end

  def ratio=(value)
    @ratio = value
    frame.ratio = effective_ratio
    value
  end

  def frame
    @frame ||= Gtk::AspectFrame.new(0.5, 0.5, effective_ratio, false).tap do |f|
      f.obey_child = false
    end
  end

  def picture
    @picture ||= Gtk::Picture.new.tap do |pic|
      pic.content_fit = :cover
      pic.can_shrink = true
      pic.paintable = @paintable
    end
  end

  private

  def effective_ratio
    return @ratio if @ratio&.positive?

    @paintable.then do |paintable|
      next DEFAULT_RATIO unless paintable

      width = paintable.intrinsic_width
      height = paintable.intrinsic_height
      (width.positive? && height.positive?) ? width.to_f / height : DEFAULT_RATIO
    end
  end
end
