require 'sinatra'
require 'mongo_mapper'
require 'uri'
require 'digest/md5'
require './models/url'

# If using Basic Authentication, please change the default passwords!
CREDENTIALS = [ENV[MSHORT_USER], ENV[MSHORT_PASS]]

configure :development do
  MongoMapper.database = 'mongoshort_dev'
end

configure :test do
  MongoMapper.database = 'mongoshort_test'
end

configure :production do
  if ENV['MONGOHQ_URL']
    uri = URI.parse(ENV['MONGOHQ_URL'])
    MongoMapper.connection = Mongo::Connection.from_uri(ENV['MONGOHQ_URL'])
    MongoMapper.database = uri.path.gsub(/^\//, '')
  end
end

helpers do
  def display_(url)
    "<p>Short: #{url.short_url}}, Long: #{url.full_url}, Viewed: #{url.times_viewed}</p>"
  end

  # Does a few checks for HTTP Basic Authentication.
  def protected!
    auth = Rack::Auth::Basic::Request.new(request.env)

    # Return a 401 error if there's no basic authentication in the request.
    unless auth.provided?
      response['WWW-Authenticate'] = %Q{Basic Realm="Mongoshort URL Shortener"}
      throw :halt, [401, 'Authorization Required']
    end
  
    # Non-basic authentications will be returned as a bad request (400 error).
    unless auth.basic?
      throw :halt, [400, 'Bad Request']
    end

    # The basic checks are okay - Check if the credentials match.
    if auth.provided? && CREDENTIALS == auth.credentials
      return true
    else
      throw :halt, [403, 'Forbidden']
    end
  end
end

get '/' do
  send_file File.join(settings.public_folder, 'index.html')
end

get '/:url' do
  url = URL.find_by_url_key(params[:url])
  if url.nil?
    raise Sinatra::NotFound
  else
    url.last_accessed = Time.now
    url.times_viewed += 1
    url.save
    redirect url.full_url, 301
  end
end

get '/info/all' do
  content_type :html
  content = "Count: #{URL.count()}</br>"
  URL.all(:order => :times_viewed.desc).each do |url|
    content << display_(url)
  end
  return content
end

get '/info/:url' do
  content_type :html
  url = URL.find_by_url_key(params[:url])
  if url.nil?
    "Not found in database"
  else
    display_(url)
  end
end

post '/new' do
  protected!
  content_type :json
  
  if !params[:url]
    status 400
    return { :error => "'url' parameter is missing" }.to_json
  end
  
  url = URL.find_or_create(params[:url], params[:vanity])
  return url.to_json
end

not_found do
  # Change this URL to wherever you want to be redirected if a non-existing URL key or an invalid action is called.
  redirect "http://#{Sinatra::Application.bind}/"
end
