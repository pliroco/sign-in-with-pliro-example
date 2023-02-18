class ApplicationController < ActionController::Base
  helper_method :signed_in?

  private

  def signed_in?
    session[:id_token].present?
  end
end
