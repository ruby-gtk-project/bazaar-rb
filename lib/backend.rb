# frozen_string_literal: true

require "gtk4"
require_relative "entry"

# Repository is one configured remote.
#
# Ported from upstream's src/bz-repository.txt.
class Repository
  attr_accessor :name, :title, :url, :is_user

  def initialize(name: nil, title: nil, url: nil, is_user: false)
    @name = name
    @title = title
    @url = url
    @is_user = is_user
  end

  def user? = @is_user == true
end

# Backend is the interface the UI talks to instead of a package manager.
#
# Ported from upstream's src/bz-backend.c and src/bz-backend.h, which declare
# it as a GInterface. The port keeps the same six operations plus the
# notification channel, and keeps `merge_and_schedule_transactions`, the one
# method upstream implements on the interface itself.
#
# Upstream's operations return DexFutures. The port runs them synchronously
# off the main loop and reports progress through the notification channel, so
# a caller schedules work with GLib::Idle / a thread and the UI stays on the
# main loop.
class Backend
  # Raised by an operation a particular backend does not offer — a bundle
  # file backend has no remotes to list, for instance.
  Unsupported = Class.new(StandardError)

  # Raised when the underlying package manager reports a failure; the
  # transaction manager turns it into the error on the task.
  Failure = Class.new(StandardError)

  # One unit of work inside a transaction: install this ref, update that
  # one. Ported from src/bz-backend-transaction-op-payload.txt.
  class OpPayload
    attr_accessor :name, :entry, :download_size, :installed_size

    def initialize(name: nil, entry: nil, download_size: 0, installed_size: 0)
      @name = name
      @entry = entry
      @download_size = download_size
      @installed_size = installed_size
    end
  end

  # Progress for one op. Ported from
  # src/bz-backend-transaction-op-progress-payload.txt.
  class OpProgressPayload
    attr_accessor :op,
      :status,
      :is_estimating,
      :progress,
      :total_progress,
      :bytes_transferred,
      :start_time

    def initialize(**attributes)
      @op = attributes[:op]
      @status = attributes[:status]
      @is_estimating = attributes.fetch(:is_estimating, false)
      @progress = attributes.fetch(:progress, 0.0)
      @total_progress = attributes.fetch(:total_progress, 0.0)
      @bytes_transferred = attributes.fetch(:bytes_transferred, 0)
      @start_time = attributes.fetch(:start_time, 0)
    end

    def estimating? = @is_estimating == true
  end

  # The port's stand-in for the DexChannel a transaction is given: the
  # backend pushes payloads in, the transaction manager drains them on the
  # main loop. Ported from the channel half of src/bz-backend.c.
  class NotificationChannel
    def initialize
      @queue = Queue.new
      @closed = false
    end

    def push(payload)
      @queue.push(payload)
      payload
    end

    # Takes everything waiting without blocking, which is what the idle
    # handler draining this on the main loop needs.
    def drain
      [].tap do |payloads|
        payloads << @queue.pop(true) while !@queue.empty?
      rescue ThreadError
        nil
      end
    end

    def close
      @closed = true
    end

    def closed? = @closed
  end

  def create_notification_channel = NotificationChannel.new

  def load_local_package(_file) = raise(Unsupported, "#{self.class} cannot load local packages")

  def retrieve_remote_entries(&_progress) = raise(Unsupported, "#{self.class} has no remote entries")

  def retrieve_install_ids = raise(Unsupported, "#{self.class} cannot list installed ids")

  def retrieve_update_ids = raise(Unsupported, "#{self.class} cannot list updates")

  def list_repositories = raise(Unsupported, "#{self.class} has no repositories")

  def schedule_transaction(installs:, updates:, removals:, channel:)
    raise(Unsupported, "#{self.class} cannot schedule transactions")
  end

  def cancel_task_for_entry(_entry) = false

  # Flattens several transactions into one call, so a queue that built up
  # while another install was running goes to the package manager as a single
  # operation. Ported from bz_backend_merge_and_schedule_transactions.
  def merge_and_schedule_transactions(transactions, channel:)
    case transactions.empty?
    when true then raise(ArgumentError, "no transactions to schedule")
    end

    schedule_transaction(
      installs: transactions.flat_map(&:installs),
      updates:  transactions.flat_map(&:updates),
      removals: transactions.flat_map(&:removals),
      channel:  channel,
    )
  end
end
