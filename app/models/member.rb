# encoding: UTF-8
# frozen_string_literal: true

require 'securerandom'

class Member < ApplicationRecord
  ROLES = %w[superadmin admin accountant compliance support technical member broker trader]
  ADMIN_ROLES = %w[superadmin admin accountant compliance support technical]

  has_many :orders
  has_many :accounts
  has_many :payment_addresses, through: :accounts
  has_many :withdraws, -> { order(id: :desc) }
  has_many :deposits, -> { order(id: :desc) }
  has_many :beneficiaries, -> { order(id: :desc) }

  scope :enabled, -> { where(state: 'active') }

  before_validation :downcase_email

  validates :uid, length: { maximum: 32 }
  validates :email, presence: true, uniqueness: true, email: true
  validates :level, numericality: { greater_than_or_equal_to: 0 }
  validates :role, inclusion: { in: ROLES }

  after_create :touch_accounts

  attr_readonly :email

  class << self
    def groups
      TradingFee.distinct.pluck(:group)
    end
  end

  def trades
    Trade.where('maker_id = ? OR taker_id = ?', id, id)
  end

  def role
    super&.inquiry
  end

  def admin?
    role == "admin"
  end

  def get_account(model_or_id_or_code)
    accounts.with_currency(model_or_id_or_code).first.yield_self do |account|
      touch_accounts unless account
      accounts.with_currency(model_or_id_or_code).first
    end
  end
  alias :ac :get_account

  def touch_accounts
    Currency.find_each do |currency|
      next if accounts.where(currency: currency).exists?
      accounts.create!(currency: currency)
    end
  end

  def trigger_pusher_event(event, data)
    self.class.trigger_pusher_event(self, event, data)
  end

  def balance_for(currency:, kind:)
    account_code = Operations::Account.find_by(
      type: :liability,
      kind: kind,
      currency_type: currency.type
    ).code
    liabilities = Operations::Liability.where(member_id: id, currency: currency, code: account_code)
    liabilities.sum('credit - debit')
  end

  def legacy_balance_for(currency:, kind:)
    if kind.to_sym == :main
      ac(currency).balance
    elsif kind.to_sym == :locked
      ac(currency).locked
    else
      raise Operations::Exception, "Account for #{options} doesn't exists."
    end
  end

private

  def downcase_email
    self.email = email.try(:downcase)
  end

  class << self
    def uid(member_id)
      Member.find_by(id: member_id).uid
    end

    # Create Member object from payload
    # == Example payload
    # {
    #   :iss=>"barong",
    #   :sub=>"session",
    #   :aud=>["peatio"],
    #   :email=>"admin@barong.io",
    #   :uid=>"U123456789",
    #   :role=>"admin",
    #   :state=>"active",
    #   :level=>"3",
    #   :iat=>1540824073,
    #   :exp=>1540824078,
    #   :jti=>"4f3226e554fa513a"
    # }

    def from_payload(p)
      params = filter_payload(p)
      validate_payload(params)
      member = Member.find_or_create_by(uid: p[:uid], email: p[:email]) do |m|
        m.role = params[:role]
        m.state = params[:state]
        m.level = params[:level]
      end
      member.assign_attributes(params)
      member.save! if member.changed?
      member
    end

    # Filter and validate payload params
    def filter_payload(payload)
      payload.slice(:email, :uid, :role, :state, :level)
    end

    def validate_payload(p)
      fetch_email(p)
      p.fetch(:uid).tap { |uid| raise(Peatio::Auth::Error, 'UID is blank.') if uid.blank? }
      p.fetch(:role).tap { |role| raise(Peatio::Auth::Error, 'Role is blank.') if role.blank? }
      p.fetch(:level).tap { |level| raise(Peatio::Auth::Error, 'Level is blank.') if level.blank? }
      p.fetch(:state).tap do |state|
        raise(Peatio::Auth::Error, 'State is blank.') if state.blank?
        raise(Peatio::Auth::Error, 'State is not active.') unless state == 'active'
      end
    end

    def fetch_email(payload)
      payload[:email].to_s.tap do |email|
        raise(Peatio::Auth::Error, 'E-Mail is blank.') if email.blank?
        raise(Peatio::Auth::Error, 'E-Mail is invalid.') unless EmailValidator.valid?(email)
      end
    end

    def search(field: nil, term: nil)
      case field
      when 'email', 'uid'
        where("members.#{field} LIKE ?", "%#{term}%")
      when 'wallet_address'
        joins(:payment_addresses).where('payment_addresses.address LIKE ?', "%#{term}%")
      else
        all
      end.order(:id).reverse_order
    end

    def trigger_pusher_event(member_or_id, event, data)
      AMQPQueue.enqueue :pusher_member, \
        member_id: self === member_or_id ? member_or_id.id : member_or_id,
        event:     event,
        data:      data
    end
  end
end

# == Schema Information
# Schema version: 20190829035814
#
# Table name: members
#
#  id         :integer          not null, primary key
#  uid        :string(32)       not null
#  email      :string(255)      not null
#  level      :integer          not null
#  role       :string(16)       not null
#  group      :string(32)       default("vip-0"), not null
#  state      :string(16)       not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_members_on_email  (email) UNIQUE
#
