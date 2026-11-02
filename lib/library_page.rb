# frozen_string_literal: true

require "adwaita"
require_relative "search_bar"
require_relative "installed_tile"
require_relative "transaction_tile"
require_relative "updates_card"
require_relative "template_callbacks"

# LibraryPage is the "Library" tab: the installed apps, the updates waiting,
# the downloads and removals in flight, and a search box over the lot.
#
# Ported from upstream's src/bz-library-page.blp and src/bz-library-page.c.
# The three pages of its view stack ("empty", "no-results", "content"), the
# filter that matches the search text against an app's id and title, the
# sort popover's name-or-size choice, the four revealers (pending updates,
# downloads, recently uninstalled, clear-finished) and the installed count
# heading are all upstream's.
class LibraryPage
  def initialize(state:, on_update: nil, on_show_group: nil, on_global_search: nil,
                 on_remove: nil, on_addons: nil, on_launch: nil)
    @state = state
    @on_update = on_update
    @on_show_group = on_show_group
    @on_global_search = on_global_search
    @on_remove = on_remove
    @on_addons = on_addons
    @on_launch = on_launch
    @sort_by_size = false
  end

  def build
    root.tap do |bin|
      bin.child = box

      box.tap do |outer|
        outer.append(search_clamp)
        outer.append(stack)

        search_clamp.child = search_bar.build

        stack.tap do |view|
          view.add_named(empty_page, "empty")
          view.add_named(no_results_page, "no-results")
          view.add_named(scroller, "content")
        end
      end

      scroller.child = content_clamp
      content_clamp.child = content_box

      content_box.tap do |content|
        content.append(non_search_content)
        content.append(installed_list)
      end

      wire_signals
      refresh
    end
  end

  # Upstream's bz_library_page_ensure_active: the search box takes focus and
  # the initial text, unless the user is already typing in it.
  def ensure_active(initial)
    case !search_bar.text_value.empty? && search_bar.text.has_focus?
    when true then false
    else
      search_bar.seed(initial)
      true
    end
  end

  # Upstream's bz_library_page_reset_search.
  def reset_search
    scroller.vadjustment.value = 0.0
    search_bar.text_value = ""
  end

  def has_apps? = !groups.empty?

  def refresh
    rebuild_installed
    rebuild_trackers
    search_clamp.visible = has_apps?
    installed_list.visible = has_apps?
    count_label.label = TemplateCallbacks.format_install_count(filtered_groups.length)
    non_search_content.visible = search_bar.text_value.empty?
    refresh_revealers
    set_page
  end

  def root = @root ||= Adwaita::Bin.new
  def box = @box ||= Gtk::Box.new(:vertical, 0)

  def search_clamp
    @search_clamp ||= Adwaita::Clamp.new.tap do |clamp|
      clamp.margin_start = 12
      clamp.margin_end = 12
      clamp.margin_top = 10
      clamp.margin_bottom = 10
      clamp.maximum_size = 375
    end
  end

  def search_bar
    @search_bar ||= SearchBar.new(
      placeholder:  "Search installed apps",
      on_changed:   ->(_bar) { refresh },
      on_activated: ->(_bar) { activate_search },
    )
  end

  def stack
    @stack ||= Adwaita::ViewStack.new.tap do |view|
      view.enable_transitions = true
      view.transition_duration = 400
    end
  end

  def empty_page
    @empty_page ||= Adwaita::StatusPage.new.tap do |page|
      page.icon_name = "library-symbolic"
      page.title = "No Apps Found"
      page.description = ""
    end
  end

  def no_results_page
    @no_results_page ||= Adwaita::StatusPage.new.tap do |page|
      page.icon_name = "library-symbolic"
      page.child = global_search_button
    end
  end

  def global_search_button
    @global_search_button ||= Gtk::Button.new(label: "Search Store Instead").tap do |button|
      button.add_css_class("pill")
      button.halign = :center
    end
  end

  def scroller
    @scroller ||= Gtk::ScrolledWindow.new.tap do |window|
      window.hscrollbar_policy = :never
    end
  end

  def content_clamp
    @content_clamp ||= Adwaita::Clamp.new.tap do |clamp|
      clamp.vexpand = true
      clamp.maximum_size = 650
    end
  end

  def content_box
    @content_box ||= Gtk::Box.new(:vertical, 0).tap do |inner|
      inner.margin_start = 9
      inner.margin_end = 9
      inner.margin_bottom = 30
    end
  end

  def non_search_content
    @non_search_content ||= Gtk::Box.new(:vertical, 0).tap do |inner|
      inner.append(updates_revealer)
      inner.append(install_revealer)
      inner.append(removal_revealer)
      inner.append(clear_revealer)
      inner.append(count_box)
    end
  end

  def updates_revealer
    @updates_revealer ||= Gtk::Revealer.new.tap do |revealer|
      revealer.transition_type = :slide_down
      revealer.child = updates_box
    end
  end

  def updates_box
    @updates_box ||= Gtk::Box.new(:vertical, 8).tap do |inner|
      inner.margin_top = 15
      inner.append(heading("Pending Updates", margin_top: 15))
      inner.append(updates_card.build)
    end
  end

  def updates_card
    @updates_card ||= UpdatesCard.new(
      state:     @state,
      on_update: ->(entries) { @on_update&.call(entries) },
    )
  end

  def install_revealer
    @install_revealer ||= Gtk::Revealer.new.tap do |revealer|
      revealer.transition_type = :slide_down
      revealer.child = install_box
    end
  end

  def install_box
    @install_box ||= Gtk::Box.new(:vertical, 0).tap do |inner|
      inner.margin_top = 15
      inner.append(heading("Downloads"))
      inner.append(install_list)
    end
  end

  def install_list = @install_list ||= tracker_list

  def removal_revealer
    @removal_revealer ||= Gtk::Revealer.new.tap do |revealer|
      revealer.transition_type = :slide_down
      revealer.child = removal_box
    end
  end

  def removal_box
    @removal_box ||= Gtk::Box.new(:vertical, 0).tap do |inner|
      inner.margin_top = 15
      inner.append(heading("Recently Uninstalled"))
      inner.append(removal_list)
    end
  end

  def removal_list = @removal_list ||= tracker_list

  def clear_revealer
    @clear_revealer ||= Gtk::Revealer.new.tap do |revealer|
      revealer.transition_type = :slide_down
      revealer.margin_bottom = 15
      revealer.child = clear_list
    end
  end

  def clear_list
    @clear_list ||= Gtk::ListBox.new.tap do |list|
      list.margin_bottom = 16
      list.margin_top = 4
      list.margin_start = 4
      list.margin_end = 4
      list.selection_mode = :none
      list.add_css_class("boxed-list")
      list.append(clear_row)
    end
  end

  def clear_row
    @clear_row ||= Adwaita::ButtonRow.new.tap do |row|
      row.title = "Clear Finished Tasks"
      row.add_css_class("error")
    end
  end

  def count_box
    @count_box ||= Gtk::Box.new(:horizontal, 0).tap do |inner|
      inner.margin_start = 12
      inner.margin_end = 4
      inner.append(count_label)
      inner.append(sort_button)
    end
  end

  def count_label
    @count_label ||= Gtk::Label.new.tap do |label|
      label.xalign = 0
      label.hexpand = true
      label.margin_top = 4
      label.add_css_class("heading")
      label.add_css_class("h4")
    end
  end

  def sort_button
    @sort_button ||= Gtk::MenuButton.new.tap do |button|
      button.icon_name = "sliders-horizontal-symbolic"
      button.tooltip_text = "Sort Options"
      button.add_css_class("flat")
      button.popover = sort_popover
    end
  end

  def sort_popover
    @sort_popover ||= Gtk::Popover.new.tap do |popover|
      popover.child = Gtk::Box.new(:vertical, 6).tap do |inner|
        inner.margin_top = 8
        inner.margin_bottom = 8
        inner.margin_start = 8
        inner.margin_end = 16
        inner.append(
          Gtk::Label.new("Sort By").tap do |label|
            label.wrap = true
            label.wrap_mode = :word_char
            label.xalign = 0
            label.margin_start = 28
            ["heading", "h4", "dimmed"].each { |css| label.add_css_class(css) }
          end,
        )
        inner.append(sort_name)
        inner.append(sort_size)
      end
    end
  end

  def sort_name
    @sort_name ||= Gtk::CheckButton.new("Name").tap do |check|
      check.active = true
    end
  end

  def sort_size
    @sort_size ||= Gtk::CheckButton.new("Size").tap do |check|
      check.group = sort_name
    end
  end

  def installed_list
    @installed_list ||= Gtk::Box.new(:vertical, 0).tap do |list|
      ["navigation-sidebar", "installed-list-view", "installed-section"].each do |css|
        list.add_css_class(css)
      end
    end
  end

  private

    def tracker_list
      Gtk::Box.new(:vertical, 0).tap do |list|
        list.add_css_class("navigation-sidebar")
        list.add_css_class("installed-list-view")
      end
    end

    def heading(text, margin_top: 0)
      Gtk::Label.new(text).tap do |label|
        label.xalign = 0
        label.margin_start = 12
        label.margin_top = margin_top
        label.add_css_class("heading")
        label.add_css_class("h4")
      end
    end

    def wire_signals
      global_search_button.signal_connect("clicked") { activate_search }
      clear_row.signal_connect("activated") { clear_tasks }
      sort_name.signal_connect("toggled") { apply_sort }
      sort_size.signal_connect("toggled") { apply_sort }
      @state.on_change(:all_installed_entry_groups, :available_updates) { refresh }
      transactions&.on_change { refresh }
    end

    def transactions = @state.transaction_manager

    def groups = Array(@state.all_installed_entry_groups)

    # Upstream's filter: add-ons never show, and with search text an app
    # matches on its id or its title, case-insensitively.
    def filtered_groups
      text = search_bar.text_value.downcase
      sorted(groups.reject(&:addon?)).select do |group|
        case text.empty?
        when true then true
        else
          group.id.to_s.downcase.include?(text) || group.title.to_s.downcase.include?(text)
        end
      end
    end

    # Upstream's sort_func: by installed size, largest first, when the size
    # radio is picked, and by title otherwise.
    def sorted(list)
      case @sort_by_size
      when true then list.sort_by { |group| -group.installed_size.to_i }
      else list.sort_by { |group| group.title.to_s }
      end
    end

    def apply_sort
      @sort_by_size = sort_size.active?
      refresh
    end

    def rebuild_installed
      installed_list.tap do |list|
        while list.first_child
          list.remove(list.first_child)
        end

        filtered_groups.each do |group|
          list.append(
            InstalledTile.new(
              group:        group,
              on_activated: ->(tile) { @on_show_group&.call(tile.group) },
              on_remove:    ->(removed) { @on_remove&.call(removed) },
              on_addons:    ->(addons) { @on_addons&.call(addons) },
            ).build,
          )
        end
      end
    end

    def rebuild_trackers
      fill_tracker_list(install_list, transactions&.install_trackers)
      fill_tracker_list(removal_list, transactions&.removal_trackers)
    end

    def fill_tracker_list(list, trackers)
      while list.first_child
        list.remove(list.first_child)
      end

      Array(trackers).each do |tracker|
        list.append(
          TransactionTile.new(
            tracker:      tracker,
            on_activated: ->(_tile) { @on_show_group&.call(group_for(tracker)) },
            on_cancel:    ->(_tracker) { transactions&.cancel_current },
            on_run:       ->(finished) { @on_launch&.call(group_for(finished)) },
          ).build,
        )
      end
    end

    def group_for(tracker)
      @state.application_factory&.convert_one(tracker.entry.id)
    end

    def refresh_revealers
      updates_revealer.reveal_child = !Array(@state.available_updates).empty?
      install_revealer.reveal_child = !Array(transactions&.install_trackers).empty?
      removal_revealer.reveal_child = !Array(transactions&.removal_trackers).empty?
      clear_revealer.reveal_child = transactions&.has_transactions? == true
    end

    def activate_search
      search_bar.text_value.then do |text|
        case text.empty?
        when false then @on_global_search&.call(text)
        end
      end
      search_bar.text_value = ""
    end

    def clear_tasks
      transactions&.clear_finished
      refresh
    end

    # Ported from set_page: nothing installed and nothing running shows the
    # empty page, a search that matches nothing shows the no-results page,
    # and otherwise the content.
    def set_page
      n_apps = groups.length
      n_filtered = filtered_groups.length
      has_transactions = transactions&.has_transactions? == true

      case
      when n_apps.zero? && !has_transactions
        search_bar.text_value = ""
        stack.visible_child_name = "empty"
      when n_apps.positive? && n_filtered.zero?
        no_results_page.description = TemplateCallbacks.no_results_found_subtitle(
          search_bar.text_value,
        )
        stack.visible_child_name = "no-results"
      else stack.visible_child_name = "content"
      end
    end
end
