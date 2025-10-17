require 'bundler/setup'

require 'ostruct'
require 'json'
require 'jwt'
require 'net/http'
require 'rack/contrib'
require 'redis'
require 'sinatra'
require 'honeybadger'

if development?
  # Load environment variables from .env and .env.local
  require 'dotenv'
  Dotenv.load '.env.local', '.env'
end

PLIRO_SITE_URL = URI(ENV.fetch('PLIRO_SITE_URL'))
PLIRO_ISSUER = ENV['PLIRO_ISSUER'] || ENV.fetch('PLIRO_SITE_URL')
PLIRO_SIGNING_KEY = OpenSSL::PKey.read(ENV.fetch('PLIRO_SIGNING_KEY'))
PLIRO_CLIENT_ID = ENV.fetch('PLIRO_CLIENT_ID')
PLIRO_CLIENT_SECRET = ENV.fetch('PLIRO_CLIENT_SECRET')

# Redis is used to store active Pliro session IDs:
$redis = Redis.new(url: ENV['REDIS_URL'], ssl_params: { verify_mode: OpenSSL::SSL::VERIFY_NONE })

# Sessions expire automatically after 7 days of inactivity:
SESSION_EXPIRATION_TIME = 7 * 24 * 60 * 60 # seconds

enable :sessions
set :session_secret, ENV.fetch('SESSION_SECRET')
set :sessions, expire_after: SESSION_EXPIRATION_TIME

# This block runs before each request to destroy expired sessions:
before do
  break if session[:pliro_session_id].nil?

  # If the key exists, GETEX will update exipration time and return its value.
  # If the key doesn't exist (i.e. it has expired), GETEX just returns nil.
  session.destroy if $redis.getex(session[:pliro_session_id], ex: SESSION_EXPIRATION_TIME).nil?
end

# This block runs before each request to trigger a silent login flow if the
# reauth param is set to true. This is used in continue URLs provided to the
# Pliro checkout flow to make sure members are signed in after completing the
# checkout.
before do
  if request.request_method == 'GET' && params[:reauth] == 'true'
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

# Article data is stored in a JSON file in the project root:
ARTICLES = JSON.parse(File.read(File.join(__dir__, 'articles.json')), object_class: OpenStruct)

# The home page:
get '/' do
  @articles = ARTICLES

  # This renders views/home.erb within views/layout.erb:
  erb :home
end

# The article show page:
get '/articles/:slug' do
  @article = ARTICLES.find { |article| article.slug == params[:slug] }

  raise Sinatra::NotFound unless @article

  # Refresh member access info in case they have upgraded to premium after they last signed in:
  if @article.premium && signed_in? && !premium_access?
    response = Net::HTTP.get_response(
      PLIRO_SITE_URL + '/oauth/userinfo',
      'Authorization' => "Bearer #{session[:access_token]}",
    )

    if response.is_a?(Net::HTTPSuccess)
      response_json = JSON.parse(response.body)

      session[:name] = response_json['name'] || response_json['email']
      session[:premium] = response_json['plan'] == 'premium'
    elsif response.is_a?(Net::HTTPUnauthorized)
      # If the member's access token has expired, we trigger a silent login flow:
      request_authentication return_to: request.fullpath, prompt: 'none'
    end
  end

  @page_title = @article.headline
  @meta_description = @article.meta_description
  @og_image = url(@article.image)

  # This renders views/article.erb within views/layout.erb:
  erb :article
end

# Sign in endpoint:
get '/sign_in' do
  request_authentication return_to: params[:return_to]
end

# OAuth callback endpoint:
get '/callback' do
  # Avoid open redirect exploits:
  return_to_url = if !params[:return_to].nil?
                    "#{request.scheme}://#{request.host_with_port}/#{params[:return_to].delete_prefix('/')}"
                  else
                    '/'
                  end

  if params[:error] == 'login_required'
    # The silent login flow failed and the user needs to sign in again.

    session.destroy

    redirect return_to_url
  elsif params.key?(:error)
    raise "OIDC error: error=#{params[:error].inspect} description=#{params[:error_description].inspect}"
  end

  if params[:state] != session[:state]
    raise "CSRF error: state=#{params[:state].inspect} stored_state=#{session[:state].inspect}"
  end

  # Use the provided authorization code to request access and ID tokens for the member:

  token_uri = PLIRO_SITE_URL + '/oauth/token'

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
  id_token_payload = decode_jwt(id_token).first

  session.destroy
  session[:access_token] = response_json.fetch('access_token')
  session[:id_token] = id_token
  session[:name] = id_token_payload['name'] || id_token_payload['email']
  session[:pliro_session_id] = id_token_payload.fetch('sid')
  session[:premium] = id_token_payload['plan'] == 'premium'

  $redis.set session[:pliro_session_id], "", ex: SESSION_EXPIRATION_TIME

  redirect return_to_url
end

# Sign out endpoint:
post '/sign_out' do
  # Redirecting to this URL signs the member out of Pliro too:
  end_session_uri = PLIRO_SITE_URL + '/oauth/end_session'
  end_session_uri.query = build_query(
    client_id: PLIRO_CLIENT_ID,
    id_token_hint: session[:id_token],
    post_logout_redirect_uri: url('/'),
  )

  session.destroy

  redirect end_session_uri
end

# OpenID Connect back-channel logout endpoint. If registered, Pliro makes a
# request to this endpoint when a member signs out of Pliro:
post '/backchannel_logout' do
  logout_token_payload, logout_token_header = decode_jwt(params[:logout_token])

  if logout_token_payload['iss'] == PLIRO_ISSUER &&
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

  def member_name
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

    authorization_uri = PLIRO_SITE_URL + '/oauth/authorize'
    authorization_uri.query = build_query({
      client_id: PLIRO_CLIENT_ID,
      response_type: 'code',
      scope: 'openid email profile',
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

  def decode_jwt(token)
    JWT.decode(token, PLIRO_SIGNING_KEY, true, algorithm: 'ES256')
  end
end
