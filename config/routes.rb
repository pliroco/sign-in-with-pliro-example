Rails.application.routes.draw do
  root 'pages#home'

  post 'auth/:provider/callback', to: 'sessions#create'

  resource :session, only: :destroy
end
