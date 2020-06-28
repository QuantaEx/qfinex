# encoding: UTF-8
# frozen_string_literal: true

class FakeBlockchain < Peatio::Blockchain::Abstract
  def initialize
    @features = {cash_addr_format: false, case_sensitive: true}
  end

  def configure(settings = {}); end
end

class FakeWallet < Peatio::Wallet::Abstract
  def initialize; end

  def configure(settings = {}); end
end

Peatio::Blockchain.registry[:fake] = FakeBlockchain.new
Peatio::Wallet.registry[:fake] = FakeWallet.new

describe WalletService do
  let!(:blockchain) { create(:blockchain, 'fake-testnet') }
  let!(:currency) { create(:currency, :fake) }
  let(:wallet) { create(:wallet, :fake_hot) }

  let(:fake_wallet_adapter) { FakeWallet.new }
  let(:fake_blockchain_adapter) { FakeBlockchain.new }

  let(:service) { WalletService.new(wallet) }

  before do
    Peatio::Blockchain.registry.expects(:[])
                         .with(:fake)
                         .returns(fake_blockchain_adapter)
                         .at_least_once

    Peatio::Wallet.registry.expects(:[])
                     .with(:fake)
                     .returns(fake_wallet_adapter)
                     .at_least_once

    Blockchain.any_instance.stubs(:blockchain_api).returns(BlockchainService.new(blockchain))
  end

  context :create_address! do
    let(:account) { create(:member, :level_3, :barong).ac(currency)  }
    let(:blockchain_address) do
      { address: :fake_address,
        secret: :changeme,
        details: { uid: account.member.uid } }
    end

    before do
      fake_wallet_adapter.expects(:create_address!).returns(blockchain_address)
    end

    it 'creates address' do
      expect(service.create_address!(account)).to eq blockchain_address
    end
  end

  context :build_withdrawal! do
    let(:withdrawal) { OpenStruct.new(rid: 'fake-address', amount: 100) }

    let(:transaction) do
      Peatio::Transaction.new(hash:        '0xfake',
                              to_address:  withdrawal.rid,
                              amount:      withdrawal.amount,
                              currency_id: currency.id)
    end

    before do
      fake_wallet_adapter.expects(:create_transaction!).returns(transaction)
    end

    it 'sends withdrawal' do
      expect(service.build_withdrawal!(withdrawal)).to eq transaction
    end
  end

  context :spread_between_wallets do

    # Single wallet:
    #   * Deposit fits exactly.
    #   * Deposit doesn't fit.
    # Two wallets:
    #   * Deposit fits to first wallet.
    #   * Deposit fits to second wallet.
    #   * Partial spread between first and second.
    #   * Deposit doesn't fit to both wallets.
    #   * Negative min_collection_amount.
    # Three wallets:
    #   * Partial spread between first and second.
    #   * Partial spread between first and third.
    #   * Partial spread between first, second and third.
    #   * Deposit doesn't fit to all wallets.

    let(:amount) { 1.2 }

    context 'Single wallet' do

      context 'single wallet available' do

        let(:destination_wallets) do
          [{ address: 'destination-wallet-1',
            balance: 8.8,
            max_balance: 10,
            min_collection_amount: 1 }]
        end

        let(:expected_spread) do
          [{ to_address: 'destination-wallet-1',
             status: 'pending',
             amount: amount,
             currency_id: currency.id }]
        end

        subject { service.send(:spread_between_wallets, amount, destination_wallets) }

        it 'spreads everything to single wallet' do
          expect(subject.map(&:as_json).map(&:symbolize_keys)).to contain_exactly(*expected_spread)
          expect(subject).to all(be_a(Peatio::Transaction))
        end
      end

      context 'Single wallet is full' do

        let(:destination_wallets) do
          [{ address: 'destination-wallet-1',
            balance: 10,
            max_balance: 10,
            min_collection_amount: 1 }]
        end

        let(:expected_spread) do
          [{ to_address: 'destination-wallet-1',
             status: 'pending',
             amount: amount,
             currency_id: currency.id }]
        end

        subject { service.send(:spread_between_wallets, amount, destination_wallets) }

        it 'spreads everything to last wallet' do
          expect(subject.map(&:as_json).map(&:symbolize_keys)).to contain_exactly(*expected_spread)
          expect(subject).to all(be_a(Peatio::Transaction))
        end
      end
    end

    context 'Two wallets' do

      context 'Deposit fits to first wallet' do

        let(:destination_wallets) do
          [{ address: 'destination-wallet-1',
            balance: 5,
            max_balance: 10,
            min_collection_amount: 1 },
          { address: 'destination-wallet-2',
            balance: 100.0,
            max_balance: 100,
            min_collection_amount: 1 }]
        end

        let(:expected_spread) do
          [{ to_address: 'destination-wallet-1',
             status: 'pending',
             amount: amount,
             currency_id: currency.id }]
        end

        subject { service.send(:spread_between_wallets, amount, destination_wallets) }

        it 'spreads everything to last wallet' do
          expect(subject.map(&:as_json).map(&:symbolize_keys)).to contain_exactly(*expected_spread)
          expect(subject).to all(be_a(Peatio::Transaction))
        end
      end

      context 'Deposit fits to second wallet' do

        let(:destination_wallets) do
          [{ address: 'destination-wallet-1',
            balance: 10,
            max_balance: 10,
            min_collection_amount: 1 },
          { address: 'destination-wallet-2',
            balance: 95,
            max_balance: 100,
            min_collection_amount: 1 }]
        end

        let(:expected_spread) do
          [{ to_address: 'destination-wallet-2',
             status: 'pending',
             amount: amount,
             currency_id: currency.id }]
        end

        subject { service.send(:spread_between_wallets, amount, destination_wallets) }

        it 'spreads everything to last wallet' do
          expect(subject.map(&:as_json).map(&:symbolize_keys)).to contain_exactly(*expected_spread)
          expect(subject).to all(be_a(Peatio::Transaction))
        end
      end

      context 'Partial spread between first and second' do

        let(:amount) { 10 }

        let(:destination_wallets) do
          [{ address: 'destination-wallet-1',
            balance: 5,
            max_balance: 10,
            min_collection_amount: 1 },
          { address: 'destination-wallet-2',
            balance: 90,
            max_balance: 100,
            min_collection_amount: 1 }]
        end

        let(:expected_spread) do
          [{ to_address: 'destination-wallet-1',
             status: 'pending',
             amount: 5,
             currency_id: currency.id },
           { to_address: 'destination-wallet-2',
             status: 'pending',
             amount: 5,
             currency_id: currency.id }]
        end

        subject { service.send(:spread_between_wallets, amount, destination_wallets) }

        it 'spreads everything to last wallet' do
          expect(subject.map(&:as_json).map(&:symbolize_keys)).to contain_exactly(*expected_spread)
          expect(subject).to all(be_a(Peatio::Transaction))
        end
      end

      context 'Two wallets are full' do
        let(:destination_wallets) do
          [{ address: 'destination-wallet-1',
            balance: 10,
            max_balance: 10,
            min_collection_amount: 1 },
          { address: 'destination-wallet-2',
            balance: 100,
            max_balance: 100,
            min_collection_amount: 1 }]
        end

        let(:expected_spread) do
          [{ to_address: 'destination-wallet-2',
             status: 'pending',
             amount: 1.2,
             currency_id: currency.id }]
        end

        subject { service.send(:spread_between_wallets, amount, destination_wallets) }

        it 'spreads everything to last wallet' do
          expect(subject.map(&:as_json).map(&:symbolize_keys)).to contain_exactly(*expected_spread)
          expect(subject).to all(be_a(Peatio::Transaction))
        end
      end

      context 'different min_collection_amount' do

        let(:destination_wallets) do
          [{ address: 'destination-wallet-1',
            balance: 10,
            max_balance: 10,
            min_collection_amount: 1 },
           { address: 'destination-wallet-2',
            balance: 100,
            max_balance: 100,
            min_collection_amount: 2 }]
        end

        let(:expected_spread) do
          [{ to_address: 'destination-wallet-2',
             status: 'pending',
             amount: 1.2,
             currency_id: currency.id }]
        end

        subject { service.send(:spread_between_wallets, amount, destination_wallets) }

        it 'spreads everything to single wallet' do
          expect(subject.map(&:as_json).map(&:symbolize_keys)).to contain_exactly(*expected_spread)
          expect(subject).to all(be_a(Peatio::Transaction))
        end
      end

      context 'tiny min_collection_amount' do

        let(:destination_wallets) do
          [{ address: 'destination-wallet-1',
             balance: 10,
             max_balance: 10,
             min_collection_amount: 2 },
           { address: 'destination-wallet-2',
             balance: 100,
             max_balance: 100,
             min_collection_amount: 3 }]
        end

        let(:expected_spread) { [] }

        subject { service.send(:spread_between_wallets, amount, destination_wallets) }

        it 'spreads everything to single wallet' do
          expect(subject.map(&:as_json).map(&:symbolize_keys)).to contain_exactly(*expected_spread)
          expect(subject).to all(be_a(Peatio::Transaction))
        end
      end
    end

    context 'Three wallets' do

      context 'Partial spread between first and second' do

        let(:amount) { 10 }

        let(:destination_wallets) do
          [{ address: 'destination-wallet-1',
            balance: 5,
            max_balance: 10,
            min_collection_amount: 1 },
          { address: 'destination-wallet-2',
            balance: 95,
            max_balance: 100,
            min_collection_amount: 1 },
          { address: 'destination-wallet-3',
            balance: 1001.0,
            max_balance: 1000,
            min_collection_amount: 1 }]
        end

        let(:expected_spread) do
          [{ to_address: 'destination-wallet-1',
             status: 'pending',
             amount: 5,
             currency_id: currency.id },
           { to_address: 'destination-wallet-2',
             status: 'pending',
             amount: 5,
             currency_id: currency.id}]
        end

        subject { service.send(:spread_between_wallets, amount, destination_wallets) }

        it 'spreads everything to last wallet' do
          expect(subject.map(&:as_json).map(&:symbolize_keys)).to contain_exactly(*expected_spread)
          expect(subject).to all(be_a(Peatio::Transaction))
        end
      end

      context 'Partial spread between first and third' do

        let(:amount) { 10 }

        let(:destination_wallets) do
          [{ address: 'destination-wallet-1',
            balance: 5,
            max_balance: 10,
            min_collection_amount: 1 },
          { address: 'destination-wallet-2',
            balance: 100,
            max_balance: 100,
            min_collection_amount: 1 },
          { address: 'destination-wallet-3',
            balance: 995.0,
            max_balance: 1000,
            min_collection_amount: 1 }]
        end

        let(:expected_spread) do
          [{ to_address: 'destination-wallet-1',
             status: 'pending',
             amount: 5,
             currency_id: currency.id },
           { to_address: 'destination-wallet-3',
             status: 'pending',
             amount: 5,
             currency_id: currency.id}]
        end

        subject { service.send(:spread_between_wallets, amount, destination_wallets) }

        it 'spreads everything to last wallet' do
          expect(subject.map(&:as_json).map(&:symbolize_keys)).to contain_exactly(*expected_spread)
          expect(subject).to all(be_a(Peatio::Transaction))
        end
      end

      context 'Three wallets are full' do

        let(:destination_wallets) do
          [{ address: 'destination-wallet-1',
            balance: 10.1,
            max_balance: 10,
            min_collection_amount: 1 },
          { address: 'destination-wallet-2',
            balance: 100.0,
            max_balance: 100,
            min_collection_amount: 1 },
          { address: 'destination-wallet-3',
            balance: 1001.0,
            max_balance: 1000,
            min_collection_amount: 1 }]
        end

        let(:expected_spread) do
          [{ to_address: 'destination-wallet-3',
             status: 'pending',
             amount: amount,
             currency_id: currency.id }]
        end

        subject { service.send(:spread_between_wallets, amount, destination_wallets) }

        it 'spreads everything to last wallet' do
          expect(subject.map(&:as_json).map(&:symbolize_keys)).to contain_exactly(*expected_spread)
          expect(subject).to all(be_a(Peatio::Transaction))
        end
      end

      context 'Partial spread between first, second and third' do

        let(:amount) { 10 }

        let(:destination_wallets) do
          [{ address: 'destination-wallet-1',
            balance: 7,
            max_balance: 10,
            min_collection_amount: 1 },
          { address: 'destination-wallet-2',
            balance: 97,
            max_balance: 100,
            min_collection_amount: 1 },
          { address: 'destination-wallet-3',
            balance: 995.0,
            max_balance: 1000,
            min_collection_amount: 1 }]
        end

        let(:expected_spread) do
          [{ to_address: 'destination-wallet-1',
             status: 'pending',
             amount: 3,
             currency_id: currency.id },
           { to_address: 'destination-wallet-2',
             status: 'pending',
             amount: 3,
             currency_id: currency.id },
           { to_address: 'destination-wallet-3',
             status: 'pending',
             amount: 4,
             currency_id: currency.id}]
        end

        subject { service.send(:spread_between_wallets, amount, destination_wallets) }

        it 'spreads everything to last wallet' do
          expect(subject.map(&:as_json).map(&:symbolize_keys)).to contain_exactly(*expected_spread)
          expect(subject).to all(be_a(Peatio::Transaction))
        end
      end
    end
  end

  context :spread_deposit do
    let!(:deposit_wallet) { create(:wallet, :fake_deposit) }
    let!(:hot_wallet) { create(:wallet, :fake_hot) }
    let!(:cold_wallet) { create(:wallet, :fake_cold) }

    let(:service) { WalletService.new(deposit_wallet) }

    let(:amount) { 2 }
    let(:deposit) { create(:deposit_btc, amount: amount, currency: currency) }

    let(:expected_spread) do
      [{ to_address: 'fake-cold',
         status: 'pending',
         amount: '2.0',
         currency_id: currency.id }]
    end

    subject { service.spread_deposit(deposit) }

    context 'hot wallet is full and cold wallet balance is not available' do
      before do
        # Hot wallet balance is full and cold wallet balance is not available.
        Wallet.any_instance.stubs(:current_balance).returns(hot_wallet.max_balance, 'N/A')
      end

      it 'spreads everything to cold wallet' do
        expect(Wallet.active.withdraw.where(currency_id: deposit.currency_id).count).to eq 2

        expect(subject.map(&:as_json).map(&:symbolize_keys)).to contain_exactly(*expected_spread)
        expect(subject).to all(be_a(Peatio::Transaction))
      end
    end

    context 'hot wallet is full, warm and cold wallet balances are not available' do
      let!(:warm_wallet) { create(:wallet, :fake_warm) }
      before do
        # Hot wallet is full, warm and cold wallet balances are not available.
        Wallet.any_instance.stubs(:current_balance).returns(hot_wallet.max_balance, 'N/A', 'N/A')
      end

      it 'skips warm wallet and spreads everything to cold wallet' do
        expect(Wallet.active.withdraw.where(currency_id: deposit.currency_id).count).to eq 3

        expect(subject.map(&:as_json).map(&:symbolize_keys)).to contain_exactly(*expected_spread)
        expect(subject).to all(be_a(Peatio::Transaction))
      end
    end

    context 'there is no active wallets' do
      before { Wallet.stubs(:active).returns(Wallet.none) }

      it 'raises an error' do
        expect{ subject }.to raise_error(StandardError)
      end
    end
  end

  context :collect_deposit do
    let!(:deposit_wallet) { create(:wallet, :fake_deposit) }
    let!(:hot_wallet) { create(:wallet, :fake_hot) }
    let!(:cold_wallet) { create(:wallet, :fake_cold) }

    let(:amount) { 2 }
    let(:deposit) { create(:deposit_btc, amount: amount, currency: currency) }

    let(:fake_wallet_adapter) { FakeWallet.new }
    let(:service) { WalletService.new(deposit_wallet) }

    context 'Spread deposit with single entry' do

      let(:spread_deposit) do [{ to_address: 'fake-cold',
                              amount: '2.0',
                              currency_id: currency.id }]
      end

      let(:transaction) do
        [Peatio::Transaction.new(hash:        '0xfake',
                                to_address:  cold_wallet.address,
                                amount:      deposit.amount,
                                currency_id: currency.id)]
      end

      subject { service.collect_deposit!(deposit, spread_deposit) }

      before do
        fake_wallet_adapter.expects(:create_transaction!).returns(transaction.first)
      end

      it 'creates single transaction' do
        expect(subject).to contain_exactly(*transaction)
        expect(subject).to all(be_a(Peatio::Transaction))
      end
    end

    context 'Spread deposit with two entry' do

      let(:spread_deposit) do [{ to_address: 'fake-hot',
                                 amount: '2.0',
                                 currency_id: currency.id },
                               { to_address: 'fake-hot',
                                 amount: '2.0',
                                 currency_id: currency.id }]
      end

      let(:transaction) do
        [{ hash:        '0xfake',
           to_address:  hot_wallet.address,
           amount:      deposit.amount,
           currency_id: currency.id },
         { hash:        '0xfake',
           to_address:  cold_wallet.address,
           amount:      deposit.amount,
           currency_id: currency.id }].map { |t| Peatio::Transaction.new(t)}
      end

      subject { service.collect_deposit!(deposit, spread_deposit) }

      before do
        fake_wallet_adapter.expects(:create_transaction!).with(spread_deposit.first, subtract_fee: true).returns(transaction.first)
        fake_wallet_adapter.expects(:create_transaction!).with(spread_deposit.second, subtract_fee: true).returns(transaction.second)
      end

      it 'creates two transactions' do
        expect(subject).to contain_exactly(*transaction)
        expect(subject).to all(be_a(Peatio::Transaction))
      end
    end
  end

  context :deposit_collection_fees do
    let!(:fee_wallet) { create(:wallet, :fake_fee) }
    let!(:deposit_wallet) { create(:wallet, :fake_deposit) }

    let(:amount) { 2 }
    let(:deposit) { create(:deposit_btc, amount: amount, currency: currency) }

    let(:fake_wallet_adapter) { FakeWallet.new }
    let(:service) { WalletService.new(fee_wallet) }

    let(:spread_deposit) do [{ to_address: 'fake-cold',
      amount: '2.0',
      currency_id: currency.id }]
    end

    let(:transactions) do
      [Peatio::Transaction.new( hash:        '0xfake',
                                to_address:  deposit.address,
                                amount:      '0.01',
                                currency_id: currency.id)]
    end

    subject { service.deposit_collection_fees!(deposit, spread_deposit) }

    context 'Adapter collect fees for transaction' do
      before do
        fake_wallet_adapter.expects(:prepare_deposit_collection!).returns(transactions)
      end

      it 'returns transaction' do
        expect(subject).to contain_exactly(*transactions)
        expect(subject).to all(be_a(Peatio::Transaction))
      end
    end

    context "Adapter doesn't perform any actions before collect deposit" do

      it 'retunrs empty array' do
        expect(subject.blank?).to be true
      end
    end
  end
end
