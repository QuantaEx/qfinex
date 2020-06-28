class WalletService
  attr_reader :wallet, :adapter

  def initialize(wallet)
    @wallet = wallet
    @adapter = Peatio::Wallet.registry[wallet.gateway.to_sym]
    @adapter.configure(wallet: @wallet.to_wallet_api_settings,
                       currency: @wallet.currency.to_blockchain_api_settings)
  end

  def create_address!(account)
    @adapter.create_address!(uid: account.member.uid)
  end

  def build_withdrawal!(withdrawal)
    transaction = Peatio::Transaction.new(to_address: withdrawal.rid,
                                          amount:     withdrawal.amount)
    @adapter.create_transaction!(transaction)
  end

  def spread_deposit(deposit)
    destination_wallets =
      Wallet.active.withdraw.ordered
        .where(currency_id: deposit.currency_id)
        .map do |w|
        # NOTE: Consider min_collection_amount is defined per wallet.
        #       For now min_collection_amount is currency config.
        { address:               w.address,
          balance:               w.current_balance,
          max_balance:           w.max_balance,
          min_collection_amount: @wallet.currency.min_collection_amount }
      end
    raise StandardError, "destination wallets don't exist" if destination_wallets.blank?

    # Since last wallet is considered to be the most secure we need always
    # have it in spread even if we don't know the balance.
    # All money which doesn't fit to other wallets will be collected to cold.
    # That is why cold wallet balance is considered to be 0 because there is no
    destination_wallets.last[:balance] = 0

    # Remove all wallets not available current balance
    # (except the last one see previous comment).
    destination_wallets.reject! { |dw| dw[:balance] == Wallet::NOT_AVAILABLE }

    spread_between_wallets(deposit.amount, destination_wallets)
  end

  # TODO: We don't need deposit_spread anymore.
  def collect_deposit!(deposit, deposit_spread)
    pa = deposit.account.payment_address
    # NOTE: Deposit wallet configuration is tricky because wallet UIR
    #       is saved on Wallet model but wallet address and secret
    #       are saved in PaymentAddress.
    @adapter.configure(
      wallet: @wallet.to_wallet_api_settings
                     .merge(address: pa.address, secret: pa.secret)
                     .compact
    )

    deposit_spread.map { |t| @adapter.create_transaction!(t, subtract_fee: true) }
  end

  # TODO: We don't need deposit_spread anymore.
  def deposit_collection_fees!(deposit, deposit_spread)
    deposit_transaction = Peatio::Transaction.new(hash:         deposit.txid,
                                                  txout:        deposit.txout,
                                                  to_address:   deposit.address,
                                                  block_number: deposit.block_number,
                                                  amount:       deposit.amount,
                                                  currency_id:  deposit.currency_id)

    @adapter.prepare_deposit_collection!(deposit_transaction,
                                         deposit_spread,
                                         deposit.currency.to_blockchain_api_settings)
  end

  def load_balance!
    @adapter.load_balance!
  rescue Peatio::Wallet::Error => e
    report_exception(e)
    BlockchainService.new(wallet.blockchain).load_balance!(@wallet.address, @wallet.currency_id)
  end

  private

  # @return [Array<Peatio::Transaction>] result of spread in form of
  # transactions array with amount and to_address defined.
  def spread_between_wallets(original_amount, destination_wallets)
    if original_amount < destination_wallets.pluck(:min_collection_amount).min
      return []
    end

    left_amount = original_amount

    spread = destination_wallets.map do |dw|
      amount_for_wallet = [dw[:max_balance] - dw[:balance], left_amount].min

      # If free amount in current wallet is too small,
      # we will not able to collect it.
      # Put 0 for this wallet.
      if amount_for_wallet < [dw[:min_collection_amount], 0].max
        amount_for_wallet = 0
      end

      left_amount -= amount_for_wallet

      # If amount left is too small we will not able to collect it.
      # So we collect everything to current wallet.
      if left_amount < dw[:min_collection_amount]
        amount_for_wallet += left_amount
        left_amount = 0
      end

      Peatio::Transaction.new(to_address:   dw[:address],
                              amount:       amount_for_wallet,
                              currency_id:  @wallet.currency_id)
    rescue => e
      # If have exception skip wallet.
      report_exception(e)
    end

    if left_amount > 0
      # If deposit doesn't fit to any wallet, collect it to the last one.
      # Since the last wallet is considered to be the most secure.
      spread.last.amount += left_amount
      left_amount = 0
    end

    # Remove zero transactions from spread.
    spread.filter { |t| t.amount > 0 }.tap do |sp|
      unless sp.map(&:amount).sum == original_amount
        raise Error, "Deposit spread failed deposit.amount != collection_spread.values.sum"
      end
    end
  end
end
