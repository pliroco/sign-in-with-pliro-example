class SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :create

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
    session[:id_token] = access_token_response.id_token
    session[:access_token] = access_token_response.access_token

    redirect_to root_path
  end

  def destroy
    reset_session

    end_session_endpoint = "http://example-account1.page.localhost:3000/oauth/end_session?post_logout_redirect_uri=#{ERB::Util.url_encode('http://localhost:4000')}"

    redirect_to end_session_endpoint, allow_other_host: true
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
