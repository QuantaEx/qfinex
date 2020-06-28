# encoding: UTF-8
# frozen_string_literal: true

describe PaymentAddress do
  context '.create' do
    let(:member)  { create(:member, :level_3) }
    let!(:account) { member.get_account(:btc) }
    let(:secret) { 's3cr3t' }
    let(:details) { { 'a' => 'b', 'b' => 'c' } }
    let!(:addr) { create(:payment_address, :btc_address, secret: secret) }

    it 'generate address after commit' do
      AMQPQueue.expects(:enqueue)
               .with(:deposit_coin_address, { account_id: account.id }, { persistent: true })
      account.payment_address
    end

    it 'updates secret' do
      expect {
        addr.update(secret: 'new_secret')
      }.to change { addr.reload.secret_encrypted }.and change { addr.reload.secret }.to 'new_secret'
    end

    it 'updates details' do
      expect {
        addr.update(details: details)
      }.to change { addr.reload.details_encrypted }.and change { addr.reload.details }.to details
    end

    it 'long secret' do
      expect {
        addr.update(secret: Faker::String.random(1024))
      }.to raise_error ActiveRecord::ValueTooLong
    end

    it 'long details' do
      expect {
        addr.update(details: { test: Faker::String.random(1024) })
      }.to raise_error ActiveRecord::ValueTooLong
    end
  end
end
