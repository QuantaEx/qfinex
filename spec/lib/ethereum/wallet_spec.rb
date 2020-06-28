describe Ethereum::Wallet do
  let(:wallet) { Ethereum::Wallet.new }

  context :configure do
    let(:settings) { { wallet: {}, currency: {} }}
    it 'requires wallet' do
      expect{ wallet.configure(settings.except(:wallet)) }.to raise_error(Peatio::Wallet::MissingSettingError)

      expect{ wallet.configure(settings) }.to_not raise_error
    end

    it 'requires currency' do
      expect{ wallet.configure(settings.except(:currency)) }.to raise_error(Peatio::Wallet::MissingSettingError)

      expect{ wallet.configure(settings) }.to_not raise_error
    end

    it 'sets settings attribute' do
      wallet.configure(settings)
      expect(wallet.settings).to eq(settings.slice(*Ethereum::Wallet::SUPPORTED_SETTINGS))
    end
  end

  context :create_address! do
    around do |example|
      WebMock.disable_net_connect!
      example.run
      WebMock.allow_net_connect!
    end

    let(:uri) { 'http://127.0.0.1:8545' }

    let(:settings) do
      {
        wallet:
          { address: 'something',
            uri:     uri },
        currency: {}
      }
    end

    before do
      PasswordGenerator.stubs(:generate).returns('pass@word')
      wallet.configure(settings)
    end

    it 'request rpc and creates new address' do
      address = '0x6d6cabaa7232d7f45b143b445114f7e92350a2aa'
      stub_request(:post, uri)
        .with(body: { jsonrpc: '2.0',
                      id:     1,
                      method: :personal_newAccount,
                      params:  ['pass@word'] }.to_json)
        .to_return(body: { jsonrpc: '2.0',
                           result: address,
                           id:     1 }.to_json)

      result = wallet.create_address!(uid: 'UID123')
      expect(result.as_json.symbolize_keys).to eq(address: address, secret: 'pass@word')
    end
  end

  context :create_transaction! do
    around do |example|
      WebMock.disable_net_connect!
      example.run
      WebMock.allow_net_connect!
    end

    let(:eth) do
      Currency.find_by(id: :eth)
    end

    let(:trst) do
      Currency.find_by(id: :trst)
    end

    let(:ring) do
      Currency.find_by(id: :ring)
    end

    let(:deposit_wallet_eth) { Wallet.find_by(currency: :eth, kind: :deposit) }
    let(:hot_wallet_eth) { Wallet.find_by(currency: :eth, kind: :hot) }
    let(:fee_wallet) { Wallet.find_by(currency: :eth, kind: :fee) }
    let(:deposit_wallet_trst) { Wallet.find_by(currency: :trst, kind: :deposit) }
    let(:hot_wallet_trst) { Wallet.find_by(currency: :trst, kind: :hot) }

    let(:uri) { 'http://127.0.0.1:8545' }

    let(:transaction) do
      Peatio::Transaction.new(amount: 1.1.to_d, to_address: '0x6d6cabaa7232d7f45b143b445114f7e92350a2aa')
    end

    context 'eth transaction with subtract fees' do

      let(:value) { 1_099_979_000_000_000_000 }

      let(:gas_limit) { 21_000 }
      let(:gas_price) { 1_000_000_000 }

      let(:request_body) do
        { jsonrpc: '2.0',
          id: 1,
          method: :personal_sendTransaction,
          params: [{
            from: deposit_wallet_eth.address.downcase,
            to: '0x6d6cabaa7232d7f45b143b445114f7e92350a2aa',
            value: '0x' + (value.to_s 16),
            gas: '0x' + (gas_limit.to_s 16),
            gasPrice: '0x' + (gas_price.to_s 16)
          }, 'changeme'] }
      end

      let(:settings) do
        {
          wallet: deposit_wallet_eth.to_wallet_api_settings,
          currency: hot_wallet_eth.currency.to_blockchain_api_settings
        }
      end

      before do
        wallet.configure(settings)
      end

      it 'requests rpc and sends transaction' do
        txid = '0xab6ada9608f4cebf799ee8be20fe3fb84b0d08efcdb0d962df45d6fce70cb017'
        stub_request(:post, uri)
          .with(body: request_body.to_json)
          .to_return(body: { result: txid,
                            error:  nil,
                            id:     1 }.to_json)

        result = wallet.create_transaction!(transaction, subtract_fee: true)
        expect(result.as_json.symbolize_keys).to eq(amount: 1.099979.to_s,
                                                    to_address: '0x6d6cabaa7232d7f45b143b445114f7e92350a2aa',
                                                    hash: txid,
                                                    status: 'pending')
      end

      context 'without subtract fees' do

        let(:value) { 1_100_000_000_000_000_000 }

        let(:request_body) do
          { jsonrpc: '2.0',
            id: 1,
            method: :personal_sendTransaction,
            params: [{
              from: deposit_wallet_eth.address.downcase,
              to: '0x6d6cabaa7232d7f45b143b445114f7e92350a2aa',
              value: '0x' + (value.to_s 16),
              gas: '0x' + (gas_limit.to_s 16),
              gasPrice: '0x' + (gas_price.to_s 16)
            }, 'changeme'] }
        end

        it 'requests rpc and sends transaction' do
          txid = '0xab6ada9608f4cebf799ee8be20fe3fb84b0d08efcdb0d962df45d6fce70cb017'
          stub_request(:post, uri)
            .with(body: request_body.to_json)
            .to_return(body: { result: txid,
                              error:  nil,
                              id:     1 }.to_json)

          result = wallet.create_transaction!(transaction)
          expect(result.as_json.symbolize_keys).to eq(amount: 1.1.to_s,
                                                      to_address: '0x6d6cabaa7232d7f45b143b445114f7e92350a2aa',
                                                      hash: txid,
                                                      status: 'pending')
        end
      end

      context 'custom gas_price and subcstract fees' do

        let(:value) { 1_099_370_000_000_000_000 }

        let(:gas_price) { 30_000_000_000 }

        let(:request_body) do
          { jsonrpc: '2.0',
            id: 1,
            method: :personal_sendTransaction,
            params: [{
              from: deposit_wallet_eth.address.downcase,
              to: '0x6d6cabaa7232d7f45b143b445114f7e92350a2aa',
              value: '0x' + (value.to_s 16),
              gas: '0x' + (gas_limit.to_s 16),
              gasPrice: '0x' + (gas_price.to_s 16)
            }, 'changeme'] }
        end

        before do
          settings[:currency][:options] = { gas_price: gas_price }
          wallet.configure(settings)
        end

        it do
          txid = '0xab6ada9608f4cebf799ee8be20fe3fb84b0d08efcdb0d962df45d6fce70cb017'
          stub_request(:post, uri)
            .with(body: request_body.to_json)
            .to_return(body: { result: txid,
                              error:  nil,
                              id:     1 }.to_json)
          result = wallet.create_transaction!(transaction, subtract_fee: true)
          expect(result.as_json.symbolize_keys).to eq(amount: 0.109937e1.to_s,
                                                      to_address: '0x6d6cabaa7232d7f45b143b445114f7e92350a2aa',
                                                      hash: txid,
                                                      status: 'pending')
        end
      end
    end

    context 'erc20 transaction' do

      let(:settings) do
        {
          wallet: deposit_wallet_trst.to_wallet_api_settings,
          currency: hot_wallet_trst.currency.to_blockchain_api_settings
        }
      end

      let(:request_body) do
        { jsonrpc: '2.0',
          id: 1,
          method: :personal_sendTransaction,
          params: [{
            from: deposit_wallet_eth.address.downcase,
            to: trst.options.fetch(:erc20_contract_address),
            data: '0xa9059cbb0000000000000000000000006d6cabaa7232d7f45b143b445114f7e92350a2aa000000000000000000000000000000000000000000000000000000000010c8e0',
            gas: '0x15f90',
            gasPrice: '0x3b9aca00'
          }, 'changeme'] }
      end

      before do
        wallet.configure(settings)
      end

      it do
        txid = '0xab6ada9608f4cebf799ee8be20fe3fb84b0d08efcdb0d962df45d6fce70cb017'
        stub_request(:post, uri)
          .with(body: request_body.to_json)
          .to_return(body: { result: txid,
                             error:  nil,
                             id:     1 }.to_json)
        result = wallet.create_transaction!(transaction)
        expect(result.as_json.symbolize_keys).to eq(amount: 1.1.to_s,
                                                    to_address: '0x6d6cabaa7232d7f45b143b445114f7e92350a2aa',
                                                    hash: txid,
                                                    status: 'pending')
      end
    end

    context :prepare_deposit_collection! do

      let(:value) { '0xa3b5840f4000' }

      let(:request_body) do
        { jsonrpc: '2.0',
          id: 1,
          method: :personal_sendTransaction,
          params: [{
            from: fee_wallet.address.downcase,
            to:   '0x6d6cabaa7232d7f45b143b445114f7e92350a2aa',
            value: value,
            gas: '0x5208',
            gasPrice: '0x3b9aca00'
          }, 'changeme'] }
      end

      let(:spread_deposit) do
      [{ to_address: 'fake-hot',
        amount: '2.0',
        currency_id: trst.id },
       { to_address: 'fake-hot',
        amount: '2.0',
        currency_id: trst.id }]
      end

      let(:settings) do
        {
          wallet: fee_wallet.to_wallet_api_settings,
          currency: fee_wallet.currency.to_blockchain_api_settings
        }
      end

      before do
        wallet.configure(settings)
      end

      it do
        txid = '0xab6ada9608f4cebf799ee8be20fe3fb84b0d08efcdb0d962df45d6fce70cb017'
        stub_request(:post, uri)
          .with(body: request_body.to_json)
          .to_return(body: { result: txid,
                             error:  nil,
                             id:     1 }.to_json)
        result = wallet.prepare_deposit_collection!(transaction, spread_deposit, trst.to_blockchain_api_settings)
        expect(result.first.as_json.symbolize_keys).to eq(amount: '0.00018',
                                                          to_address: '0x6d6cabaa7232d7f45b143b445114f7e92350a2aa',
                                                          hash: txid,
                                                          status: 'pending')
      end
    end
  end

  context :load_balance_of_address! do
    around do |example|
      WebMock.disable_net_connect!
      example.run
      WebMock.allow_net_connect!
    end

    let(:hot_wallet_trst) { Wallet.find_by(currency: :trst, kind: :hot) }
    let(:hot_wallet_eth) { Wallet.find_by(currency: :eth, kind: :hot) }

    let(:response1) do
      {
        jsonrpc: '2.0',
        result: "0x71a5c4e9fe8a100",
        id: 1
      }
    end

    let(:response2) do
      {
        jsonrpc: '2.0',
        result: "0x7a120",
        id: 1
      }
    end

    let(:settings1) do
      {
        wallet:
          { address: 'something',
            uri:     'http://127.0.0.1:8545' },
        currency: hot_wallet_eth.currency.to_blockchain_api_settings
      }
    end

    let(:settings2) do
      {
        wallet:
          { address: 'something',
            uri:     'http://127.0.0.1:8545' },
        currency: hot_wallet_trst.currency.to_blockchain_api_settings
      }
    end

    before do
      stub_request(:post, 'http://127.0.0.1:8545')
        .with(body: { jsonrpc: '2.0',
                      id: 1,
                      method: :eth_getBalance,
                      params:
                        [
                          "something",
                          'latest'
                        ] }.to_json)
        .to_return(body: response1.to_json)

      stub_request(:post, 'http://127.0.0.1:8545')
        .with(body: { jsonrpc: '2.0',
                      id: 1,
                      method: :eth_call,
                      params:
                        [
                          {
                            to:   "0x87099add3bcc0821b5b151307c147215f839a110",
                            data: "0x70a082310000000000000000000000000000000000000000000000000000000something"
                          },
                          'latest'
                        ] }.to_json)
        .to_return(body: response2.to_json)
    end

    it 'requests rpc eth_getBalance and get balance' do
      wallet.configure(settings1)
      result = wallet.load_balance!
      expect(result).to be_a(BigDecimal)
      expect(result).to eq('0.51182300042'.to_d)
    end

    it 'requests rpc eth_call and get token balance' do
      wallet.configure(settings2)
      result = wallet.load_balance!
      expect(result).to be_a(BigDecimal)
      expect(result).to eq('0.5'.to_d)
    end
  end
end
