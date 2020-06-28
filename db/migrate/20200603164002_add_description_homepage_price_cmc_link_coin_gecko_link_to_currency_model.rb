class AddDescriptionHomepagePriceCmclinkCoingeckolinkToCurrencyModel < ActiveRecord::Migration[5.2]
  def change
    add_column :currencies, :description, :text, after: :name
    add_column :currencies, :homepage, :string, after: :description
    add_column :currencies, :price, :decimal, precision: 32, scale: 16, after: :icon_url
    add_column :currencies, :cmc_link, :string, after: :price
    add_column :currencies, :coin_gecko_link, :string, after: :cmc_link
  end
end
