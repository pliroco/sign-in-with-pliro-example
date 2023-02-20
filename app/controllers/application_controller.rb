class ApplicationController < ActionController::Base
  before_action :decode_and_verify_id_token

  helper_method :signed_in?, :customer_name

  private

  attr_reader :id_token

  def decode_and_verify_id_token
    return if session[:id_token].blank?

    @id_token = decode_id_token(session[:id_token])

    id_token.verify! issuer: 'http://localhost:3000', audience: ENV['PLIRO_CLIENT_ID']
  end

  def signed_in?
    id_token.present?
  end

  def customer_name
    id_token.raw_attributes['name']
  end

  def decode_id_token(id_token)
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
    OpenIDConnect::ResponseObject::IdToken.decode id_token, key
  end
end
