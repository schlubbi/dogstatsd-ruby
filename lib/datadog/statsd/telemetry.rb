# frozen_string_literal: true
require 'time'

module Datadog
  class Statsd
    class Telemetry
      attr_reader :metrics
      attr_reader :events
      attr_reader :service_checks
      attr_reader :bytes_sent
      attr_reader :bytes_dropped
      attr_reader :bytes_dropped_queue
      attr_reader :bytes_dropped_writer
      attr_reader :packets_sent
      attr_reader :packets_dropped
      attr_reader :packets_dropped_queue
      attr_reader :packets_dropped_writer

      # Rough estimation of maximum telemetry message size without tags
      MAX_TELEMETRY_MESSAGE_SIZE_WT_TAGS = 50 # bytes

      def initialize(flush_interval, container_id, external_data, cardinality, global_tags: [], transport_type: :udp)
        @flush_interval = flush_interval
        @global_tags = global_tags
        @transport_type = transport_type
        reset

        # TODO: Karim: I don't know why but telemetry tags are serialized
        # before global tags so by refactoring this, I am keeping the same behavior
        @serialized_tags = Serialization::TagSerializer.new(
          client: 'ruby',
          client_version: VERSION,
          client_transport: transport_type,
        ).format(global_tags)

        @serialized_fields = Serialization::FieldSerializer.new(
          container_id,
          external_data
        ).format(cardinality)

        # Pre-compute zero-value telemetry strings to avoid sprintf per flush
        # Each counter gets its own value cache: { value => frozen_string }
        @value_caches = TELEMETRY_COUNTER_NAMES.map { |name|
          cache = {}
          cache[0] = sprintf(pattern, name, 0).freeze
          cache
        }
      end

      def would_fit_in?(max_buffer_payload_size)
        MAX_TELEMETRY_MESSAGE_SIZE_WT_TAGS + serialized_tags.size + serialized_fields.size < max_buffer_payload_size
      end

      def reset
        @metrics = 0
        @events = 0
        @service_checks = 0
        @bytes_sent = 0
        @bytes_dropped = 0
        @bytes_dropped_queue = 0
        @bytes_dropped_writer = 0
        @packets_sent = 0
        @packets_dropped = 0
        @packets_dropped_queue = 0
        @packets_dropped_writer = 0
        @next_flush_time = now_in_s + @flush_interval
      end

      def sent(metrics: 0, events: 0, service_checks: 0, bytes: 0, packets: 0)
        @metrics += metrics
        @events += events
        @service_checks += service_checks

        @bytes_sent += bytes
        @packets_sent += packets
      end

      def dropped_queue(bytes: 0, packets: 0)
        @bytes_dropped += bytes
        @bytes_dropped_queue += bytes
        @packets_dropped += packets
        @packets_dropped_queue += packets
      end

      def dropped_writer(bytes: 0, packets: 0)
        @bytes_dropped += bytes
        @bytes_dropped_writer += bytes
        @packets_dropped += packets
        @packets_dropped_writer += packets
      end

      def should_flush?
        @next_flush_time < now_in_s
      end

      TELEMETRY_COUNTER_NAMES = [
        'metrics',
        'events',
        'service_checks',
        'bytes_sent',
        'bytes_dropped',
        'bytes_dropped_queue',
        'bytes_dropped_writer',
        'packets_sent',
        'packets_dropped',
        'packets_dropped_queue',
        'packets_dropped_writer',
      ].freeze

      def flush
        # Return a new array each call for thread safety — callers may
        # iterate the result while another thread triggers a new flush.
        # The strings themselves are cached/frozen so no new string allocs.
        [
          telemetry_format(0, @metrics),
          telemetry_format(1, @events),
          telemetry_format(2, @service_checks),
          telemetry_format(3, @bytes_sent),
          telemetry_format(4, @bytes_dropped),
          telemetry_format(5, @bytes_dropped_queue),
          telemetry_format(6, @bytes_dropped_writer),
          telemetry_format(7, @packets_sent),
          telemetry_format(8, @packets_dropped),
          telemetry_format(9, @packets_dropped_queue),
          telemetry_format(10, @packets_dropped_writer),
        ]
      end

      private
      attr_reader :serialized_tags
      attr_reader :serialized_fields

      def pattern
        @pattern ||= "datadog.dogstatsd.client.%s:%d|#{COUNTER_TYPE}|##{serialized_tags}#{serialized_fields}"
      end

      def telemetry_format(index, value)
        cache = @value_caches[index]
        if cached = cache[value]
          return cached
        end
        result = sprintf(pattern, TELEMETRY_COUNTER_NAMES[index], value).freeze
        cache[value] = result if cache.size < 32
        result
      end

      if Kernel.const_defined?('Process') && Process.respond_to?(:clock_gettime)
        def now_in_s
          Process.clock_gettime(Process::CLOCK_MONOTONIC, :second)
        end
      else
        def now_in_s
          Time.now.to_i
        end
      end
    end
  end
end
