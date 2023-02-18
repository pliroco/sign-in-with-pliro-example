Rails.application.config.middleware.use OmniAuth::Builder do
  provider(
    :openid_connect,
    name: :pliro,
    issuer: 'http://localhost:3000',
    # discovery: true,
    client_options: {
      identifier: ENV['PLIRO_CLIENT_ID'],
      secret: ENV['PLIRO_CLIENT_SECRET'],
      redirect_uri: 'http://localhost:4000/auth/pliro/callback',
      scheme: 'http',
      host: 'example-account1.page.localhost',
      port: 3000,
      authorization_endpoint: '/oauth/authorize',
      token_endpoint: '/oauth/token',
      jwks_uri: 'http://example-account1.page.localhost:3000/oauth/discovery/keys',
      userinfo_endpoint: '/oauth/userinfo',
    },
  )
end
