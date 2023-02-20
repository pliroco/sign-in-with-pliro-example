class SessionsController < ApplicationController
  def create
    user_info = request.env['omniauth.auth']
    reset_session
    session[:id_token] = user_info.credentials.id_token
    redirect_to root_path
  end

  def destroy
    reset_session
    redirect_to '/auth/pliro/logout'
  end
end
