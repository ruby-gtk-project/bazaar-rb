# frozen_string_literal: true

require "gtk4"
require_relative "transaction"
require_relative "backend"

# TransactionManager runs transactions one at a time and keeps the lists the
# UI watches while they run.
#
# Ported from upstream's src/bz-transaction-manager.c and
# src/bz-transaction-manager.h.
#
# Upstream runs each transaction as a libdex fiber and receives the backend's
# payloads over a DexChannel. The port runs the backend call on a Ruby thread
# and drains the same payloads on the main loop from a GLib timeout, so the
# widgets are only ever touched from the main thread.
#
# Queued transactions are merged: when something is already running, the
# waiting ones are folded into a single transaction, which is what upstream's
# dispatch_next does with its queue.
class TransactionManager
  # How often the main loop drains the notification channel, in
  # milliseconds. Upstream is woken by the channel itself; a short poll is
  # the port's equivalent and is still far faster than the progress changes
  # a user can see.
  POLL_INTERVAL = 50

  attr_reader :transactions
  attr_accessor :backend

  def initialize(backend: nil)
    @backend = backend
    @transactions = []
    @queue = []
    @current = nil
    @paused = false
    @current_progress = 0.0
    @pending = false
    @listeners = []
    @success_handlers = []
    @failure_handlers = []
  end

  def paused? = @paused

  def paused=(value)
    @paused = value == true
    changed
    case @paused
    when false then dispatch_next
    end
  end

  # True while a transaction is running.
  def active? = !@current.nil?

  # True while the running transaction is still working out what it will do;
  # the progress bar shows an indeterminate pulse for it.
  def pending? = @pending

  def has_transactions? = !@transactions.empty?

  def current_progress = @current_progress

  # Every tracker of every transaction, flattened the way upstream's
  # GtkFlattenListModel does.
  def all_trackers = @transactions.flat_map(&:trackers)

  def install_trackers
    all_trackers.select do |tracker|
      [
        TransactionEntryTracker::KIND_INSTALL,
        TransactionEntryTracker::KIND_UPDATE,
      ].include?(tracker.kind)
    end
  end

  def removal_trackers
    all_trackers.select { |tracker| tracker.kind == TransactionEntryTracker::KIND_REMOVAL }
  end

  def on_change(&block)
    @listeners << block
    block
  end

  def on_success(&block)
    @success_handlers << block
    block
  end

  def on_failure(&block)
    @failure_handlers << block
    block
  end

  def changed
    @listeners.each(&:call)
  end

  # Queues a transaction and starts it when nothing else is running.
  #
  # Ported from bz_transaction_manager_add.
  def add(transaction)
    transaction.hold
    @transactions << transaction
    @queue << transaction
    transaction.on_change { changed }
    changed
    dispatch_next
    transaction
  end

  # Ported from bz_transaction_manager_cancel_current.
  def cancel_current
    @current.then do |transaction|
      case transaction
      when nil then false
      else
        transaction.entries.each { |entry| @backend&.cancel_task_for_entry(entry) }
        true
      end
    end
  end

  # Drops the transactions that have finished from the list, which is what
  # the library page's "Clear Finished Tasks" row does.
  #
  # Ported from bz_transaction_manager_clear_finished.
  def clear_finished
    @transactions.reject!(&:finished?)
    changed
  end

  private

    # Starts the next transaction, merging everything else waiting into it.
    def dispatch_next
      case @paused || !@current.nil? || @queue.empty?
      when true then nil
      else start(take_next)
      end
    end

    def take_next
      case @queue.length
      when 1 then @queue.shift
      else
        Transaction.merged(@queue.dup).tap do |merged|
          @queue.clear
          @transactions << merged
          merged.on_change { changed }
        end
      end
    end

    def start(transaction)
      @current = transaction
      @pending = true
      @current_progress = 0.0
      transaction.status = "Starting up..."
      transaction.progress = 0.0
      changed

      channel = @backend.create_notification_channel
      started = Time.now
      worker = Thread.new { schedule(transaction, channel) }

      poll(
        transaction,
        channel,
        worker,
        started,
      )
      transaction
    end

    def schedule(transaction, channel)
      @backend.merge_and_schedule_transactions([transaction], channel: channel)
      [true, nil]
    rescue StandardError => error
      channel.close
      [false, error.message]
    end

    # Drains the channel on the main loop until the worker thread is done,
    # then settles the transaction. This is the port of transaction_fiber's
    # receive loop plus transaction_finally.
    def poll(transaction, channel, worker, started)
      seen = {}
      GLib::Timeout.add(POLL_INTERVAL) do
        consume(transaction, channel, seen)
        case worker.alive?
        when true then GLib::Source::CONTINUE
        else
          consume(transaction, channel, seen)
          settle(
            transaction,
            worker,
            seen,
            started,
          )
          GLib::Source::REMOVE
        end
      end
    end

    def consume(transaction, channel, seen)
      channel.drain.each do |payload|
        case payload
        when Backend::OpPayload then consume_op(transaction, payload, seen)
        when Backend::OpProgressPayload then consume_progress(transaction, payload)
        end
      end
    end

    # The backend announces an op twice: once when it starts and once when it
    # is done, which is how upstream's op_set tells the two apart.
    def consume_op(transaction, payload, seen)
      case seen.key?(payload.object_id)
      when true
        seen.delete(payload.object_id)
        transaction.finish_task(payload)
      else
        seen[payload.object_id] = payload
        transaction.add_task(payload)
      end
    end

    def consume_progress(transaction, payload)
      transaction.update_task(payload)
      transaction.pending = payload.estimating?
      transaction.status = payload.status
      transaction.progress = payload.total_progress
      @pending = payload.estimating?
      @current_progress = payload.total_progress
      changed
    end

    def settle(transaction, worker, seen, started)
      ok, message = worker.value

      # Anything the backend never reported finishing was cut short.
      seen.each_value { |payload| transaction.error_out_task(payload, "Cancelled") }

      transaction.status = format("Finished in %.02f seconds", Time.now - started)
      transaction.progress = 1.0
      transaction.success = ok
      transaction.error = message
      transaction.finished = true
      transaction.release

      @current_progress = 1.0
      @pending = false
      @current = nil
      changed

      notify_outcome(transaction, ok)
      dispatch_next
    end

    def notify_outcome(transaction, ok)
      case ok
      when true then @success_handlers.each { |handler| handler.call(transaction) }
      else @failure_handlers.each { |handler| handler.call(transaction) }
      end
    end
end
