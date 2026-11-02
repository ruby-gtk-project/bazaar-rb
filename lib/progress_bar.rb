# frozen_string_literal: true

require "adwaita"

# ProgressBar is a GtkProgressBar that springs forward to each new value
# instead of jumping.
#
# Ported from upstream's src/bz-progress-bar.c and src/bz-progress-bar.blp,
# including the spring parameters (damping 1.0, mass 0.5, stiffness 200) and
# the epsilon, and the rule that only forward movement is animated: a value
# that goes backwards — a new op starting — snaps.
#
# The pride themes upstream draws with
# src/progress-bar-designs/pride/pride.c are not drawn here; the themed
# variants are the style classes of the same name in lib/style.css, which the
# preferences dialog sets on the global bar.
class ProgressBar
  EPSILON = 0.00025

  def initialize(fraction: 0.0)
    @fraction = fraction
  end

  attr_reader :fraction

  def build
    bar.tap do
      animation
      self.fraction = @fraction
    end
  end

  def fraction=(value)
    last = @fraction
    @fraction = value.clamp(0.0, 1.0)
    current = bar.fraction

    case @fraction < last || (last - @fraction).abs < 0.001
    when true
      animation.reset
      bar.fraction = @fraction
    else
      animation.value_from = current
      animation.value_to = @fraction
      animation.initial_velocity = animation.velocity
      animation.play
    end
    @fraction
  end

  def bar = @bar ||= Gtk::ProgressBar.new

  def animation
    @animation ||= Adwaita::SpringAnimation.new(
      bar,
      0.0,
      0.0,
      Adwaita::SpringParams.new(1.0, 0.5, 200.0),
      Adwaita::PropertyAnimationTarget.new(bar, "fraction"),
    ).tap do |spring|
      spring.epsilon = EPSILON
    end
  end
end
