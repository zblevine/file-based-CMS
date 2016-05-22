require "sinatra"
require "sinatra/reloader" if development?
require "sinatra/content_for"
require "tilt/erubis"
require "redcarpet"
require "yaml"
require "bcrypt"

configure do
  enable :sessions
  set :session_secret, 'secret'
  set :erb, :escape_html => true
end

def data_path
  return "test/data" if ENV["RACK_ENV"] == "test"
  "data"
end

def user_info_path
  return "test/user_info.yaml" if ENV["RACK_ENV"] == "test"
  "user_info.yaml"
end

def someone_signed_in?
  !!session[:current_user]
end

def redirect_if_not_signed_in
  unless someone_signed_in?
    session[:message] = "You must be signed in to do that."
    redirect "/"
  end
end

get "/" do
  @files = Dir.glob(File.join(data_path, "*")).map { |file| File.basename(file) }
  erb :index, layout: :layout
end

get "/new" do
  redirect_if_not_signed_in
  erb :new, layout: :layout
end

get "/users/signin" do
  erb :sign_in, layout: :layout
end

def render_markdown(txt)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(txt)
end

get "/:file_name" do
  file_name = File.join(data_path, params[:file_name])

  if File.exist?(file_name)
    file_txt = File.read(file_name)
    return erb render_markdown(file_txt) if File.extname(file_name) == ".md"
    headers["Content-Type"] = "text/plain"
    file_txt
  else 
    session[:message] = "#{params[:file_name]} does not exist."
    redirect "/"
  end
end

get "/:file_name/edit" do
  redirect_if_not_signed_in
  @file_name = params[:file_name]
  @txt = File.read(File.join(data_path, @file_name))
  erb :edit, layout: :layout
end


post "/:file_name/save" do
  redirect_if_not_signed_in
  file_name = File.join(data_path, params[:file_name])

  File.write(file_name, params[:new_txt])

  session[:message] = "#{params[:file_name]} has been updated."
  redirect "/"
end

post "/:file_name/delete" do 
  redirect_if_not_signed_in
  file_name = File.join(data_path, params[:file_name])
  File.delete(file_name)

  session[:message] = "#{params[:file_name]} has been deleted."
  redirect "/"
end

post "/new" do
  redirect_if_not_signed_in
  doc_name = params[:doc_name].strip
  if doc_name.empty?
    session[:message] = "Document must have a name."
    status 422
    erb :new
  else
    doc_name << ".txt" if File.extname(doc_name).empty?
    file_name = File.join(data_path, doc_name)
    File.new(file_name, "w+")
    session[:message] = "#{doc_name} has been created."
    redirect "/"
  end
end

post "/users/signin" do
  user_hsh = YAML.load_file(user_info_path)
  usr = params[:user]
  if user_hsh.key?(usr) && BCrypt::Password.new(user_hsh[usr]) == params[:pw]
    session[:message] = "Welcome!"
    session[:current_user] = usr
    redirect "/"
  else
    session[:message] = "Invalid username or password."
    status 422
    erb :sign_in
  end
end

post "/users/signout" do
  session.delete(:current_user)
  session[:message] = "You have been signed out."
  redirect "/"
end
