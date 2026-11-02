# frozen_string_literal: true

require "adwaita"

# ShortcutsDialog lists Bazaar's keyboard shortcuts.
#
# A direct port of upstream's src/shortcuts-dialog.blp: three sections —
# Navigation, Remotes and General — with the same items, action names and
# accelerators. An item upstream gives no accelerator (because the
# accelerator lives on the application action) is listed with the accelerator
# the application binds to that action.
class ShortcutsDialog < Adwaita::ShortcutsDialog
  SECTIONS = {
    "Navigation" => [
      ["Open Explore Page", "<Control>e"],
      ["Open Library Page", "<Control>d"],
      ["Open Search Page", "<Control>f"],
    ],
    "Remotes"    => [
      ["Sync Remotes", "<Control>r"],
    ],
    "General"    => [
      ["Open Preferences", "<Control>comma"],
      ["Show Shortcuts", "<Control>question"],
      ["Close Window", "<Control>w"],
      ["Quit Bazaar", "<Control>q"],
    ],
  }.freeze

  def initialize
    super()
    self.title = "Keyboard Shortcuts"
  end

  def build
    tap do |dialog|
      SECTIONS.each { |title, items| dialog.add(section(title, items)) }
    end
  end

  private

    def section(title, items)
      Adwaita::ShortcutsSection.new.tap do |section|
        section.title = title
        items.each { |label, accelerator| section.add(item(label, accelerator)) }
      end
    end

    # Positional, not keyword, arguments — even though the error a no-argument
    # new raises advertises the signatures as "title: utf8, accelerator: utf8".
    def item(label, accelerator) = Adwaita::ShortcutsItem.new(label, accelerator)
end
