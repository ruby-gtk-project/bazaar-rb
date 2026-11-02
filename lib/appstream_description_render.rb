# frozen_string_literal: true

require "rexml/document"
require "adwaita"

# AppstreamDescriptionRender renders an AppStream `<description>` — the
# paragraphs, bullet lists and numbered lists an app's long description is
# written in — into a read-only text view.
#
# Ported from upstream's src/bz-appstream-description-render.c and
# src/bz-appstream-description-render.blp: the same five text tags (code,
# emphasis, paragraph, list-item-ul, list-item-ol, list-number) with the same
# spacing and indents, the same whitespace normalisation, "N." numbering for
# an ordered list and "• " for an unordered one, and a blank line after a
# paragraph or list that is not the last of its siblings.
#
# Upstream also turns bare URLs in the text into clickable links, coloured
# with the current accent colour; that part is not ported, so a URL renders
# as plain text.
class AppstreamDescriptionRender
  NO_ELEMENT     = :none
  PARAGRAPH      = :paragraph
  ORDERED_LIST   = :ordered_list
  UNORDERED_LIST = :unordered_list
  LIST_ITEM      = :list_item
  CODE           = :code
  EMPHASIS       = :emphasis

  def initialize(description: nil)
    @description = description
  end

  def build
    root.tap do |bin|
      bin.child = text_view
      setup_tags
      self.description = @description
    end
  end

  def description=(markup)
    @description = markup
    regenerate
    markup
  end

  def root = @root ||= Adwaita::Bin.new

  def text_view
    @text_view ||= Gtk::TextView.new.tap do |view|
      view.editable = false
      view.cursor_visible = false
      view.wrap_mode = :word_char
      view.height_request = 25
      view.remove_css_class("view")
    end
  end

  private

    def buffer = text_view.buffer

    def setup_tags
      @tags ||= begin
        buffer.create_tag("code", "family" => "monospace")
        buffer.create_tag("emphasis", "weight" => Pango::Weight::BOLD.to_i)
        buffer.create_tag("paragraph", "pixels-below-lines" => 12)
        buffer.create_tag(
          "list-item-ul",
          "left-margin"        => 10,
          "pixels-below-lines" => 4,
          "indent"             => -12,
        )
        buffer.create_tag(
          "list-item-ol",
          "left-margin"        => 10,
          "pixels-below-lines" => 4,
          "indent"             => -18,
        )
        buffer.create_tag("list-number", "family" => "monospace", "foreground" => "gray")
        true
      end
    end

    def regenerate
      setup_tags
      buffer.text = ""
      parse(@description).then do |document|
        case document
        when nil then nil
        else
          state = { in_space: false, at_start: true }
          children_of(document).each_with_index do |node, index|
            compile(
              node,
              parent_kind: NO_ELEMENT,
              index:       index,
              last:        index == children_of(document).length - 1,
              state:       state,
            )
          end
        end
      end
    end

    # The description arrives as a fragment, so it is wrapped before parsing.
    def parse(markup)
      case markup.nil? || markup.to_s.strip.empty?
      when true then nil
      else REXML::Document.new("<description>#{markup}</description>").root
      end
    end

    def children_of(node) = node.children.reject { |child| blank_text?(child) }

    def blank_text?(child)
      child.is_a?(REXML::Text) && child.to_s.strip.empty?
    end

    def compile(node, parent_kind:, index:, last:, state:)
      case node
      when REXML::Text then insert_text(node.value, state)
      else compile_element(
        node,
        parent_kind,
        index,
        last,
        state,
      )
      end
    end

    def compile_element(node, parent_kind, index, last, state)
      kind = kind_of(node)
      local = local_state(kind, state)
      start = buffer.create_mark(nil, buffer.end_iter, true)

      insert_marker(kind, parent_kind, index)

      kids = children_of(node)
      kids.each_with_index do |child, child_index|
        compile(
          child,
          parent_kind: kind,
          index:       child_index,
          last:        child_index == kids.length - 1,
          state:       local,
        )
      end

      apply_tag(kind, parent_kind, start)
      buffer.delete_mark(start)
      insert_trailing_break(kind, last, kids.length)
    end

    def kind_of(node)
      case node.name
      when "p" then PARAGRAPH
      when "ol" then ORDERED_LIST
      when "ul" then UNORDERED_LIST
      when "li" then LIST_ITEM
      when "code" then CODE
      when "em" then EMPHASIS
      else NO_ELEMENT
      end
    end

    # A paragraph and a list item each start their own whitespace run, which
    # is why upstream swaps in local in_space / at_start flags for them.
    def local_state(kind, state)
      case [PARAGRAPH, LIST_ITEM].include?(kind)
      when true then { in_space: false, at_start: true }
      else state
      end
    end

    def insert_marker(kind, parent_kind, index)
      case kind
      when LIST_ITEM then insert_list_marker(parent_kind, index)
      end
    end

    def insert_list_marker(parent_kind, index)
      case parent_kind
      when ORDERED_LIST
        buffer.create_mark(nil, buffer.end_iter, true).then do |prefix_start|
          buffer.insert(buffer.end_iter, "#{index + 1}.")
          buffer.apply_tag("list-number", buffer.get_iter_at(mark: prefix_start), buffer.end_iter)
          buffer.delete_mark(prefix_start)
        end
      else buffer.insert(buffer.end_iter, "• ")
      end
    end

    def apply_tag(kind, parent_kind, start)
      buffer.get_iter_at(mark: start).then do |start_iter|
        case kind
        when CODE then buffer.apply_tag("code", start_iter, buffer.end_iter)
        when EMPHASIS then buffer.apply_tag("emphasis", start_iter, buffer.end_iter)
        when PARAGRAPH then buffer.apply_tag("paragraph", start_iter, buffer.end_iter)
        when LIST_ITEM
          buffer.apply_tag(list_item_tag(parent_kind), start_iter, buffer.end_iter)
          buffer.insert(buffer.end_iter, "\n")
        end
      end
    end

    def list_item_tag(parent_kind)
      case parent_kind
      when ORDERED_LIST then "list-item-ol"
      else "list-item-ul"
      end
    end

    def insert_trailing_break(kind, last, child_count)
      case kind
      when PARAGRAPH
        case last
        when false then buffer.insert(buffer.end_iter, "\n")
        end
      when ORDERED_LIST, UNORDERED_LIST
        case !last && child_count.positive?
        when true then buffer.insert(buffer.end_iter, "\n")
        end
      end
    end

    def insert_text(text, state)
      normalize(text, state).then do |normalized|
        case normalized.empty?
        when true then nil
        else buffer.insert(buffer.end_iter, normalized)
        end
      end
    end

    # Upstream's normalize_whitespace: runs of whitespace collapse to one
    # space, and leading whitespace at the start of a block is dropped.
    def normalize(text, state)
      String.new.tap do |out|
        text.to_s.each_char do |char|
          case char.match?(/\s/)
          when true
            state[:in_space] = true
          else
            case state[:in_space] && !state[:at_start]
            when true then out << " "
            end
            state[:in_space] = false
            state[:at_start] = false
            out << char
          end
        end
      end
    end
end
