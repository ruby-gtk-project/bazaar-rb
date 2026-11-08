# frozen_string_literal: true

require "adwaita"
require_relative "entry_selection_row"
require_relative "transaction_list_dialog"

# TransactionDialog confirms an install or a removal before Window hands it
# to the transaction manager: which remote's copy to use when an app's
# group holds more than one candidate entry, and, on a removal, whether to
# keep or delete the app's user data.
#
# Ported from the `show_dialog_fiber` half of upstream's
# src/bz-transaction-dialog.c. Upstream's "high risk" warning step — shown
# before the picker for a proprietary app that would get full filesystem or
# X11 access — depends on `safety-calculator.c`, which is not ported, so
# that step is left out; every other entry goes straight to the picker,
# same as upstream's low-risk path.
#
# Upstream runs this as a libdex fiber that awaits the dialog's "response"
# signal. The port has no fiber scheduler, so `show` takes a block instead
# and calls it once the dialog responds, with the same result shape upstream
# builds (`confirmed`, `selected_entry`, `delete_user_data`).
class TransactionDialog
  Result = Struct.new(:confirmed, :selected_entry, :delete_user_data, keyword_init: true)

  def initialize(group:, remove:, repositories: [])
    @group = group
    @remove = remove
    @repositories = Array(repositories)
    @candidates = Array(group&.model)
  end

  def show(parent, &on_result)
    case @candidates.empty?
    when true then on_result&.call(Result.new(confirmed: false, selected_entry: nil, delete_user_data: false))
    else
      dialog.tap do |d|
        d.signal_connect("response") { |_, response| handle_response(response, on_result) }
        d.present(parent)
      end
    end
  end

  def dialog
    @dialog ||= Adwaita::AlertDialog.new.tap do |d|
      d.heading = heading
      d.body = body
      d.add_response("cancel", "_Cancel")
      d.add_response(action_response, action_label)
      d.set_response_appearance(action_response, response_appearance)
      d.default_response = action_response
      d.close_response = "cancel"
      assign_extra_child(d)
    end
  end

  private

    def title = @group&.title.to_s

    def heading
      case @remove
      when true then "Remove #{title}?"
      else "Install #{title}?"
      end
    end

    def body
      case @candidates.length > 1
      when true
        case @remove
        when true then "Select which version to remove."
        else "Select which version to install. May install additional shared components"
        end
      else
        case @remove
        when true then "It will not be possible to use #{title} after it is uninstalled."
        else "May install additional shared components"
        end
      end
    end

    def action_response
      case @remove
      when true then "remove"
      else "install"
      end
    end

    def action_label
      case @remove
      when true then "_Remove"
      else "_Install"
      end
    end

    def response_appearance
      case @remove
      when true then :destructive
      else :suggested
      end
    end

    def assign_extra_child(dialog)
      case @candidates.length > 1 || @remove
      when true then dialog.extra_child = extra_child
      end
    end

    def extra_child
      Gtk::Box.new(:vertical, 12).tap do |box|
        case @candidates.length > 1
        when true then box.append(picker_list)
        end
        case @remove
        when true then box.append(data_choice_list)
        end
      end
    end

    def picker_list
      @picker_list ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("boxed-list")
        rows.each { |row| list.append(row.build) }
        first_eligible_row.then { |row| row.nil? || row.radio.active = true }
      end
    end

    def rows
      @rows ||= @candidates.map do |entry|
        EntrySelectionRow.new(entry: entry, repository: repository_for(entry)).tap do |row|
          row.radio.sensitive = !skip?(entry)
        end
      end.tap { |built| group_radios(built) }
    end

    def group_radios(built)
      built.first&.radio.then do |leader|
        case leader
        when nil then nil
        else built.drop(1).each { |row| row.radio.group = leader }
        end
      end
    end

    def first_eligible_row = rows.find { |row| row.radio.sensitive? }

    def repository_for(entry) = @repositories.find { |repo| repo.name == entry.remote_repo_name }

    # A runtime/addon dependency the backend marked not reinstallable, or an
    # entry the removal side would find not installed, is shown but
    # disabled — upstream's `should_skip_entry`.
    def skip?(entry)
      case @remove
      when true then !entry.installed?
      else entry.installed? || !entry.reinstallable?
      end
    end

    def data_choice_list
      @data_choice_list ||= Gtk::ListBox.new.tap do |list|
        list.selection_mode = :none
        list.add_css_class("boxed-list")
        list.append(keep_data_row.build)
        list.append(delete_data_row.build)
        delete_data_row.radio.group = keep_data_row.radio
      end
    end

    def keep_data_row
      @keep_data_row ||= DataChoiceRow.new(
        title: "Keep User Data",
        subtitle: "Allow restoring personal settings & content",
        active: true,
      )
    end

    def delete_data_row
      @delete_data_row ||= DataChoiceRow.new(
        title: "Delete All Data",
        subtitle: "Permanently erase user data to save space",
        active: false,
      )
    end

    def handle_response(response, on_result)
      confirmed = response == action_response
      on_result&.call(
        Result.new(
          confirmed: confirmed,
          selected_entry: result_entry(confirmed),
          delete_user_data: confirmed && @remove && delete_data_row.radio.active?,
        ),
      )
    end

    def result_entry(confirmed)
      case confirmed
      when true then selected_entry
      else nil
      end
    end

    def selected_entry
      case @candidates.length > 1
      when true then rows.find { |row| row.radio.active? }&.entry || @candidates.first
      else @candidates.first
      end
    end
end

# DataChoiceRow is one row of the keep/delete-data radio pair a removal
# confirmation offers, built the same way upstream's inline
# `adw_action_row_new` + `gtk_check_button_new` pair is.
class DataChoiceRow
  def initialize(title:, subtitle:, active:)
    @title = title
    @subtitle = subtitle
    @active = active
  end

  def radio
    @radio ||= Gtk::CheckButton.new.tap do |button|
      button.valign = :center
      button.active = @active
    end
  end

  def build
    row.tap do |r|
      r.add_prefix(radio)
      r.activatable_widget = radio
    end
  end

  def row
    @row ||= Adwaita::ActionRow.new.tap do |r|
      r.title = @title
      r.subtitle = @subtitle
    end
  end
end
