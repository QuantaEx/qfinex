# encoding: UTF-8
# frozen_string_literal: true

class OrderBid < Order
  scope :matching_rule, -> { order(price: :desc, created_at: :asc) }

  # @deprecated
  def hold_account
    member.get_account(bid)
  end

  # @deprecated
  def hold_account!
    Account.lock.find_by!(member_id: member_id, currency_id: bid)
  end

  def expect_account
    member.get_account(ask)
  end

  def expect_account!
    Account.lock.find_by!(member_id: member_id, currency_id: ask)
  end

  def avg_price
    return ::Trade::ZERO if funds_received.zero?
    market.round_price(funds_used / funds_received)
  end

  # @deprecated Please use {income/outcome_currency} in Order model
  def currency
    Currency.find(bid)
  end

  def income_currency
    ask_currency
  end

  def outcome_currency
    bid_currency
  end

  LOCKING_BUFFER_FACTOR = '1.1'.to_d
  def compute_locked
    case ord_type
    when 'limit'
      price*volume
    when 'market'
      funds = estimate_required_funds(Global[market_id].asks) {|p, v| p*v }
      # Maximum funds precision defined in Market::FUNDS_PRECISION.
      (funds*LOCKING_BUFFER_FACTOR).round(Market::FUNDS_PRECISION, BigDecimal::ROUND_UP)
    end
  end

end

# == Schema Information
# Schema version: 20190813121822
#
# Table name: orders
#
#  id             :integer          not null, primary key
#  bid            :string(10)       not null
#  ask            :string(10)       not null
#  market_id      :string(20)       not null
#  price          :decimal(32, 16)
#  volume         :decimal(32, 16)  not null
#  origin_volume  :decimal(32, 16)  not null
#  maker_fee      :decimal(17, 16)  default(0.0), not null
#  taker_fee      :decimal(17, 16)  default(0.0), not null
#  state          :integer          not null
#  type           :string(8)        not null
#  member_id      :integer          not null
#  ord_type       :string(30)       not null
#  locked         :decimal(32, 16)  default(0.0), not null
#  origin_locked  :decimal(32, 16)  default(0.0), not null
#  funds_received :decimal(32, 16)  default(0.0)
#  trades_count   :integer          default(0), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#
# Indexes
#
#  index_orders_on_member_id                     (member_id)
#  index_orders_on_state                         (state)
#  index_orders_on_type_and_market_id            (type,market_id)
#  index_orders_on_type_and_member_id            (type,member_id)
#  index_orders_on_type_and_state_and_market_id  (type,state,market_id)
#  index_orders_on_type_and_state_and_member_id  (type,state,member_id)
#  index_orders_on_updated_at                    (updated_at)
#
