class SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :create

  def create
    reset_session
    session[:id_token] = params[:id_token]
    redirect_to root_path
  end

  def destroy
    reset_session
    redirect_to '/auth/pliro/logout'
  end
end
