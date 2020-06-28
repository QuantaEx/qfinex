# encoding: UTF-8
# frozen_string_literal: true

module API
  module V2
    module Admin
      module Entities
        class Withdraw < API::V2::Entities::Withdraw
          expose(
            :member_id,
            as: :member,
            documentation: {
              type: String,
              desc: 'The member id.'
            }
          )

         expose(
            :uid,
            documentation: {
              type: String,
              desc: 'The withdrawal member uid.'
            }
          ) { |w| w.member.uid }

          expose(
            :email,
            documentation: {
              type: String,
              desc: 'The withdrawal member email.'
            }
          ) { |w| w.member.email }

          expose(
            :account_id,
            as: :account,
            documentation: {
              type: String,
              desc: 'The account code.'
            }
          )

          expose(
            :block_number,
            documentation: {
              type: Integer,
              desc: 'The withdrawal block_number.'
            },
            if: ->(w) { w.coin? }
          )

          expose(
            :amount,
            documentation: {
              type: BigDecimal,
              desc: 'The withdrawal amount.'
            }
          )

          expose(
            :sum,
            documentation: {
              type: BigDecimal,
              desc: 'The withdrawal sum.'
            }
          )

          expose(
            :tid,
            documentation: {
              type: String,
              desc: 'Withdraw tid.'
            }
          )

          expose(
            :note,
            documentation: {
              type: String,
              desc: 'Withdraw note.'
            }
          )

          expose(
            :completed_at,
            format_with: :iso8601,
            documentation: {
              type: String,
              desc: 'The datetime when withdraw was completed.'
            },
            if: ->(w) { w.completed? }
          )
        end
      end
    end
  end
end
