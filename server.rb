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

before do
  if params[:reauth] == 'true'
    uri = URI(request.fullpath)
    query_params = parse_query(uri.query)
    query_params.delete 'reauth'
    uri.query = query_params.empty? ? nil : build_query(query_params)
    request_authentication return_to: uri.to_s, prompt: 'none'
  end
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

  if @article.premium && signed_in? && !premium_access?
    response = Net::HTTP.get_response(
      URI(PLIRO_OPENID_CONFIG.userinfo_endpoint),
      'Authorization' => "Bearer #{session[:access_token]}",
    )

    if response.is_a?(Net::HTTPSuccess)
      response_json = JSON.parse(response.body)

      session[:name] = response_json.fetch('name')
      session[:premium] = response_json.fetch('products').include?('premium')
    elsif response.is_a?(Net::HTTPUnauthorized)
      request_authentication return_to: request.fullpath, prompt: 'none'
    end
  end

  erb :article
end

get '/sign_in' do
  request_authentication return_to: params[:return_to]
end

get '/callback' do
  return_to_url = if !params[:return_to].nil?
                    "#{request.scheme}://#{request.host_with_port}#{params[:return_to]}"
                  else
                    '/'
                  end

  if %w(interaction_required login_required account_selection_required consent_required).include?(params[:error])
    session.destroy

    redirect return_to_url
  elsif params.key?(:error)
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
    redirect_uri: build_redirect_uri(return_to: params[:return_to]),
  }
  token_request.basic_auth PLIRO_CLIENT_ID, PLIRO_CLIENT_SECRET

  token_response = Net::HTTP.start(token_uri.hostname, token_uri.port, use_ssl: token_uri.scheme == 'https') do |http|
    http.request token_request
  end

  response_json = JSON.parse(token_response.body)
  id_token = response_json.fetch('id_token')
  id_token_payload = JWT.decode(id_token, nil, false).first

  session.destroy
  session[:access_token] = response_json.fetch('access_token')
  session[:id_token] = id_token
  session[:name] = id_token_payload.fetch('name')
  session[:pliro_session_id] = id_token_payload.fetch('sid')
  session[:premium] = id_token_payload.fetch('products').include?('premium')

  $redis.set session[:pliro_session_id], "", ex: SESSION_EXPIRATION_TIME

  redirect return_to_url
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

  def premium_access?
    !!session[:premium]
  end

  def simple_format(text)
    text.split(/\n\n+/).map { |paragraph| "<p>#{paragraph}</p>" }.join("\n")
  end

  def request_authentication(return_to:, prompt: nil)
    session[:state] = SecureRandom.hex

    authorization_uri = URI(PLIRO_OPENID_CONFIG.authorization_endpoint)
    authorization_uri.query = build_query({
      client_id: PLIRO_CLIENT_ID,
      response_type: 'code',
      scope: 'openid profile',
      redirect_uri: build_redirect_uri(return_to:),
      state: session[:state],
      prompt:,
    }.compact)

    redirect authorization_uri
  end

  def build_redirect_uri(return_to:)
    url '/callback' + (return_to.nil? ? '' : "?return_to=#{escape(return_to)}")
  end

  def build_continue_url
    uri = URI(request.url)
    query_params = parse_query(uri.query)
    uri.query = build_query(query_params.merge(reauth: true))
    uri.to_s
  end
end
