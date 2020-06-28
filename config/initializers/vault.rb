# encoding: UTF-8
# frozen_string_literal: true

require 'vault/totp'
require 'vault/rails'

Vault.configure do |config|
  config.enabled = Rails.env.production?
  config.address = ENV.fetch('VAULT_URL', 'http://127.0.0.1:8200')
  config.token = ENV.fetch('VAULT_TOKEN')
  config.ssl_verify = false
  config.timeout = 60
  config.application = ENV.fetch('VAULT_APP_NAME', 'peatio')
end

if Rails.env.production? && ENV.fetch('VAULT_RENEW', false)
  def renew_process
    token = Vault.auth_token.lookup(Vault.token)
    sleep(token.data[:ttl] * (1 + rand) * 0.1)
    Vault.auth_token.renew(token.data[:id])
  end

  Thread.new do
    loop do
      renew_process
    rescue StandardError => e
      report_exception(e)
      sleep 60
    end
  end
end
