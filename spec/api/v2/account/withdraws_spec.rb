# encoding: UTF-8
# frozen_string_literal: true

describe API::V2::Account::Withdraws, type: :request do
  let(:member) { create(:member, :level_3) }
  let(:token) { jwt_for(member) }
  let(:level_0_member) { create(:member, :level_0) }
  let(:level_0_member_token) { jwt_for(level_0_member) }

  describe 'GET /api/v2/account/withdraws' do
    let!(:btc_withdraws) { create_list(:btc_withdraw, 20, :with_deposit_liability, member: member) }
    let!(:usd_withdraws) { create_list(:usd_withdraw, 20, :with_deposit_liability, member: member) }

    it 'requires authentication' do
      get '/api/v2/account/withdraws'
      expect(response.code).to eq '401'
    end

    it 'validates currency param' do
      api_get '/api/v2/account/withdraws', params: { currency: 'FOO' }, token: token

      expect(response.code).to eq '422'
      expect(response).to include_api_error('account.currency.doesnt_exist')
    end

    it 'validates page param' do
      api_get '/api/v2/account/withdraws', params: { page: -1 }, token: token

      expect(response.code).to eq '422'
      expect(response).to include_api_error('account.withdraw.non_positive_page')
    end

    it 'validates limit param' do
      api_get '/api/v2/account/withdraws', params: { limit: 9999 }, token: token
      expect(response.code).to eq '422'
      expect(response).to include_api_error('account.withdraw.invalid_limit')
    end

    it 'returns withdraws for all currencies by default' do
      api_get '/api/v2/account/withdraws', params: { limit: 100 }, token: token
      result = JSON.parse(response.body)

      expect(response).to be_successful
      expect(response.headers.fetch('Total')).to eq '40'
      expect(result.map { |x| x['currency'] }.uniq.sort).to eq %w[ btc usd ]
    end

    it 'returns withdraws specified currency' do
      api_get '/api/v2/account/withdraws', params: { currency: 'BTC', limit: 100 }, token: token
      result = JSON.parse(response.body)

      expect(response).to be_successful
      expect(response.headers.fetch('Total')).to eq '20'
      expect(result.map { |x| x['currency'] }.uniq.sort).to eq %w[ btc ]
    end


    it 'filters withdraws by multiple states' do
      create(:usd_withdraw, member: member, aasm_state: :rejected)
      api_get '/api/v2/account/withdraws', params: { state: ['canceled', 'rejected'] }, token: token
      result = JSON.parse(response.body)

      expect(result.size).to eq 1

      create(:usd_withdraw, member: member, aasm_state: :canceled)
      api_get '/api/v2/account/withdraws', params: { state: ['canceled', 'rejected'] }, token: token
      result = JSON.parse(response.body)

      expect(result.size).to eq 2
    end

    it 'paginates withdraws' do
      ordered_withdraws = btc_withdraws.sort_by(&:id).reverse

      api_get '/api/v2/account/withdraws', params: { currency: 'BTC', limit: 10, page: 1 }, token: token
      result = JSON.parse(response.body)

      expect(response).to be_successful
      expect(response.headers.fetch('Total')).to eq '20'
      expect(result.first['id']).to eq ordered_withdraws[0].id

      api_get '/api/v2/account/withdraws', params: { currency: 'BTC', limit: 10, page: 2 }, token: token
      result = JSON.parse(response.body)

      expect(response).to be_successful
      expect(response.headers.fetch('Total')).to eq '20'
      expect(result.first['id']).to eq ordered_withdraws[10].id
    end

    it 'sorts withdraws' do
      ordered_withdraws = btc_withdraws.sort_by(&:id).reverse

      api_get '/api/v2/account/withdraws', params: { currency: 'BTC', limit: 100 }, token: token
      expect(response).to be_successful
      result = JSON.parse(response.body)

      expect(result.map { |x| x['id'] }).to eq ordered_withdraws.map(&:id)
    end

    it 'denies access to unverified member' do
      api_get '/api/v2/account/withdraws', token: level_0_member_token
      expect(response.code).to eq '403'
      expect(response).to include_api_error('account.withdraw.not_permitted')
    end
  end

  describe 'create withdraw' do
    let(:currency) { Currency.visible.sample; Currency.find(:usd) }
    let(:amount) { 0.15 }

    let(:beneficiary) do
      create(:beneficiary, member: member, state: :active, currency: currency)
    end

    let :data do
      { uid:            member.uid,
        currency:       currency.code,
        amount:         amount,
        rid:            Faker::Blockchain::Bitcoin.address,
        otp:            123456 }
    end

    let(:account) { member.accounts.with_currency(currency).first }
    let(:balance) { 1.2 }
    let(:long_note) { (0...257).map { (65 + rand(26)).chr }.join }
    before { account.plus_funds(balance) }
    before { Vault::TOTP.stubs(:validate?).returns(true) }

    context 'disabled account withdrawal API' do
      before { ENV['ENABLE_ACCOUNT_WITHDRAWAL_API'] = 'false' }
      after { ENV['ENABLE_ACCOUNT_WITHDRAWAL_API'] = 'true' }
      it 'doesn\'t allow account withdrawal API call' do
        api_post '/api/v2/account/withdraws', params: data, token: token
        expect(response).to have_http_status(422)
        expect(response).to include_api_error('account.withdraw.disabled_api')
      end
    end

    context 'extremely precise values' do
      before { Currency.any_instance.stubs(:withdraw_fee).returns(BigDecimal(0)) }
      before { Currency.any_instance.stubs(:precision).returns(16) }
      it 'keeps precision for amount' do
        data[:amount] = '0.0000000123456789'
        api_post '/api/v2/account/withdraws', params: data, token: token
        expect(response).to have_http_status(201)
        expect(Withdraw.last.sum.to_s).to eq data[:amount]
      end
    end

    it 'validates missing params' do
      data.except!(:otp, :rid, :amount, :currency)
      api_post '/api/v2/account/withdraws', params: data, token: token
      expect(response).to have_http_status(422)
      expect(response).to include_api_error('account.withdraw.missing_otp')
      expect(response).to include_api_error('account.withdraw.missing_rid')
      expect(response).to include_api_error('account.withdraw.missing_amount')
      expect(response).to include_api_error('account.withdraw.missing_currency')

    end

    it 'requires otp' do
      data[:otp] = nil
      api_post '/api/v2/account/withdraws', params: data, token: token
      expect(response).to have_http_status(422)
      expect(response).to include_api_error('account.withdraw.empty_otp')
    end

    it 'validates otp code' do
      Vault::TOTP.stubs(:validate?).returns(false)
      api_post '/api/v2/account/withdraws', params: data, token: token
      expect(response).to have_http_status(422)
      expect(response).to include_api_error('account.withdraw.invalid_otp')
    end

    it 'requires amount' do
      data[:amount] = nil
      api_post '/api/v2/account/withdraws', params: data, token: token
      expect(response).to have_http_status(422)
      expect(response).to include_api_error('account.withdraw.non_positive_amount')
    end

    it 'validates negative amount' do
      data[:amount] = -1
      api_post '/api/v2/account/withdraws', params: data, token: token
      expect(response).to have_http_status(422)
      expect(response).to include_api_error('account.withdraw.non_positive_amount')
    end

    it 'validates enough balance' do
      data[:amount] = 100
      api_post '/api/v2/account/withdraws', params: data, token: token
      expect(response).to have_http_status(422)
      expect(response).to include_api_error('account.withdraw.insufficient_balance')
    end

    it 'validates amount type' do
      data[:amount] = 'one'
      api_post '/api/v2/account/withdraws', params: data, token: token
      expect(response).to have_http_status(422)
      expect(response).to include_api_error('account.withdraw.non_decimal_amount')
    end

    it 'validates amount precision' do
      data[:amount] = 0.123456789123456789
      api_post '/api/v2/account/withdraws', params: data, token: token
      expect(response).to have_http_status(422)
      expect(response).to include_api_error('account.withdraw.invalid_amount')
    end
    
    it 'requires rid' do
      data[:rid] = nil
      api_post '/api/v2/account/withdraws', params: data, token: token
      expect(response).to have_http_status(422)
      expect(response).to include_api_error('account.withdraw.empty_rid')
    end

    it 'requires currency' do
      data[:currency] = nil
      api_post '/api/v2/account/withdraws', params: data, token: token
      expect(response).to have_http_status(422)
      expect(response).to include_api_error('account.currency.doesnt_exist')
    end

    it 'disabled currency' do
      data[:currency] = :eur
      api_post '/api/v2/account/withdraws', params: data, token: token
      expect(response).to have_http_status(422)
      expect(response).to include_api_error('account.currency.doesnt_exist')
    end

    context 'disabled withdrawal for currency' do
      let(:currency) { Currency.find('btc') }

      before { currency.update!(withdrawal_enabled: false) }

      it 'returns error' do
        api_post '/api/v2/account/withdraws', params: data, token: token
        expect(response).to have_http_status 422
        expect(response).to include_api_error('account.currency.withdrawal_disabled')
      end
    end

    it 'creates new withdraw and immediately submits it' do
      api_post '/api/v2/account/withdraws', params: data, token: token

      expect(response).to have_http_status(201)
      record = Withdraw.last
      expect(record.sum).to eq amount
      expect(record.aasm_state).to eq 'submitted'
      expect(record.account).to eq account
      expect(record.account.balance).to eq(1.2 - amount)
      expect(record.account.locked).to eq amount
    end

    it 'creates new withdraw with note' do
      api_post '/api/v2/account/withdraws', params: data.merge(note: 'Test note'), token: token
      expect(response).to have_http_status(201)

      result = JSON.parse(response.body)
      expect(result['note']).to eq 'Test note'

      record = Withdraw.last
      expect(record.note).to eq 'Test note'
    end

    it 'doesnt create new withdraw with too long note' do
      api_post '/api/v2/account/withdraws', params: data.merge(note: long_note), token: token
      expect(response).to have_http_status(422)
      expect(response).to include_api_error('account.withdraw.too_long_note')
    end
  end
end
