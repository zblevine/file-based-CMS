ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../cms"

class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { current_user: "admin" } }
  end

  def test_index
    create_document("about.txt")
    create_document("changes.txt")
    get "/"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.txt"
    assert_includes last_response.body, "changes.txt"
  end

  def test_one_file
    create_document("changes.txt", "Change. Ruby is a changing language. Another sentence")
    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, "Ruby is a changing language."
  end

  def test_empty_file
    create_document("kevin_durant.txt")
    get "/basedgod.txt"
    assert_equal 302, last_response.status
    assert_equal session[:message], "basedgod.txt does not exist."
  end

  def test_markdown_file
    create_document("mdpage.md", "There should be some **bold** here")
    get "/mdpage.md"
    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<strong>bold</strong>"
  end

  def test_edit_page
    create_document("history.txt", "The French Revolution started in 1789.")
    get "/history.txt/edit", {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, "French Revolution"
  end

  def test_save_changes
    create_document("history.txt", "ancient history")

    post "/history.txt/save", {new_txt: "changed history"}, admin_session
    assert_equal 302, last_response.status
    assert_equal session[:message], "history.txt has been updated."

    get "/history.txt"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "changed history"
  end

  def test_new_doc_page
    get "/new", {}, admin_session
    assert_equal 200, last_response.status
    assert_includes last_response.body, "</form>"
    assert_includes last_response.body, "Add a new document:"
  end

  def test_created_doc
    post "/new", {doc_name: "new_doc.txt"}, admin_session
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_equal 200, last_response.status
    assert_includes last_response.body, "new_doc.txt"
  end

  def test_doc_no_ext
    post "/new", {doc_name: "no_ext"}, admin_session
    get last_response["Location"]
    assert_includes last_response.body, "no_ext.txt"
  end

  def test_nameless_doc
    post "/new", {doc_name: ""}, admin_session
    assert_equal 422, last_response.status
    assert_includes last_response.body, "Add a new document:"
    assert_includes last_response.body, "Document must have a name."
  end

  def test_delete
    create_document("pawn.txt")
    create_document("king.txt")

    post "/pawn.txt/delete", {}, admin_session
    assert_equal 302, last_response.status

    get last_response["Location"]
    assert_includes last_response.body, "/king.txt"
    refute_includes last_response.body, "/pawn.txt"
  end

  def test_signin_page
    get "/users/signin"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "Username:"
  end

  def test_correct_signin
    post "/users/signin", user: "admin", pw: "secret"
    assert_equal 302, last_response.status
    assert_equal session[:message], "Welcome!"
    assert_equal session[:current_user], "admin"
  end

  def test_wrong_signin
    post "/users/signin", user: "admin", pw: "wrongpw"
    assert_equal 422, last_response.status
    assert_nil session[:current_user]
    assert_includes last_response.body, "admin"
    assert_includes last_response.body, "Invalid username or password."

    post "/users/signin", user: "rudeboy", pw: "secret"
    assert_equal 422, last_response.status
    assert_includes last_response.body, "rudeboy"
  end

  def test_signout
    post "/users/signout"
    assert_equal 302, last_response.status
    assert_equal session[:message], "You have been signed out."

    get last_response["Location"]
    assert_includes last_response.body, "Sign In"
  end

  def test_stuff_not_logged_in
    create_document("doc.txt")

    get "/doc.txt/edit"
    assert_equal 302, last_response.status
    assert_equal session[:message], "You must be signed in to do that."

    get "/new"
    assert_equal 302, last_response.status
    assert_equal session[:message], "You must be signed in to do that."

    post "/doc.txt/save", new_txt: "hello world"
    assert_equal 302, last_response.status
    assert_equal session[:message], "You must be signed in to do that."

    get "/doc.txt"
    refute_includes last_response.body, "hello world"

    post "/new", doc_name: "never_posted.txt"
    assert_equal 302, last_response.status
    assert_equal session[:message], "You must be signed in to do that."

    get "/"
    refute_includes last_response.body, "never_posted.txt"

    post "/doc.txt/delete"
    assert_equal 302, last_response.status
    assert_equal session[:message], "You must be signed in to do that."

    get "/"
    assert_includes last_response.body, "doc.txt"
  end
end