# encoding: UTF-8
# frozen_string_literal: true

describe API::V2::Admin::Withdraws, type: :request do
  let(:admin) { create(:member, :admin, :level_3, email: 'example@gmail.com', uid: 'ID73BF61C8H0') }
  let(:token) { jwt_for(admin) }
  let(:level_3_member) { create(:member, :level_3) }
  let(:level_3_member_token) { jwt_for(level_3_member) }
  before do
    [admin, level_3_member].each do |member|
      member.accounts.map { |a| a.update(balance: 500) }
    end

    create(:usd_withdraw, amount: 10.0, sum: 10.0, member: admin)
    create(:usd_withdraw, amount: 9.0, sum: 9.0, member: admin)
    create(:usd_withdraw, amount: 100.0, sum: 100.0, member: level_3_member)
    create(:btc_withdraw, amount: 42.0, sum: 42.0, txid: 'special_txid', member: admin)
    create(:btc_withdraw, amount: 42.0, sum: 42.0, member: admin, aasm_state: :accepted)
    create(:btc_withdraw, amount: 11.0, sum: 11.0, member: level_3_member, aasm_state: :skipped)
    create(:btc_withdraw, amount: 12.0, sum: 12.0, member: level_3_member, aasm_state: :errored)
  end

  describe 'GET /api/v2/admin/withdraws' do
    let(:url) { '/api/v2/admin/withdraws' }

    it 'get all withdraws' do
      api_get url, token: token

      actual = JSON.parse(response.body)
      expected = Withdraw.all

      expect(actual.length).to eq expected.length
      expect(actual.map { |a| a['state'] }).to match_array expected.map(&:aasm_state)
      expect(actual.map { |a| a['id'] }).to match_array expected.map(&:id)
      expect(actual.map { |a| a['currency'] }).to match_array expected.map(&:currency_id)
      expect(actual.map { |a| a['member'] }).to match_array expected.map(&:member_id)
      expect(actual.map { |a| a['type'] }).to match_array(expected.map { |d| d.coin? ? 'coin' : 'fiat' })
      expect(actual.map { |a| a['uid'] }).to match_array(expected.map { |d| d.member.uid })
      expect(actual.map { |a| a['email'] }).to match_array(expected.map { |d| d.member.email })
    end

    context 'ordering' do
      it 'ascending by id' do
        api_get url, token: token, params: { order_by: 'id', ordering: 'asc' }

        actual = JSON.parse(response.body)
        expected = Withdraw.order(id: 'asc')

        expect(actual.map { |a| a['id'] }).to eq expected.map(&:id)
      end

      it 'descending by sum' do
        api_get url, token: token, params: { order_by: 'sum', ordering: 'desc' }

        actual = JSON.parse(response.body)
        expected = Withdraw.order(sum: 'desc')

        expect(actual.map { |a| a['id'] }).to eq expected.map(&:id)
      end
    end

    context 'filtering' do
      it 'by member' do
        api_get url, token: token, params: { uid: level_3_member.uid }

        actual = JSON.parse(response.body)
        expected = Withdraw.where(member_id: level_3_member.id)

        expect(actual.length).to eq expected.length
        expect(actual.map { |a| a['state'] }).to match_array expected.map(&:aasm_state)
        expect(actual.map { |a| a['id'] }).to match_array expected.map(&:id)
        expect(actual.map { |a| a['currency'] }).to match_array expected.map(&:currency_id)
        expect(actual.map { |a| a['member'] }).to all eq level_3_member.id
        expect(actual.map { |a| a['type'] }).to match_array(expected.map { |d| d.coin? ? 'coin' : 'fiat' })
        expect(actual.map { |a| a['uid'] }).to match_array(expected.map { |d| d.member.uid })
        expect(actual.map { |a| a['email'] }).to match_array(expected.map { |d| d.member.email })
      end

      it 'by state' do
        api_get url, token: token, params: { state: :skipped }

        actual = JSON.parse(response.body)
        expected = Withdraw.where(aasm_state: :skipped)

        expect(actual.map { |a| a['state'] }).to all eq 'skipped'
        expect(actual.length).to eq expected.count
        expect(actual.map { |a| a['id'] }).to match_array expected.map(&:id)
        expect(actual.map { |a| a['uid'] }).to match_array(expected.map { |d| d.member.uid })
      end

      it 'by multiple states' do
        api_get url, token: token, params: { state: [:skipped, :accepted] }

        actual = JSON.parse(response.body)
        expected = Withdraw.where(aasm_state: [:skipped, :accepted])

        expect(actual.map { |a| a['state'] }.uniq).to match_array %w[skipped accepted]
        expect(actual.length).to eq expected.count
        expect(actual.map { |a| a['id'] }).to match_array expected.map(&:id)
        expect(actual.map { |a| a['uid'] }).to match_array(expected.map { |d| d.member.uid })
      end

      it 'by type' do
        api_get url, token: token, params: { type: 'coin' }

        actual = JSON.parse(response.body)
        expected = Withdraw.where(type: 'Withdraws::Coin')

        expect(actual.length).to eq expected.length
        expect(actual.map { |a| a['state'] }).to match_array expected.map(&:aasm_state)
        expect(actual.map { |a| a['id'] }).to match_array expected.map(&:id)
        expect(actual.map { |a| a['currency'] }).to match_array expected.map(&:currency_id)
        expect(actual.map { |a| a['member'] }).to match_array expected.map(&:member_id)
        expect(actual.map { |a| a['type'] }).to all eq 'coin'
      end

      it 'by txid' do
        api_get url, token: token, params: { txid: Withdraw.where(type: 'Withdraws::Coin').first.txid }

        actual = JSON.parse(response.body)
        expected = Withdraw.where(type: 'Withdraws::Coin').first

        expect(actual.length).to eq 1
        expect(actual.first['state']).to eq expected.aasm_state
        expect(actual.first['id']).to eq expected.id
        expect(actual.first['currency']).to eq expected.currency_id
        expect(actual.first['member']).to eq expected.member_id
        expect(actual.first['type']).to eq 'coin'
      end
    end
  end

  describe 'GET /api/v2/admin/withdraws/:id' do
    context 'invalid params' do
      context 'non-integer id' do
        it do
          api_get '/api/v2/admin/withdraws/id', token: token
          expect(response).to include_api_error('admin.withdraw.non_integer_id')
        end
      end

      context 'withdraw does not exist' do
        it do
          api_get "/api/v2/admin/withdraws/#{Withdraw.last.id + 1}", token: token
          expect(response).to include_api_error('record.not_found')
        end
      end
    end

  describe 'POST /api/v2/admin/withdraws/actions' do
    let(:url) { '/api/v2/admin/withdraws/actions' }
    let(:fiat) { Withdraw.where(type: 'Withdraws::Fiat').first }
    let(:coin) { Withdraw.where(type: 'Withdraws::Coin').first }

    context 'validates params' do
      it 'does not pass unsupported action' do
        api_post url, token: token, params: { action: 'illegal', id: fiat.id }

        expect(response.status).to eq 422
        expect(response).to include_api_error('admin.withdraw.invalid_action')
      end

      it 'passes supported action for coin' do
        api_post url, token: token, params: { action: 'process', id: coin.id }
        expect(response).not_to include_api_error('admin.withdraw.invalid_action')
      end

      it 'passes supported action for fiat' do
        api_post url, token: token, params: { action: 'reject', id: fiat.id }
        expect(response).not_to include_api_error('admin.withdraw.invalid_action')
      end

      it 'does not pass coin action for fiat' do
        api_post url, token: token, params: { action: 'load', id: fiat.id }

        expect(response.status).to eq 422
        expect(response).to include_api_error('admin.withdraw.cannot_load')
      end
    end

    context 'updates withdraw' do
      before { [coin, fiat].map(&:submit!) }

      it 'accept fiat' do
        api_post url, token: token, params: { action: 'accept', id: fiat.id }
        expect(fiat.reload.aasm_state).to eq('accepted')
        expect(response).to be_successful
      end

      it 'process coin' do
        coin.accept!
        api_post url, token: token, params: { action: 'process', id: coin.id }
        expect(coin.reload.aasm_state).to eq('processing')
      end

      it 'reject fiat' do
        api_post url, token: token, params: { action: 'reject', id: fiat.id }
        expect(fiat.reload.aasm_state).to eq('rejected')
        expect(response).to be_successful
      end

      it 'fail coin' do
        coin.accept!
        coin.process!
        api_post url, token: token, params: { action: 'fail', id: coin.id }
        expect(coin.reload.aasm_state).to eq('failed')
        expect(response).to be_successful
      end

      it 'load coin with txid' do
        coin.accept!
        api_post url, token: token, params: { action: 'load', id: coin.id, txid: 'new_txid' }
        expect(coin.reload.txid).to eq('new_txid')
        expect(coin.aasm_state).to eq('confirming')
        expect(response).to be_successful
      end

      it 'load fiat with txid' do
        fiat.accept!
        expect {
          api_post url, token: token, params: { action: 'load', id: fiat.id, txid: 'new_txid' }
        }.not_to change { fiat }
        expect(response).to include_api_error('admin.withdraw.redundant_txid')
      end

      it 'load coin without txid with txid as param' do
        coin.update(txid: nil)
        coin.accept!
        api_post url, token: token, params: { action: 'load', id: coin.id, txid: 'new_txid' }
        expect(coin.reload.txid).to eq('new_txid')
        expect(coin.aasm_state).to eq('confirming')
        expect(response).to be_successful
      end

      it 'load coin without txid' do
        coin.update(txid: nil)
        coin.accept!
        expect {
          api_post url, token: token, params: { action: 'load', id: coin.id }
        }.not_to change { coin }
        expect(response).to include_api_error('admin.withdraw.cannot_load')
      end
    end
  end
end
