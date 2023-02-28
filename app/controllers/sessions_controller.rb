class SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: %i(create backchannel_logout)

  def init
    session[:state] = SecureRandom.base58(16)

    authorization_uri = oidc_client.authorization_uri(
      response_type: 'code',
      scope: ['openid', 'profile'],
      state: session[:state],
    )

    redirect_to authorization_uri, allow_other_host: true
  end

  def create
    if params[:error].present?
      raise "OIDC error: error=#{params[:error].inspect} description=#{params[:error_description].inspect}"
    end

    if params[:state] != session[:state]
      raise "CSRF error: state=#{params[:state].inspect} stored_state=#{session[:state].inspect}"
    end

    oidc_client.authorization_code = params[:code]
    access_token_response = oidc_client.access_token!
    decoded_id_token = JSON::JWT.decode(access_token_response.id_token, :skip_verification)

    reset_session
    session[:customer_id] = decoded_id_token['sub']
    session[:customer_name] = decoded_id_token['name']
    session[:pliro_session_id] = decoded_id_token['sid']
    session[:id_token] = access_token_response.id_token
    session[:access_token] = access_token_response.access_token

    redirect_to root_path
  end

  def destroy
    end_session_uri = URI('http://example-account1.page.localhost:3000/oauth/end_session')
    end_session_uri.query = {
      client_id: ENV['PLIRO_CLIENT_ID'],
      id_token_hint: session[:id_token],
      post_logout_redirect_uri: 'http://localhost:4000',
    }.to_query

    reset_session

    redirect_to end_session_uri.to_s, allow_other_host: true
  end

  def backchannel_logout
    key_json = {
      "kty" => "EC",
      "crv" => "P-256",
      "x" => "GlgP9SICX5d_wOpE1ABUMfjnj_Trc-tRY3b7N9gQ6xQ",
      "y" => "_HN1yJjxy4LtrB6EvGcz9xEBTeDIrKDBGmUoR4cfs5A",
      "kid" => "16665380d2190bbf320bd40ecc804ba13045ca6820e980b9e2720849342af949",
      "use" => "sig",
      "alg" => "ES256",
    }
    key = JSON::JWK.new(key_json)
    decoded_logout_token = JSON::JWT.decode(params[:logout_token], key, :ES256)

    if decoded_logout_token[:iss] == 'http://example-account1.page.localhost' &&
        decoded_logout_token[:aud] == ENV['PLIRO_CLIENT_ID'] &&
        decoded_logout_token[:iat] <= Time.current.utc.to_i &&
        decoded_logout_token[:iat] >= 5.minutes.ago.utc.to_i &&
        decoded_logout_token[:sub].present? &&
        decoded_logout_token[:sid].present? &&
        decoded_logout_token[:events]&.key?('http://schemas.openid.net/event/backchannel-logout') &&
        !decoded_logout_token.key?(:nonce) &&
        decoded_logout_token.header[:typ] == 'logout+jwt'

      customer_id = decoded_logout_token[:sub]
      pliro_session_id = decoded_logout_token[:sid]

      ActiveRecord::SessionStore::Session.delete_by(
        "data->>'customer_id' = :customer_id AND data->>'pliro_session_id' = :pliro_session_id",
        customer_id:,
        pliro_session_id:,
      )

      head :no_content
    else
      render status: :bad_request, json: { error: invalid_request }
    end
  end

  private

  def oidc_client
    @oidc_client ||= OpenIDConnect::Client.new(
      identifier: ENV['PLIRO_CLIENT_ID'],
      secret: ENV['PLIRO_CLIENT_SECRET'],
      redirect_uri: 'http://localhost:4000/callback',
      scheme: 'http',
      host: 'example-account1.page.localhost',
      port: 3000,
      authorization_endpoint: '/oauth/authorize',
      token_endpoint: '/oauth/token',
    )
  end
end
