# encoding: UTF-8
# frozen_string_literal: true
module API
  module V2
    class TestApp < Grape::API
      helpers API::V2::Helpers
      use API::V2::Auth::Middleware

      get '/' do
        authenticate!
        current_user.email
      end
    end

    class Mount
      mount TestApp
    end
  end
end

describe API::V2::Auth::Middleware, type: :request do

  context 'when using JWT authentication' do
    let(:member) { create(:member, :level_3, uid: 'U123456789') }
    let(:payload) do
      { x: 'x', y: 'y', z: 'z', email: member.email,\
        uid: 'U123456789', role: 'member', state: 'active', level: '3' }
    end
    let(:token) { jwt_build(payload) }

    it 'should deny access when token is not given' do
      api_get '/api/v2/'
      expect(response.code).to eq '401'
      expect(response).to include_api_error('jwt.decode_and_verify')
    end

    it 'should deny access when invalid token is given' do
      api_get '/api/v2/', token: '123.456.789'
      expect(response.code).to eq '401'
      expect(response).to include_api_error('jwt.decode_and_verify')
    end

    it 'should allow access when valid token is given' do
      api_get '/api/v2/', token: token

      expect(response).to be_successful
      expect(JSON.parse(response.body)).to eq member.email
    end
  end

  context 'when not using authentication' do
    it 'should deny access' do
      api_get '/api/v2/'
      expect(response.code).to eq '401'
      expect(response).to include_api_error('jwt.decode_and_verify')
    end
  end
end
