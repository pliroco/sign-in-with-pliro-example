Rails.application.routes.draw do
  root 'pages#home'

  post 'sign_in' => 'sessions#init'
  get 'callback' => 'sessions#create'
  post 'sign_out' => 'sessions#destroy'
  post 'backchannel_logout' => 'sessions#backchannel_logout'
end
