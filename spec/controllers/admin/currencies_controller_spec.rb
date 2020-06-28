# encoding: UTF-8
# frozen_string_literal: true

describe Admin::CurrenciesController, type: :controller do
  before(:each) { inject_authorization!(member) }
  let(:member) { create(:admin_member) }
  let :attributes do
    { code:                             'nbn',
      blockchain_key:                   Blockchain.first.key,
      type:                             'coin',
      symbol:                           'N',
      withdraw_limit_24h:               '1.5'.to_d,
      withdraw_limit_72h:               '2.5'.to_d,
      withdraw_fee:                     '0.001'.to_d,
      position:                         '10'.to_i,
      deposit_fee:                      '0.0'.to_d,
      visible:                          true,
      base_factor:                      1000000,
      precision:                        8,
      options:                          { "erc20_contract_address" => '1fmiowizbqnrkhzrn4vvsmqacc5gvk9sf3' }
    }

  end

  let(:existing_currency) { Currency.first }

  before { session[:member_id] = member.id }

  describe '#create' do
    it 'creates market with valid attributes' do
      expect do
        post :create, params: { currency: attributes }
        expect(response).to redirect_to admin_currencies_path
      end.to change(Currency, :count)
      currency = Currency.find(:nbn)
      attributes.each { |k, v| expect(currency.method(k).call).to eq v }
    end
  end

  describe '#update' do
    let :new_attributes do
      { code:                             'mkd',
        type:                             'fiat',
        symbol:                           'X',
        withdraw_limit_24h:               '2.5'.to_d,
        withdraw_limit_72h:               '3.5'.to_d,
        withdraw_fee:                     '0.006'.to_d,
        deposit_fee:                      '0.05'.to_d,
        visible:                          false,
        base_factor:                      100000,
        precision:                        9,
        options:                          { "erc20_contract_address" => '12kamv8qxvqyosgzitfym6yzxk2sgovhq9', \
                                            "custom_token_id" => "12kamv8qxvqyosgzitfym6yzxk2sgovhq9" }
      }

    end

    let :final_attributes do
      new_attributes.merge(deposit_fee: '0.0'.to_d).merge \
        attributes.slice \
          :code,
          :type,
          :base_factor,
          :precision,
          :erc20_contract_address,
          :custom_token_id
    end

    before { request.env['HTTP_REFERER'] = '/admin/currencies' }

    it 'updates currency attributes' do
      post :create, params: { currency: attributes }
      currency = Currency.find(:nbn)
      attributes.each { |k, v| expect(currency.method(k).call).to eq v }
      post :update, params: { currency: new_attributes, id: currency.id }
      expect(response).to redirect_to admin_currencies_path
      currency.reload
      final_attributes.each { |k, v| expect(currency.method(k).call).to eq v }
    end
  end

  describe '#destroy' do
    it 'doesn\'t support deletion of currencies' do
      expect { delete :destroy, params: { id: existing_currency.id } }.to raise_error(ActionController::UrlGenerationError)
    end
  end

  describe 'routes' do
    let(:base_route) { '/admin/currencies' }
    it 'routes to CurrenciesController' do
      expect(get: base_route).to be_routable
      expect(post: base_route).to be_routable
      expect(get: "#{base_route}/new").to be_routable
      expect(get: "#{base_route}/#{existing_currency.id}").to be_routable
      expect(put: "#{base_route}/#{existing_currency.id}").to be_routable
    end

    it 'doesn\'t routes to CurrenciesController' do
      expect(delete: "#{base_route}/#{existing_currency.id}").to_not be_routable
    end
  end
end
