# frozen_string_literal: true

require "adwaita"
require_relative "library_page"
require_relative "template_callbacks"
require_relative "transaction"

# Window is Bazaar's main window: the view switcher, the main menu, the
# banners, the toasts, and the navigation view every pushed page lands in.
#
# Ported from upstream's src/bz-window.blp and src/bz-window.c — the
# loading / main stack, the toolbar view with the view switcher in the header
# and a view-switcher bar at the bottom, the breakpoint at 700px that moves
# the switcher down, the three banners (the donation prompt, the
# "viewing a cached Flathub" warning and the metered-connection warning),
# the Escape / Back / BackSpace / Ctrl+G shortcuts that pop a page, and the
# primary, account and debug menus.
#
# The window's own actions are installed on it as a Gio::SimpleActionGroup
# under the "window" prefix, which is what the menu items and the tiles
# address ("window.open-library" and friends).
#
# Three of upstream's view-stack pages — Curated, Explore and Search — and
# the pages the remaining actions push (the full view, the add-ons dialog,
# the leftover-user-data page) belong to components that are not ported yet,
# so this window carries the Library page and the actions that drive it.
class Window
  DEFAULT_WIDTH = 1220
  DEFAULT_HEIGHT = 900
  MIN_WIDTH = 360
  MIN_HEIGHT = 294

  attr_reader :state

  def initialize(application:, state:, on_update: nil, on_search: nil, on_sync: nil)
    @application = application
    @state = state
    @on_update = on_update
    @on_search = on_search
    @on_sync = on_sync
  end

  def build
    window.tap do |win|
      win.content = window_overlay
      win.insert_action_group("window", action_group)
      win.add_controller(escape_controller)

      window_overlay.child = outer_toolbar_view
      outer_toolbar_view.content = breakpoint_bin
      breakpoint_bin.child = toasts
      breakpoint_bin.add_breakpoint(narrow_breakpoint)
      narrow_breakpoint.signal_connect("apply") { header_bar.title_widget = nil }
      narrow_breakpoint.signal_connect("unapply") { header_bar.title_widget = title_box }
      toasts.child = navigation_view
      navigation_view.add(main_page)

      toolbar_view.tap do |view|
        view.add_top_bar(top_box)
        view.add_bottom_bar(switcher_bar)
        view.content = main_stack
      end

      top_box.tap do |box|
        box.append(header_bar)
        box.append(donations_banner)
        box.append(cached_banner)
        box.append(metered_banner)
      end

      header_bar.tap do |bar|
        bar.pack_start(debug_box)
        bar.pack_end(primary_menu_button)
        bar.title_widget = title_box
      end

      main_stack.tap do |stack|
        stack.add_named(loading_box, "loading")
        stack.add_named(view_stack, "main")
      end

      view_stack.add_titled_with_icon(
        library_page.build,
        "installed",
        "Library",
        "library-symbolic",
      )

      wire_state
      refresh
    end
  end

  def present
    window.present
  end

  # Upstream's bz_window_add_toast.
  def add_toast(toast)
    toasts.add_toast(toast)
  end

  # Upstream's bz_window_push_page.
  def push_page(page)
    navigation_view.push(page)
  end

  # Upstream's bz_window_search: show the search page seeded with the text.
  # The port has the library page's own search box, which is what Ctrl+F
  # reaches until the search page is ported.
  def search(text)
    view_stack.visible_child_name = "installed"
    library_page.ensure_active(text.to_s)
  end

  def refresh
    # The navigation view notifies its visible page while the window is still
    # being assembled, so the stack may not have its children yet.
    main_stack.get_child_by_name(busy_page).then do |child|
      case child
      when nil then nil
      else main_stack.visible_child_name = busy_page
      end
    end
    donations_banner.revealed = !@state.donation_prompt_dismissed?
    cached_banner.revealed = cached?
    cached_banner.sensitive = !@state.syncing?
    metered_banner.revealed = metered?
    metered_banner.sensitive = !@state.syncing?
    debug_box.visible = @state.debug_mode?
    switcher.visible = !@state.busy?
    switcher_bar.visible = !@state.busy?
    busy_title.visible = @state.busy?
    loading_box.tooltip_text = @state.background_task_label.to_s
    window.title = TemplateCallbacks.format_title(navigation_view.visible_page&.title)
  end

  def window
    @window ||= Adwaita::ApplicationWindow.new(@application).tap do |win|
      win.set_default_size(DEFAULT_WIDTH, DEFAULT_HEIGHT)
      win.width_request = MIN_WIDTH
      win.height_request = MIN_HEIGHT
    end
  end

  def library_page
    @library_page ||= LibraryPage.new(
      state:            @state,
      on_update:        ->(entries) { @on_update&.call(entries) },
      on_global_search: ->(text) { @on_search&.call(text) },
      on_remove:        ->(group) { remove_group(group) },
      on_launch:        ->(group) { launch_group(group) },
    )
  end

  def window_overlay = @window_overlay ||= Gtk::Overlay.new
  def outer_toolbar_view = @outer_toolbar_view ||= Adwaita::ToolbarView.new

  def breakpoint_bin
    @breakpoint_bin ||= Adwaita::BreakpointBin.new.tap do |bin|
      bin.width_request = MIN_WIDTH
      bin.height_request = 450
    end
  end

  # Upstream's breakpoint drops the header's title widget and reveals the
  # bottom bar below 700px. The bottom bar is a plain setter; the title
  # widget is cleared from the breakpoint's apply / unapply handlers, because
  # adw_breakpoint_add_setter refuses a NULL value through the bindings.
  def narrow_breakpoint
    @narrow_breakpoint ||= Adwaita::Breakpoint.new(
      Adwaita::BreakpointCondition.parse("max-width: 700px"),
    ).tap do |breakpoint|
      breakpoint.add_setter(toolbar_view, "reveal-bottom-bars", true)
    end
  end

  def toasts = @toasts ||= Adwaita::ToastOverlay.new

  def navigation_view
    @navigation_view ||= Adwaita::NavigationView.new.tap do |view|
      view.pop_on_escape = false
      view.signal_connect("notify::visible-page") { refresh }
    end
  end

  def main_page
    @main_page ||= Adwaita::NavigationPage.new(toolbar_view, "Bazaar").tap do |page|
      page.tag = "main"
    end
  end

  def toolbar_view
    @toolbar_view ||= Adwaita::ToolbarView.new.tap do |view|
      view.top_bar_style = :flat
      view.bottom_bar_style = :flat
      view.reveal_bottom_bars = false
    end
  end

  def main_stack = @main_stack ||= Gtk::Stack.new

  def loading_box
    @loading_box ||= Gtk::Box.new(:vertical, 6).tap do |box|
      box.halign = :fill
      box.valign = :center
      box.append(
        Adwaita::Spinner.new.tap do |spinner|
          spinner.width_request = 64
          spinner.height_request = 64
          spinner.margin_bottom = 18
        end,
      )
      box.append(
        Gtk::Label.new("Refreshing").tap do |label|
          label.wrap = true
          label.justify = :center
          label.margin_bottom = 24
          label.add_css_class("title-3")
        end,
      )
    end
  end

  def view_stack = @view_stack ||= Adwaita::ViewStack.new

  def top_box = @top_box ||= Gtk::Box.new(:vertical, 0)

  def header_bar = @header_bar ||= Adwaita::HeaderBar.new

  def debug_box
    @debug_box ||= Gtk::Box.new(:horizontal, 6).tap do |box|
      box.add_css_class("bz-debug")
      box.append(
        Gtk::Button.new.tap do |button|
          button.has_tooltip = true
          button.tooltip_text = "Open Bazaar Inspector"
          button.icon_name = "bug-symbolic"
          button.action_name = "app.bazaar-inspector"
        end,
      )
    end
  end

  def title_box
    @title_box ||= Gtk::Box.new(:horizontal, 0).tap do |box|
      box.append(switcher)
      box.append(busy_title)
    end
  end

  def switcher
    @switcher ||= Adwaita::ViewSwitcher.new.tap do |widget|
      widget.stack = view_stack
      widget.policy = :wide
    end
  end

  def busy_title
    @busy_title ||= Gtk::Label.new("Bazaar").tap do |label|
      label.add_css_class("title")
    end
  end

  def switcher_bar
    @switcher_bar ||= Adwaita::ViewSwitcherBar.new.tap do |bar|
      bar.stack = view_stack
      bar.reveal = true
    end
  end

  def primary_menu_button
    @primary_menu_button ||= Gtk::MenuButton.new.tap do |button|
      button.primary = true
      button.icon_name = "open-menu-symbolic"
      button.has_tooltip = true
      button.tooltip_text = "Main Menu"
      button.menu_model = primary_menu
    end
  end

  # Ported from the `menu primary_menu` block of src/bz-window.blp.
  def primary_menu
    @primary_menu ||= Gio::Menu.new.tap do |menu|
      menu.append_section(nil, section("_Donate to Bazaar" => "app.donate"))
      menu.append_section(
        nil,
        section(
          "_Refresh"                   => "app.sync-remotes",
          "_Login With Flathub"        => "app.flathub-login",
          "_Manage Leftover User Data" => "window.user-data",
        ),
      )
      menu.append_section(
        nil,
        section(
          "_Preferences"        => "app.preferences",
          "_Keyboard Shortcuts" => "app.shortcuts",
          "_About Bazaar"       => "app.about",
        ),
      )
      menu.append_section(nil, section("_Quit Bazaar" => "app.quit"))
    end
  end

  # Ported from the `menu account_menu` block of src/bz-window.blp.
  def account_menu
    @account_menu ||= Gio::Menu.new.tap do |menu|
      menu.append_section(nil, section("Favorites" => "app.flathub-favorites"))
      menu.append_section(nil, section("Log Out" => "app.flathub-logout"))
    end
  end

  # Ported from the `menu debug_menu` block of src/bz-window.blp.
  def debug_menu
    @debug_menu ||= Gio::Menu.new.tap do |menu|
      menu.append_section(nil, section("Open Bazaar Inspector" => "app.bazaar-inspector"))
    end
  end

  def donations_banner
    @donations_banner ||= Adwaita::Banner.new("You are running a new version of Bazaar!").tap do |banner|
      banner.add_css_class("bz-donations-banner")
      banner.button_label = "See What's New"
      banner.action_name = "app.donate"
    end
  end

  def cached_banner
    @cached_banner ||= Adwaita::Banner.new(
      "You have a network connection but are viewing a cached version of Flathub",
    ).tap do |banner|
      banner.button_label = "Refresh Manually"
      banner.signal_connect("button-clicked") { @on_sync&.call }
    end
  end

  def metered_banner
    @metered_banner ||= Adwaita::Banner.new(
      "Network connection is metered — automatic refreshes disabled",
    ).tap do |banner|
      banner.button_label = "Refresh Manually"
      banner.signal_connect("button-clicked") { @on_sync&.call }
    end
  end

  # Escape, Back, BackSpace and Ctrl+G all pop the navigation view, which is
  # the ShortcutController in the template.
  def escape_controller
    @escape_controller ||= Gtk::EventControllerKey.new.tap do |controller|
      controller.signal_connect("key-pressed") do |_c, keyval, _code, modifiers|
        escape_pressed?(keyval, modifiers).then do |matched|
          case matched
          when true
            navigation_view.pop
            true
          else false
          end
        end
      end
    end
  end

  def action_group
    @action_group ||= Gio::SimpleActionGroup.new.tap do |group|
      group.add_action(simple_action("open-library") { view_stack.visible_child_name = "installed" })
      group.add_action(simple_action("quit") { window.close })
      group.add_action(string_action("show-group") { |id| show_group(id) })
      group.add_action(string_action("install-group") { |id| install_group(id) })
      group.add_action(string_action("remove-group") { |id| remove_group_by_id(id) })
      group.add_action(string_action("cancel-group") { |id| cancel_group(id) })
      group.add_action(string_action("launch-group") { |id| launch_group_by_id(id) })
    end
  end

  private

    def section(items)
      Gio::Menu.new.tap do |menu|
        items.each { |label, action| menu.append(label, action) }
      end
    end

    def simple_action(name, &block)
      Gio::SimpleAction.new(name).tap do |action|
        action.signal_connect("activate") { block.call }
      end
    end

    def string_action(name, &block)
      Gio::SimpleAction.new(name, GLib::VariantType.new("s")).tap do |action|
        action.signal_connect("activate") { |_action, parameter| block.call(parameter.get_string) }
      end
    end

    def escape_pressed?(keyval, modifiers)
      [
        Gdk::Keyval::KEY_Escape,
        Gdk::Keyval::KEY_Back,
        Gdk::Keyval::KEY_BackSpace,
      ].include?(keyval) ||
        (keyval == Gdk::Keyval::KEY_g && modifiers.control_mask?)
    end

    def busy_page
      case @state.busy?
      when true then "loading"
      else "main"
      end
    end

    # Upstream reveals this banner when there is a connection but Flathub
    # itself could not be reached, so what is on screen came from the cache.
    def cached?
      !@state.metered_connection? && @state.have_connection? && !@state.online?
    end

    def metered?
      !@state.recently_synced? && @state.metered_connection? && @state.have_connection?
    end

    def wire_state
      @state.on_change { refresh }
      @state.transaction_manager&.on_change { refresh }
    end

    def group_for(id) = @state.application_factory&.convert_one(id)

    def show_group(id)
      group_for(id).then do |group|
        case group
        when nil then nil
        else library_page.ensure_active(group.title.to_s)
        end
      end
    end

    def install_group(id)
      group_for(id).then { |group| schedule(installs: entries_of(group)) }
    end

    def remove_group_by_id(id) = remove_group(group_for(id))

    def remove_group(group)
      schedule(removals: entries_of(group))
    end

    def cancel_group(id)
      group_for(id).then do |group|
        entries_of(group).each { |entry| @state.backend&.cancel_task_for_entry(entry) }
      end
    end

    def launch_group_by_id(id) = launch_group(group_for(id))

    # Upstream launches the app through its desktop file; the port asks
    # flatpak to run the ref, which is what that desktop file does.
    def launch_group(group)
      entries_of(group).first.then do |entry|
        case entry
        when nil then nil
        else spawn_launch(entry)
        end
      end
    end

    def spawn_launch(entry)
      entry.unique_id.to_s.split("::", 3)[2].to_s.split("/")[1].then do |app_id|
        case app_id.to_s.empty?
        when true then nil
        else Process.spawn(
          "flatpak",
          "run",
          app_id,
          out: File::NULL,
          err: File::NULL,
        )
        end
      end
    rescue Errno::ENOENT
      add_toast(Adwaita::Toast.new("Could not launch #{entry.title}"))
    end

    def entries_of(group)
      case group
      when nil then []
      else Array(group.model)
      end
    end

    def schedule(installs: [], updates: [], removals: [])
      case installs.empty? && updates.empty? && removals.empty?
      when true then nil
      else
        @state.transaction_manager&.add(
          Transaction.new(installs: installs, updates: updates, removals: removals),
        )
      end
    end
end
