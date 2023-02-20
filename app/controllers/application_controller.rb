class ApplicationController < ActionController::Base
  helper_method :signed_in?, :customer_name

  private

  def signed_in?
    session[:id_token].present?
  end

  def customer_name
    decoded_id_token['name']
  end

  def decoded_id_token
    @decoded_id_token ||= JSON::JWT.decode(session[:id_token], :skip_verification)
  end
end
