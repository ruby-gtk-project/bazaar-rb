# frozen_string_literal: true

require "gtk4"
require_relative "entry"
require_relative "backend"

# TransactionTask is one backend op plus its latest progress and, if it went
# wrong, the error.
#
# Ported from upstream's src/bz-transaction-task.txt.
class TransactionTask < GLib::Object
  type_register

  attr_accessor :op, :last_progress, :error

  def initialize(op:)
    super()
    @op = op
    @last_progress = nil
    @error = nil
  end

  def errored? = !@error.nil?
end

# TransactionEntryTracker follows one entry through a transaction: which kind
# of change it is, whether it is queued, running, done or cancelled, and how
# far along it is.
#
# Ported from upstream's src/bz-transaction-entry-tracker.txt. The library
# page's download and uninstall lists are built from these.
class TransactionEntryTracker < GLib::Object
  type_register

  KIND_INSTALL = :install
  KIND_UPDATE  = :update
  KIND_REMOVAL = :removal

  STATUS_QUEUED    = :queued
  STATUS_ONGOING   = :ongoing
  STATUS_DONE      = :done
  STATUS_CANCELLED = :cancelled

  attr_reader :entry, :kind, :current_ops, :finished_ops
  attr_accessor :status, :progress, :pending, :active

  def initialize(entry:, kind:)
    super()
    @entry = entry
    @kind = kind
    @current_ops = []
    @finished_ops = []
    @status = STATUS_QUEUED
    @progress = 0.0
    @pending = true
    # A removal has nothing to download, so upstream marks it active the
    # moment it is queued.
    @active = kind == KIND_REMOVAL
    @listeners = []
  end

  def pending? = @pending == true
  def active? = @active == true
  def done? = @status == STATUS_DONE
  def cancelled? = @status == STATUS_CANCELLED

  def on_change(&block)
    @listeners << block
    block
  end

  def changed
    @listeners.each(&:call)
  end

  def add_current_op(task)
    @current_ops << task
    changed
    task
  end

  def finish_op(task)
    @current_ops.delete(task)
    @finished_ops << task
    changed
    task
  end
end

# Transaction is one batch of installs, updates and removals, and everything
# the UI needs to describe it while it runs.
#
# Ported from upstream's src/bz-transaction.c and src/bz-transaction.h.
class Transaction < GLib::Object
  type_register

  attr_reader :installs, :updates, :removals, :trackers, :current_ops, :finished_ops
  attr_accessor :name, :status, :progress, :error

  def initialize(installs: [], updates: [], removals: [])
    super()
    case installs.empty? && updates.empty? && removals.empty?
    when true then raise(ArgumentError, "a transaction must change something")
    end

    @installs = installs
    @updates = updates
    @removals = removals
    @current_ops = []
    @finished_ops = []
    @pending = false
    @finished = false
    @success = false
    @progress = 0.0
    @status = nil
    @error = nil
    @listeners = []
    @trackers = build_trackers
    @name = default_name
  end

  # The merged transaction the manager hands the backend when several have
  # queued up. Ported from bz_transaction_new_merged.
  def self.merged(transactions)
    case transactions.length >= 2
    when false then raise(ArgumentError, "merging needs at least two transactions")
    end

    new(
      installs: transactions.flat_map(&:installs),
      updates:  transactions.flat_map(&:updates),
      removals: transactions.flat_map(&:removals),
    )
  end

  def pending? = @pending == true
  def finished? = @finished == true
  def success? = @success == true

  def pending=(value)
    @pending = value == true
    changed
  end

  def success=(value)
    @success = value == true
    changed
  end

  # Setting this runs upstream's `finish`, which settles every tracker.
  def finished=(value)
    @finished = value == true
    case @finished
    when true then finish_trackers
    end
    changed
  end

  def on_change(&block)
    @listeners << block
    block
  end

  def changed
    @listeners.each(&:call)
  end

  def entries = @installs + @updates + @removals

  # Every entry a transaction touches is held for its duration, which is what
  # makes the install and remove buttons of that app go insensitive.
  def hold
    entries.each(&:hold)
  end

  def release
    entries.each(&:release)
  end

  # The backend announced a new op: record it and attach it to the tracker of
  # the entry it belongs to. Ported from bz_transaction_add_task.
  def add_task(payload)
    TransactionTask.new(op: payload).tap do |task|
      @current_ops << task
      tracker_for(payload.entry).then do |tracker|
        case tracker
        when nil then nil
        else
          # An update's download size is not known up front, so upstream
          # blanks it rather than showing a wrong number.
          case tracker.kind == TransactionEntryTracker::KIND_UPDATE
          when true then payload.download_size = nil
          end
          tracker.add_current_op(task)
          tracker.status = TransactionEntryTracker::STATUS_ONGOING
          tracker.active = true
        end
      end
      changed
    end
  end

  # Ported from bz_transaction_update_task.
  def update_task(progress_payload)
    task_for(progress_payload.op).then do |task|
      case task
      when nil then nil
      else task.last_progress = progress_payload
      end
    end

    tracker_for(progress_payload.op.entry).then do |tracker|
      case tracker
      when nil then nil
      else
        tracker.progress = progress_payload.progress
        tracker.pending = progress_payload.estimating?
        tracker.active = true
        tracker.status = TransactionEntryTracker::STATUS_ONGOING
        tracker.changed
      end
    end
    changed
  end

  # Ported from bz_transaction_finish_task.
  def finish_task(payload)
    transfer(payload) do |tracker|
      tracker.status = TransactionEntryTracker::STATUS_DONE
      tracker.active = false
      tracker.pending = false
      tracker.progress = 1.0
    end
  end

  # Ported from bz_transaction_error_out_task.
  def error_out_task(payload, message)
    transfer(payload) do |tracker|
      tracker.status = TransactionEntryTracker::STATUS_CANCELLED
      tracker.active = false
      tracker.pending = false
    end.then do |task|
      case task
      when nil then nil
      else task.error = message
      end
    end
  end

  private

    def transfer(payload)
      task_for(payload).tap do |task|
        case task
        when nil then nil
        else
          @current_ops.delete(task)
          @finished_ops << task
        end

        tracker_for(payload.entry).then do |tracker|
          case tracker
          when nil then nil
          else
            case task
            when nil then nil
            else tracker.finish_op(task)
            end
            yield(tracker)
            tracker.changed
          end
        end
        changed
      end
    end

    def task_for(payload) = @current_ops.find { |task| task.op.equal?(payload) }

    def tracker_for(entry) = @trackers.find { |tracker| tracker.entry.equal?(entry) }

    def build_trackers
      [
        [@installs, TransactionEntryTracker::KIND_INSTALL],
        [@updates, TransactionEntryTracker::KIND_UPDATE],
        [@removals, TransactionEntryTracker::KIND_REMOVAL],
      ].flat_map do |entries, kind|
        entries.map { |entry| TransactionEntryTracker.new(entry: entry, kind: kind) }
      end
    end

    # Every tracker settles when the transaction does: a tracker already
    # cancelled stays cancelled, the rest follow the transaction's outcome.
    def finish_trackers
      @trackers.each do |tracker|
        tracker.active = false
        tracker.pending = false
        case tracker.cancelled?
        when true then next
        end
        tracker.status = outcome_status
        tracker.changed
      end
    end

    def outcome_status
      case @success
      when true then TransactionEntryTracker::STATUS_DONE
      else TransactionEntryTracker::STATUS_CANCELLED
      end
    end

    # What the transaction dialog calls this batch: the single app it
    # changes, or a count.
    def default_name
      case entries.length
      when 1 then entries.first.title || entries.first.id
      else "#{entries.length} apps"
      end
    end
end
