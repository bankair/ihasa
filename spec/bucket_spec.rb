require 'spec_helper'
require 'ihasa'

describe Ihasa::Bucket do
  let(:redis) { Ihasa.default_redis }
  before(:each) { redis.keys.tap { |keys| redis.del(keys) unless keys.empty? } }

  it { expect { Ihasa.bucket }.not_to raise_error }
  it { expect { Ihasa.bucket }.to change {redis.keys.size}.from(0).to(4) }

  context 'with a namespaced bucket' do
    let!(:bucket) { Ihasa.bucket(prefix: 'FOOBAR') }
    CUSTOM_KEYS = %w(FOOBAR:RATE FOOBAR:BURST FOOBAR:ALLOWANCE FOOBAR:LAST)
    it { expect(redis.keys()).to match_array(CUSTOM_KEYS) }
  end

  context 'with a standard bucket' do
    let!(:bucket) { Ihasa.bucket }
    STANDARD_KEYS = %w(IHAB:RATE IHAB:BURST IHAB:ALLOWANCE IHAB:LAST)
    it { expect(redis.keys()).to match_array(STANDARD_KEYS) }

    describe '#accept?' do
      it { expect(bucket.accept?).to eq true }
      it 'sustain burst' do
        10.times { expect(bucket.accept?).to eq true }
      end
      it 'no longer reponsd true once the burst limit is crossed' do
        10.times { expect(bucket.accept?).to eq true }
        100.times { expect(bucket.accept?).to eq false }
      end
      it 'regenerate its allowance over time' do
        skip "Slow integration test"
        10.times { expect(bucket.accept?).to eq true }
        10.times { expect(bucket.accept?).to eq false }
        sleep 2.1
        10.times { expect(bucket.accept?).to eq true }
        10.times { expect(bucket.accept?).to eq false }
        sleep 1.1
        5.times { expect(bucket.accept?).to eq true }
        sleep 1
        5.times { expect(bucket.accept?).to eq true }
        sleep 1
        5.times { expect(bucket.accept?).to eq true }
      end

      it 'execute the given block only when the burst limit is not met' do
        count = 0
        10.times { |i| expect(bucket.accept? { count += 1 }).to eq(1 + i) }
        expect(count).to eq 10
        10.times { bucket.accept? { count += 1 } }
        expect(count).to eq 10
      end
    end
    describe '#accept?!' do
      it { expect(bucket.accept!).to eq true }
      it 'sustain burst' do
        10.times { expect(bucket.accept!).to eq true }
      end
      it 'no longer reponsd true once the burst limit is crossed' do
        10.times { expect(bucket.accept!).to eq true }
        expect{bucket.accept!}.to raise_error(/Bucket IHAB throttle limit/)
      end
    end

  end

end
