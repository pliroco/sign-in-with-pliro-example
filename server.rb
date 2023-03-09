require 'bundler/setup'

require 'json'
require 'jwt'
require 'net/http'
require 'rack/contrib'
require 'redis'
require 'sinatra'

if development?
  # Load environment variables from .env and .env.local
  require 'dotenv'
  Dotenv.load '.env.local', '.env'
end

PLIRO_PAGE_URL = URI(ENV.fetch('PLIRO_PAGE_URL'))
PLIRO_CLIENT_ID = ENV.fetch('PLIRO_CLIENT_ID')
PLIRO_CLIENT_SECRET = ENV.fetch('PLIRO_CLIENT_SECRET')
PLIRO_OPENID_CONFIG = JSON.parse(
  Net::HTTP.get(PLIRO_PAGE_URL + '/.well-known/openid-configuration'),
  object_class: OpenStruct,
)
PLIRO_JWKS = JWT::JWK::Set.new(JSON.parse(Net::HTTP.get(URI(PLIRO_OPENID_CONFIG.jwks_uri))))

$redis = Redis.new(url: ENV['REDIS_TLS_URL'], ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

SESSION_EXPIRATION_TIME = 60 * 60 * 24

enable :sessions
set :session_secret, ENV.fetch('SESSION_SECRET')

before do
  break if session[:pliro_session_id].nil?

  session.destroy if $redis.getex(session[:pliro_session_id], ex: SESSION_EXPIRATION_TIME).nil?
end

# Block search indexing
use Rack::ResponseHeaders do |headers|
  headers['X-Robots-Tag'] = 'none'
end

ARTICLES = JSON.parse(File.read(File.join(__dir__, 'articles.json')), object_class: OpenStruct)

get '/' do
  @articles = ARTICLES

  erb :home
end

get '/articles/:slug' do
  @article = ARTICLES.find { |article| article.slug == params[:slug] }

  raise Sinatra::NotFound unless @article

  erb :article
end

get '/sign_in' do
  session[:state] = SecureRandom.hex

  authorization_uri = URI(PLIRO_OPENID_CONFIG.authorization_endpoint)
  authorization_uri.query = build_query(
    client_id: PLIRO_CLIENT_ID,
    response_type: 'code',
    scope: 'openid profile',
    redirect_uri: url('/callback'),
    state: session[:state],
  )

  redirect authorization_uri
end

get '/callback' do
  if params.key?(:error)
    raise "OIDC error: error=#{params[:error].inspect} description=#{params[:error_description].inspect}"
  end

  if params[:state] != session[:state]
    raise "CSRF error: state=#{params[:state].inspect} stored_state=#{session[:state].inspect}"
  end

  token_uri = URI(PLIRO_OPENID_CONFIG.token_endpoint)

  token_request = Net::HTTP::Post.new(token_uri)
  token_request.form_data = {
    grant_type: 'authorization_code',
    code: params[:code],
    redirect_uri: url('/callback'),
  }
  token_request.basic_auth PLIRO_CLIENT_ID, PLIRO_CLIENT_SECRET

  token_response = Net::HTTP.start(token_uri.hostname, token_uri.port, use_ssl: token_uri.scheme == 'https') do |http|
    http.request token_request
  end

  response_json = JSON.parse(token_response.body)
  id_token = response_json.fetch('id_token')
  id_token_payload = JWT.decode(id_token, nil, false).first

  session.destroy
  session[:id_token] = id_token
  session[:name] = id_token_payload.fetch('name')
  session[:pliro_session_id] = id_token_payload.fetch('sid')

  $redis.set session[:pliro_session_id], "", ex: SESSION_EXPIRATION_TIME

  redirect to('/')
end

post '/sign_out' do
  end_session_uri = URI(PLIRO_OPENID_CONFIG.end_session_endpoint)
  end_session_uri.query = build_query(
    client_id: PLIRO_CLIENT_ID,
    id_token_hint: session[:id_token],
    post_logout_redirect_uri: url('/'),
  )

  session.destroy

  redirect end_session_uri
end

post '/backchannel_logout' do
  algorithms = %w(ES256)
  jwks = PLIRO_JWKS.filter { |key| key[:use] == 'sig' && algorithms.include?(key[:alg]) }
  logout_token_payload, logout_token_header = JWT.decode(params[:logout_token], nil, true, algorithms:, jwks:)

  if logout_token_payload['iss'] == PLIRO_OPENID_CONFIG.issuer &&
      logout_token_payload['aud'] == PLIRO_CLIENT_ID &&
      logout_token_payload['iat'] <= Time.now.utc.to_i &&
      logout_token_payload['iat'] >= Time.now.utc.to_i - 5 * 60 &&
      !logout_token_payload['sub'].nil? &&
      !logout_token_payload['sid'].nil? &&
      logout_token_payload['events']&.key?('http://schemas.openid.net/event/backchannel-logout') &&
      !logout_token_payload.key?('nonce') &&
      logout_token_header['typ'] == 'logout+jwt'

    $redis.del logout_token_payload['sid']

    status 204
  else
    status 400
    content_type :json
    JSON.generate(error: 'invalid_request')
  end
end

helpers do
  def signed_in?
    !session[:id_token].nil?
  end

  def customer_name
    session[:name]
  end

  def simple_format(text)
    text.split(/\n\n+/).map { |paragraph| "<p>#{paragraph}</p>" }.join("\n")
  end
end
