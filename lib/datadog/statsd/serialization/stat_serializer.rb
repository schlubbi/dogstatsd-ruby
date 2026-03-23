# frozen_string_literal: true

module Datadog
  class Statsd
    module Serialization
      class StatSerializer
        STAT_CACHE_MAX_SIZE = 1024

        def initialize(prefix, container_id, external_data, global_tags: [])
          @prefix = prefix
          @prefix_str = prefix.to_s
          @tag_serializer = TagSerializer.new(global_tags)
          @field_serializer = FieldSerializer.new(container_id, external_data)
          @stat_cache = {}
          @stat_cache_size = 0
        end

        def format(metric_name, delta, type, tags: [], sample_rate: 1, cardinality: nil)
          # Fast path: cache full output for common case (sample_rate=1, cardinality=nil)
          if sample_rate == 1 && cardinality.nil?
            tags_formatted = tag_serializer.format(tags)
            tags_key = tags_formatted ? tags_formatted.object_id : 0

            # Nested hash lookup: name → type → (tags_key → result, ~tags_key → delta)
            # The leaf level stores result and delta as two separate entries in h2
            # using tags_key and ~tags_key (bitwise NOT) as keys. This avoids
            # creating a sub-Hash for each tags combination — adding entries to
            # an existing Hash doesn't allocate new Ruby objects.
            if h1 = @stat_cache[metric_name]
              if h2 = h1[type]
                if (cached = h2[tags_key]) && h2[~tags_key] == delta
                  return cached
                end
              end
            end

            metric_name_fmt = formatted_metric_name(metric_name)
            fields = field_serializer.format(cardinality)

            result = if tags_formatted
              "#{@prefix_str}#{metric_name_fmt}:#{delta}|#{type}|##{tags_formatted}#{fields}"
            else
              "#{@prefix_str}#{metric_name_fmt}:#{delta}|#{type}#{fields}"
            end

            result.freeze
            if @stat_cache_size < STAT_CACHE_MAX_SIZE
              if h2
                # h2 exists — just add entries (no new objects allocated,
                # Hash#[]= on an existing hash only resizes internal C storage)
                h2[tags_key] = result
                h2[~tags_key] = delta
              elsif h1
                h1[type] = { tags_key => result, ~tags_key => delta }
              else
                @stat_cache[metric_name] = { type => { tags_key => result, ~tags_key => delta } }
              end
              @stat_cache_size += 1
            end
            return result
          end

          metric_name = formatted_metric_name(metric_name)
          fields = field_serializer.format(cardinality)

          if sample_rate != 1
            if tags_list = tag_serializer.format(tags)
              "#{@prefix_str}#{metric_name}:#{delta}|#{type}|@#{sample_rate}|##{tags_list}#{fields}"
            else
              "#{@prefix_str}#{metric_name}:#{delta}|#{type}|@#{sample_rate}#{fields}"
            end
          else
            if tags_list = tag_serializer.format(tags)
              "#{@prefix_str}#{metric_name}:#{delta}|#{type}|##{tags_list}#{fields}"
            else
              "#{@prefix_str}#{metric_name}:#{delta}|#{type}#{fields}"
            end
          end
        end

        def global_tags
          tag_serializer.global_tags
        end

        private

        attr_reader :prefix
        attr_reader :tag_serializer
        attr_reader :field_serializer

        if RUBY_VERSION < '3'
          def metric_name_to_string(metric_name)
            metric_name.to_s
          end
        else
          def metric_name_to_string(metric_name)
            Symbol === metric_name ? metric_name.name : metric_name.to_s
          end
        end

        def formatted_metric_name(metric_name)
          formatted = metric_name_to_string(metric_name)
          if formatted.include?('::')
            formatted = formatted.gsub('::', '.')
            formatted.tr!(':|@', '_')
            formatted
          elsif formatted.include?(':') || formatted.include?('@') || formatted.include?('|')
            formatted.tr(':|@', '_')
          else
            formatted
          end
        end
      end
    end
  end
end
