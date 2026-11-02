# frozen_string_literal: true

require "open3"
require "rbconfig"
require "shellwords"
require_relative "backend"
require_relative "entry"
require_relative "appstream_parser"

# FlatpakBackend is the Flatpak implementation of Backend.
#
# Ported from upstream's src/bz-flatpak-instance.c and src/bz-flatpak-entry.c.
# Upstream links against libflatpak; the Ruby bindings have no libflatpak, so
# the port drives the `flatpak` command line, which exposes the same four
# things those files need: the configured remotes, the refs each remote
# carries with their sizes, the installed refs with their versions, and the
# refs that have an update waiting.
#
# The identity scheme is upstream's, because the entry cache, the search
# index and the transaction manager all key on it:
#
#   FLATPAK-SYSTEM::flathub::app/org.gnome.Loupe/x86_64/stable
#
# built by `unique_id_for`, with an MD5 of that string naming the entry's
# cache directory (bz_flatpak_ref_format_unique plus the checksum beside it).
class FlatpakBackend < Backend
  SYSTEM_INSTALLATION_DIR = "/var/lib/flatpak"

  # `flatpak` writes its progress as percentages on a carriage-return line;
  # anything else it prints is the status text the tiles show.
  PERCENT = /(\d{1,3})%/
  REF_LINE = %r{\b((?:app|runtime)/[^\s]+/[^\s]+/[^\s]+)\b}

  attr_reader :command

  def initialize(command: "flatpak")
    @command = command
    @cancelled = {}
    @current = nil
  end

  # True when a flatpak command line is actually available; the pages show
  # their empty state rather than an error when it is not.
  def available?
    run([@command, "--version"]).first
  end

  # Every remote the user has configured, system and per-user.
  #
  # Ported from bz_flatpak_instance_list_repositories.
  def list_repositories
    columns = ["name", "title", "url", "options"]
    rows(["remotes", "--columns=#{columns.join(",")}"]).map do |row|
      Repository.new(
        name:    row[0],
        title:   blank_to_nil(row[1]) || row[0],
        url:     row[2],
        is_user: row[3].to_s.include?("user"),
      )
    end
  end

  # The unique ids of the installed refs, mapped to the installed version.
  #
  # Upstream returns a GHashTable of unique id -> version
  # (bz_flatpak_instance_retrieve_install_ids); the port returns the same
  # mapping as a Ruby hash.
  def retrieve_install_ids
    columns = ["ref", "origin", "installation", "version"]
    rows(["list", "--all", "--columns=#{columns.join(",")}"]).to_h do |row|
      [unique_id_for(origin: row[1], ref: row[0], user: row[2] == "user"), row[3].to_s]
    end
  end

  # The unique ids with an update waiting, which is what badges the Library
  # tab and fills the updates card.
  def retrieve_update_ids
    columns = ["ref", "origin", "installation"]
    rows(["remote-ls", "--updates", "--all", "--columns=#{columns.join(",")}"]).map do |row|
      unique_id_for(origin: row[1], ref: row[0], user: row[2] == "user")
    end
  end

  # Builds an Entry for every ref every remote carries, with the AppStream
  # metadata of that remote folded in.
  #
  # Ported from bz_flatpak_instance_retrieve_remote_entries: the refs come
  # from the remote itself (so sizes and branches are the remote's), and the
  # metadata comes from the remote's AppStream catalogue, matched on the
  # `<bundle type="flatpak">` ref the catalogue declares.
  #
  # The block, when given, is called with (remote_name, index, total) as each
  # remote is read, which is what drives the refresh progress bar.
  def retrieve_remote_entries
    repositories = list_repositories
    repositories.each_with_index.flat_map do |repository, index|
      case block_given?
      when true then yield(repository.name, index, repositories.length)
      end
      entries_for_remote(repository)
    end
  end

  # Runs one merged transaction through `flatpak`, pushing an OpPayload for
  # every ref it touches and an OpProgressPayload as the output advances.
  #
  # Ported from bz_flatpak_instance_schedule_transaction, which builds a
  # FlatpakTransaction out of the same three lists.
  def schedule_transaction(installs:, updates:, removals:, channel:)
    ops = build_ops(installs, updates, removals)
    ops.each { |op, _| channel.push(op) }

    ops.each_with_index do |(op, argv), index|
      case @cancelled.delete(op.entry&.unique_id)
      when true then next
      end
      run_op(
        op,
        argv,
        channel,
        index,
        ops.length,
      )
    end

    channel.close
    true
  end

  # Marks an entry's op as cancelled. Upstream cancels the libflatpak
  # transaction through its GCancellable; here the op is skipped before it
  # starts and the running child is signalled.
  def cancel_task_for_entry(entry)
    @cancelled[entry.unique_id] = true
    @current.then do |pid|
      case pid
      when nil then false
      else
        Process.kill("TERM", pid)
        true
      end
    end
  rescue Errno::ESRCH
    false
  end

  # "FLATPAK-SYSTEM::flathub::app/org.gnome.Loupe/x86_64/stable", the id the
  # whole app keys entries on.
  def unique_id_for(origin:, ref:, user: false)
    scope = "SYSTEM"
    case user
    when true then scope = "USER"
    end
    "FLATPAK-#{scope}::#{blank_to_nil(origin) || "bundle"}::#{ref}"
  end

  # The directory a remote's AppStream catalogue is unpacked into.
  #
  # Ported from the appstream_dir handling in bz-flatpak-instance.c: the
  # "active" symlink under <installation>/appstream/<remote>/<arch>.
  def appstream_dir(remote_name, user:)
    File.join(
      installation_dir(user: user),
      "appstream",
      remote_name,
      arch,
      "active",
    )
  end

  def installation_dir(user:)
    case user
    when true
      File.join(
        ENV.fetch("XDG_DATA_HOME", File.join(Dir.home, ".local", "share")),
        "flatpak",
      )
    else SYSTEM_INSTALLATION_DIR
    end
  end

  # The architecture flatpak itself would install for.
  def arch
    @arch ||= begin
      status, out, = run([@command, "--default-arch"])
      case status
      when true then out.strip
      else default_arch
      end
    end
  end

  private

    def default_arch
      case RbConfig::CONFIG["host_cpu"]
      when "x86_64" then "x86_64"
      when "aarch64", "arm64" then "aarch64"
      else RbConfig::CONFIG["host_cpu"]
      end
    end

    # The refs a remote carries, keyed by ref, each with its download and
    # installed size.
    def remote_refs(repository)
      columns = ["ref", "download-size", "installed-size", "version", "options"]
      argv = ["remote-ls", repository.name, "--all", "--columns=#{columns.join(",")}"]
      case repository.user?
      when true then argv << "--user"
      end
      rows(argv).to_h do |row|
        [
          row[0],
          {
            download_size:  parse_size(row[1]),
            installed_size: parse_size(row[2]),
            version:        blank_to_nil(row[3]),
          },
        ]
      end
    end

    def entries_for_remote(repository)
      refs = remote_refs(repository)
      case refs.empty?
      when true then []
      else
        components = components_by_ref(repository)
        refs.map do |ref, sizes|
          entry_for(
            repository,
            ref,
            sizes,
            components[ref],
          )
        end
      end
    end

    # The remote's AppStream components, keyed by the flatpak ref each one
    # declares in its <bundle> element.
    def components_by_ref(repository)
      directory = appstream_dir(repository.name, user: repository.user?)
      catalogue = ["appstream.xml.gz", "appstream.xml"]
                  .map { |name| File.join(directory, name) }
                  .find { |path| File.exist?(path) }
      case catalogue
      when nil then {}
      else
        AppstreamParser.components(catalogue).each_with_object({}) do |component, acc|
          blank_to_nil(component.bundle).then do |ref|
            case ref
            when nil then nil
            else acc[ref] = component
            end
          end
        end
      end
    end

    def entry_for(repository, ref, sizes, component)
      kinds = kinds_for(ref)
      Entry.new.tap do |entry|
        entry.id = id_for(ref)
        entry.unique_id = unique_id_for(origin: repository.name, ref: ref, user: repository.user?)
        entry.kinds = kinds
        entry.remote_repo_name = repository.name
        entry.size = sizes[:download_size]
        entry.installed_size = sizes[:installed_size]
        entry.title = entry.id
        entry.reinstallable = (kinds & Entry::KIND_APPLICATION) != 0

        case component
        when nil then nil
        else
          AppstreamParser.populate_entry(
            entry,
            component,
            appstream_dir: appstream_dir(repository.name, user: repository.user?),
            remote_name:   repository.name,
            id:            entry.id,
            kinds:         kinds,
          )
        end
      end
    end

    # "app/org.gnome.Loupe/x86_64/stable" -> "org.gnome.Loupe"
    def id_for(ref) = ref.split("/")[1].to_s

    def kinds_for(ref)
      case ref.split("/").first
      when "app" then Entry::KIND_APPLICATION
      when "runtime" then runtime_kinds(ref)
      else 0
      end
    end

    # Flatpak models add-ons as runtimes whose name carries the extension
    # point of the app they extend, which is how upstream's key-file check
    # (an "ExtensionOf" group) classifies them.
    def runtime_kinds(ref)
      case ref.include?(".Extension.") || ref.include?(".Plugin.")
      when true then Entry::KIND_RUNTIME | Entry::KIND_ADDON
      else Entry::KIND_RUNTIME
      end
    end

    # One op per entry, in upstream's order: installs, then updates, then
    # removals.
    def build_ops(installs, updates, removals)
      [
        [installs, ["install", "--noninteractive", "--assumeyes"]],
        [updates, ["update", "--noninteractive", "--assumeyes"]],
        [removals, ["uninstall", "--noninteractive", "--assumeyes"]],
      ].flat_map do |entries, verb|
        entries.map do |entry|
          [
            Backend::OpPayload.new(
              name:           op_name(verb.first, entry),
              entry:          entry,
              download_size:  entry.size,
              installed_size: entry.installed_size,
            ),
            verb + scope_flags(entry) + [ref_of(entry)],
          ]
        end
      end
    end

    def op_name(verb, entry)
      case verb
      when "install" then "Installing #{entry.title || entry.id}"
      when "update" then "Updating #{entry.title || entry.id}"
      else "Uninstalling #{entry.title || entry.id}"
      end
    end

    def scope_flags(entry)
      case entry.unique_id.to_s.start_with?("FLATPAK-USER")
      when true then ["--user"]
      else ["--system"]
      end
    end

    # The ref back out of the unique id: everything after the second "::".
    def ref_of(entry) = entry.unique_id.to_s.split("::", 3)[2].to_s

    def run_op(op, argv, channel, index, total)
      started = Time.now.to_i
      channel.push(
        Backend::OpProgressPayload.new(
          op:             op,
          status:         op.name,
          is_estimating:  true,
          progress:       0.0,
          total_progress: index.fdiv(total),
          start_time:     started,
        ),
      )

      status = stream([@command] + argv) do |chunk|
        publish_progress(
          op,
          chunk,
          channel,
          index,
          total,
          started,
        )
      end

      case status
      when false then raise(Backend::Failure, "#{op.name} failed")
      end

      channel.push(
        Backend::OpProgressPayload.new(
          op:             op,
          status:         op.name,
          progress:       1.0,
          total_progress: (index + 1).fdiv(total),
          start_time:     started,
        ),
      )
      op
    end

    def publish_progress(op, chunk, channel, index, total, started)
      PERCENT.match(chunk).then do |match|
        progress = 0.0
        case match
        when nil then nil
        else progress = match[1].to_i.fdiv(100)
        end
        channel.push(
          Backend::OpProgressPayload.new(
            op:             op,
            status:         status_text(chunk, op),
            is_estimating:  match.nil?,
            progress:       progress,
            total_progress: (index + progress).fdiv(total),
            start_time:     started,
          ),
        )
      end
    end

    def status_text(chunk, op)
      chunk.split(/[\r\n]/).map(&:strip).reject(&:empty?).last.then do |line|
        case line
        when nil then op.name
        else line
        end
      end
    end

    # Runs a command and returns [ok, stdout, stderr].
    def run(argv)
      out, err, status = Open3.capture3(*argv)
      [status.success?, out, err]
    rescue Errno::ENOENT
      [false, "", "#{argv.first} is not installed"]
    end

    # Runs a command, handing each chunk of its output to the block as it
    # arrives, and answers whether it succeeded.
    def stream(argv, &block)
      Open3.popen2e(*argv) do |stdin, output, wait|
        stdin.close
        @current = wait.pid
        read_chunks(output, &block)
        @current = nil
        wait.value.success?
      end
    rescue Errno::ENOENT
      false
    end

    def read_chunks(output)
      buffer = +""
      until output.eof?
        buffer << output.readpartial(4096)
        buffer.split(/(?<=[\r\n])/).then do |pieces|
          buffer = pieces.pop.to_s
          pieces.each { |piece| yield(piece) }
        end
      end
      case buffer.strip.empty?
      when false then yield(buffer)
      end
    rescue EOFError, IOError
      nil
    end

    # `flatpak --columns=...` prints one tab-separated row per line, with no
    # header when a column list is given.
    def rows(argv)
      status, out, = run([@command] + argv)
      case status
      when false then []
      else
        out.each_line.map { |line| line.chomp.split("\t") }.reject { |row| row.compact.empty? }
      end
    end

    # The sizes flatpak prints are human readable ("1.2 MB"); the UI wants
    # bytes.
    def parse_size(text)
      /\A\s*([\d.,]+)\s*([kMGT]?)i?B?\s*\z/.match(text.to_s).then do |match|
        case match
        when nil then 0
        else (match[1].tr(",", ".").to_f * multiplier(match[2])).round
        end
      end
    end

    def multiplier(suffix)
      case suffix
      when "k" then 1024
      when "M" then 1024**2
      when "G" then 1024**3
      when "T" then 1024**4
      else 1
      end
    end

    def blank_to_nil(value)
      case value.to_s.strip.empty?
      when true then nil
      else value.to_s.strip
      end
    end
end
