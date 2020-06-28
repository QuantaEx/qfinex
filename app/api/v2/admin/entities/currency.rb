# enco  ding: UTF-8
# froz  en_string_literal: true

module API
  module V2
    module Admin
      module Entities
        class Currency < API::V2::Entities::Currency
          unexpose(:id)

          expose(
            :code,
            documentation: {
              desc: 'Unique currency code.',
              type: String
            }
          )

          expose(
            :blockchain_key,
            documentation: {
                type: String,
                desc: 'Associated blockchain key which will perform transactions synchronization for currency.'
            },
            if: -> (currency){ currency.coin? }
          )

          expose(
            :min_collection_amount,
            documentation: {
              type: BigDecimal,
              desc: 'Minimal collection amount.'
            }
          )

          expose(
            :position,
            documentation: {
              type: Integer,
              desc: 'Currency position.'
            }
          )

          expose(
            :visible,
            documentation: {
              type: String,
              desc: 'Currency display status (true/false).'
            }
          )

          expose(
            :base_factor,
            documentation: {
              type: Integer,
              desc: 'Currency base factor.'
            }
          )

          expose(
            :subunits,
            documentation: {
              type: Integer,
              desc: 'Fraction of the basic monetary unit.'
            }
          ) { |currency| currency.subunits }

          expose(
            :options,
            documentation: {
              type: JSON,
              desc: 'Currency options.'
            },
            if: -> (currency){ currency.coin? }
          )

          expose(
            :precision,
            documentation: {
              type: Integer,
              desc: 'Currency precision.'
            }
          )
          expose(
            :price,
            documentation: {
            desc: 'Currency current price'
             }
           )
          expose(
            :description,
            documentation: {
            type: String,
            desc: 'Currency description',
              }
            )
          expose(
            :homepage,
            documentation: {
            type: String,
            desc: 'Currency project Homepage',
           }
            )
          expose(
            :cmc_link,
            documentation: {
            type: String,
            desc: 'Currency project Coinmarketcap link',
               }
             )
          expose(
            :coin_gecko_link,
            documentation: {
            type: String,
            desc: 'Currency project CoinGecko link',
               }
             )
          expose(
            :created_at,
            format_with: :iso8601,
            documentation: {
              type: String,
              desc: 'Currency created time in iso8601 format.'
            }
          )
          expose(
            :updated_at,
            format_with: :iso8601,
            documentation: {
              type: String,
              desc: 'Currency updated time in iso8601 format.'
            }
          )
        end
      end
    end
  end
end
