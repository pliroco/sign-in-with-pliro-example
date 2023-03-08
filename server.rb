require 'bundler/setup'
require 'json'
require 'sinatra'
require 'rack/contrib'

ARTICLES = JSON.parse(File.read(File.join(__dir__, 'articles.json')), object_class: OpenStruct)

# Block search indexing
use Rack::ResponseHeaders do |headers|
  headers['X-Robots-Tag'] = 'none'
end

get '/' do
  @articles = ARTICLES

  erb :home
end

get '/articles/:slug' do
  @article = ARTICLES.find { |article| article.slug == params[:slug] }

  raise Sinatra::NotFound unless @article

  erb :article
end

helpers do
  def simple_format(text)
    text.split(/\n\n+/).map { |paragraph| "<p>#{paragraph}</p>" }.join("\n")
  end
end
