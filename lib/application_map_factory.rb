# frozen_string_literal: true

# ApplicationMapFactory turns ids into the objects the UI shows, and does it
# the same way everywhere.
#
# Ported from upstream's src/bz-application-map-factory.c, which wraps a
# GtkMapListModel's map function plus an optional filter so that the same
# conversion is reused for a whole model (`generate`) and for a single id
# (`convert_one`). The app builds two of them: unique ids to entries, and
# application ids to entry groups.
class ApplicationMapFactory
  def initialize(filter: nil, &map)
    @map = map
    @filter = filter
  end

  # One id to one object, or nil when the id is unknown or filtered out.
  def convert_one(id)
    case keep?(id)
    when false then nil
    else @map.call(id)
    end
  end

  # A whole list of ids to the objects they name, dropping the ones the
  # filter rejects and the ids nothing is known about.
  def generate(ids) = ids.select { |id| keep?(id) }.filter_map { |id| @map.call(id) }

  private

    def keep?(id)
      case @filter
      when nil then true
      else @filter.call(id)
      end
    end
end
