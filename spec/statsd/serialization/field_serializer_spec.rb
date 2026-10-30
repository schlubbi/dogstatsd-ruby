require 'spec_helper'

describe Datadog::Statsd::Serialization::FieldSerializer do
  describe '#format' do
    [
      [nil, nil, ''],
      ['container-id', nil, '|c:container-id'],
      [nil, 'external-data', '|e:external-data'],
      ['container-id', 'external-data', '|c:container-id|e:external-data'],
      ['', '', '|c:|e:'],
    ].each do |container_id, external_data, expected|
      context "with container #{container_id.inspect} and external data #{external_data.inspect}" do
        subject { described_class.new(container_id, external_data) }

        it 'formats origin fields without cardinality' do
          expect(subject.format(nil)).to eq expected
        end

        it 'keeps cardinality independent between calls' do
          expect(subject.format(:low)).to eq "#{expected}|card:low"
          expect(subject.format('high')).to eq "#{expected}|card:high"
          expect(subject.format(nil)).to eq expected
        end
      end
    end

    it 'does not let a cardinality result change subsequent origin fields' do
      serializer = described_class.new('container-id', 'external-data')
      serializer.format(:low).replace('changed')

      expect(serializer.format(nil)).to eq '|c:container-id|e:external-data'
      expect(serializer.format(:high)).to eq '|c:container-id|e:external-data|card:high'
    end

    it 'validates cardinality after formatting cached origin fields' do
      serializer = described_class.new('container-id', 'external-data')
      serializer.format(nil)

      expect { serializer.format(:invalid) }
        .to raise_error(ArgumentError, 'Invalid cardinality invalid. Valid options are none, low, orchestrator, high.')
    end

    it 'does not allocate when formatting origin fields without cardinality' do
      skip 'Ruby too old' if RUBY_VERSION < '2.3.0'
      serializer = described_class.new('container-id', 'external-data')
      serializer.format(nil)

      expect { serializer.format(nil) }.to make_allocations(0)
    end

    it 'allocates only the result when formatting cardinality on Ruby 3+' do
      skip 'Ruby too old' if RUBY_VERSION < '3'
      serializer = described_class.new('container-id', 'external-data')
      serializer.format(:low)

      expect { serializer.format(:low) }.to make_allocations(1)
    end
  end

  context 'benchmark' do
    before { skip("Benchmarks results are currently not used by CI") if ENV.key?('CI') }

    def benchmark_setup(benchmark)
      empty = described_class.new(nil, nil)
      container = described_class.new('a' * 64, nil)
      external = described_class.new(nil, 'it-false,cn-container,pu-pod')
      both = described_class.new('a' * 64, 'it-false,cn-container,pu-pod')

      benchmark.report('no origin') { empty.format(nil) }
      benchmark.report('container') { container.format(nil) }
      benchmark.report('external') { external.format(nil) }
      benchmark.report('both') { both.format(nil) }
      benchmark.report('cardinality') { empty.format(:low) }
      benchmark.report('both + cardinality') { both.format(:low) }
    end

    it 'measure IPS' do
      require 'benchmark/ips'

      Benchmark.ips do |x|
        benchmark_setup(x)
        x.compare!
      end
    end

    it 'measure memory' do
      require 'benchmark-memory'

      Benchmark.memory do |x|
        benchmark_setup(x)
        x.compare!
      end
    end
  end
end
