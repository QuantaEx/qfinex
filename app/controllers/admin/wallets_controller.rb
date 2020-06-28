# encoding: UTF-8
# frozen_string_literal: true

module Admin
  class WalletsController < BaseController
    def index
      @wallets = Wallet.includes(:blockchain)
                     .page(params[:page])
                     .per(100)
    end

    def show
      @wallet = Wallet.find(params[:id])
    end

    def new
      @wallet = Wallet.new
      render :show
    end

    def create
      @wallet = Wallet.new(wallet_params)
      if @wallet.save
        redirect_to admin_wallets_path
      else
        flash[:alert] = @wallet.errors.full_messages.first
        render :show
      end
    end

    def update
      @wallet = Wallet.find(params[:id])
      if @wallet.update(wallet_params)
        redirect_to admin_wallets_path
      else
        flash[:alert] = @wallet.errors.full_messages.first
        render :show
      end
    end

    def show_client_info
      @gateway = params[:gateway]
      @wallet = Wallet.find_by_id(params[:id]) || Wallet.new
    end

    private

    def wallet_params
      params.require(:wallet).permit(permitted_wallet_attributes)
    end

    def wallet_settings_params
      params.require(:wallet).require(:settings)
    end

    def permitted_wallet_attributes
      %i[
        currency_id
        blockchain_key
        name
        address
        max_balance
        kind
        status
        gateway
        uri
        secret
      ]
    end
  end
end
