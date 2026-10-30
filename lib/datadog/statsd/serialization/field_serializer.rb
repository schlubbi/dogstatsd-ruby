# frozen_string_literal: true

module Datadog
  class Statsd
    module Serialization
      class FieldSerializer
        VALID_CARDINALITY = [:none, :low, :orchestrator, :high]

        def initialize(container_id, external_data)
          @origin_fields = String.new
          @origin_fields << "|c:#{container_id}" unless container_id.nil?
          @origin_fields << "|e:#{external_data}" unless external_data.nil?
          @origin_fields.freeze
        end

        def format(cardinality)
          return @origin_fields if cardinality.nil?

          unless VALID_CARDINALITY.include?(cardinality.to_sym)
            raise ArgumentError, "Invalid cardinality #{cardinality}. Valid options are #{VALID_CARDINALITY.join(', ')}."
          end

          "#{@origin_fields}|card:#{cardinality}"
        end
      end
    end
  end
end
