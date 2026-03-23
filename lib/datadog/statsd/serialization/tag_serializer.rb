# frozen_string_literal: true

module Datadog
  class Statsd
    module Serialization
      class TagSerializer
        FORMAT_CACHE_MAX_SIZE = 1024

        def initialize(global_tags = [], env = ENV)
          # Cache for fully formatted tag strings (keyed by array object_id or identity)
          @format_cache = {}

          # Convert to hash
          global_tags = to_tags_hash(global_tags)

          # Merge with default tags
          global_tags = default_tags(env).merge(global_tags)

          # Convert to tag list and set
          @global_tags = to_tags_list(global_tags)
          if @global_tags.any?
            @global_tags_formatted = @global_tags.join(',')
          else
            @global_tags_formatted = nil
          end
        end

        def format(message_tags)
          if !message_tags || message_tags.empty?
            return @global_tags_formatted
          end

          # Cache lookup by the tags array/hash identity
          # Arrays with same elements will have different object_ids, so use the array itself as key
          if cached = @format_cache[message_tags]
            return cached
          end

          # Build result string directly, avoiding intermediate array allocations
          result = if @global_tags_formatted
            r = String.new(@global_tags_formatted)
            append_tags(r, message_tags)
            r
          else
            build_tags_string(message_tags)
          end

          result.freeze

          # Bounded cache
          if @format_cache.size < FORMAT_CACHE_MAX_SIZE
            @format_cache[message_tags] = result
          end

          result
        end

        attr_reader :global_tags

        private

        def to_tags_hash(tags)
          case tags
          when Hash
            tags.dup
          when Array
            Hash[
              tags.map do |string|
                tokens = string.split(':')
                tokens << nil if tokens.length == 1
                tokens.length == 2 ? tokens : nil
              end.compact
            ]
          else
            {}
          end
        end

        def to_tags_list(tags)
          case tags
          when Hash
            tags.map do |name, value|
              if value
                escape_tag_content("#{name}:#{value}")
              else
                escape_tag_content(name)
              end
            end
          when Array
            tags.map { |tag| escape_tag_content(tag) }
          else
            []
          end
        end

        def escape_tag_content(tag)
          tag = tag.to_s
          return tag unless tag.include?('|') || tag.include?(',')
          tag.delete('|,')
        end

        # Append tags to an existing string with comma separators
        def append_tags(result, tags)
          case tags
          when Array
            tags.each do |tag|
              result << ','
              result << escape_tag_content(tag)
            end
          when Hash
            tags.each do |name, value|
              result << ','
              if value
                result << escape_tag_content("#{name}:#{value}")
              else
                result << escape_tag_content(name)
              end
            end
          end
        end

        # Build tags string from scratch (no global tags prefix)
        def build_tags_string(tags)
          case tags
          when Array
            return '' if tags.empty?
            result = String.new(escape_tag_content(tags[0]))
            i = 1
            while i < tags.length
              result << ','
              result << escape_tag_content(tags[i])
              i += 1
            end
            result
          when Hash
            first = true
            result = String.new
            tags.each do |name, value|
              result << ',' unless first
              first = false
              if value
                result << escape_tag_content("#{name}:#{value}")
              else
                result << escape_tag_content(name)
              end
            end
            result
          else
            ''
          end
        end

        def dd_tags(env = ENV)
          return {} unless dd_tags = env['DD_TAGS']

          to_tags_hash(dd_tags.split(','))
        end

        def default_tags(env = ENV)
          dd_tags(env).tap do |tags|
            tags['dd.internal.entity_id'] = env['DD_ENTITY_ID'] if env.key?('DD_ENTITY_ID')
            tags['env'] = env['DD_ENV'] if env.key?('DD_ENV')
            tags['service'] = env['DD_SERVICE'] if env.key?('DD_SERVICE')
            tags['version'] = env['DD_VERSION'] if env.key?('DD_VERSION')
          end
        end
      end
    end
  end
end
