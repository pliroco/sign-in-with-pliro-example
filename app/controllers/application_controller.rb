class ApplicationController < ActionController::Base
  helper_method :signed_in?, :customer_name

  private

  def signed_in?
    session[:customer_id].present?
  end

  def customer_name
    session[:customer_name]
  end
end
