
# frozen_string_literal: true

# Writing and Reading to files
require 'fileutils'
require 'securerandom'
require 'html2slim'

APP_NAME = "raft"
DEPLOY_HOST = "www.example.com"
SITE_URL = "https://#{DEPLOY_HOST}/"
REPO_URL = "git@example.com:organization/raft.git"


def add_gems
  gem 'dotenv-rails', require: 'dotenv/rails-now'
  gem 'devise'
  gem 'devise-i18n'
  gem 'simple_form'
  gem 'bcrypt', '~> 3.1.7'
  gem 'image_processing', '~> 1.2'
  gem 'slim-rails'
  gem 'mysql2'
  gem 'awesome_print'
  gem 'bcrypt_pbkdf'
  gem 'ed25519'
  gem 'sanitize'
  gem 'recaptcha'
  gem 'will_paginate'
  gem 'will_paginate-bootstrap4'
  gem 'omniauth'
  gem 'omniauth-google-oauth2'
  gem 'omniauth-facebook'
  gem 'omniauth-linkedin-oauth2'
  gem 'omniauth-openid'
  gem 'omniauth-twitter'

  gem_group :development, :test do
    gem 'rspec-rails'
    gem 'factory_bot_rails'
  end

  gem_group :development do
    gem 'annotate'
    gem 'capistrano-bundler'
    gem 'capistrano-rails'
    gem 'capistrano-rvm'
    gem 'i18n-tasks'
    gem 'i18n_yaml_sorter'
    gem 'rubocop', require: false
  end

end

def setup_mysql
  app_name = APP_NAME.parameterize
  db_user = app_name
  db_passwd = SecureRandom.base64(12)
  sql = "create user #{db_user};\n"
  sql += "alter user #{db_user} identified by '#{db_passwd}';\n"
  %w(prod test dev).each do |env|
    sql += "create database #{app_name}_#{env};\n"
    sql += "grant all on #{app_name}_#{env}.* to '#{db_user}';\n"
  end
  File.write('tmp/setup.sql', sql )
  run "mysql < tmp/setup.sql"
  gsub_file 'config/database.yml', /adapter: sqlite3/, 'adapter: mysql2'
  gsub_file 'config/database.yml', /pool: .*/, "username: #{db_user}"
  gsub_file 'config/database.yml', /timeout: .*/, "password: #{db_passwd}\n  host: localhost\n  encoding: utf8mb4\n  collation: utf8mb4_unicode_ci"
  gsub_file 'config/database.yml', /db\/test.sqlite3/, "#{app_name}_test"
  gsub_file 'config/database.yml', /db\/development.sqlite3/, "#{app_name}_dev"
  gsub_file 'config/database.yml', /db\/production.sqlite3/, "#{app_name}_prod"
end

def setup_simple_form
  generate 'simple_form:install --bootstrap'
end

def setup_rspec
  generate "rspec:install"
end

def source_paths
  [__dir__]
end

def setup_users
  generate 'devise:install'
  environment "config.action_mailer.default_url_options = { host: 'localhost', port: 3000 }", env: 'development'
  environment "config.action_mailer.default_url_options = { host: '#{SITE_URL}' }", env: 'production'
  rails_command 'g scaffold user status:integer roles:integer firstname:string lastname:string street:string city:string country:string postcode:string member_id:integer license:string birthday:date gender:integer --no-scaffold-stylesheet'
  #generate :devise, 'User', 'status: integer', 'roles:integer', 'firstname:string', 'lastname:string', 'street:string', 'city:string', 'country:string', 'postcode:string', 'member_id:integer', 'license:string', 'birthday:date', 'gender:integer'
  generate :devise, 'User'
  in_root do
    migration = Dir.glob('db/migrate/*').max_by { |f| File.mtime(f) }
    gsub_file migration, /:status/, ':status, default: 0'
    gsub_file migration, /:roles/, ':roles, default: 0'

    [ "t.integer  :sign_in_count",
      "t.datetime :current_sign_in_at",
      "t.datetime :last_sign_in_at",
      "t.string   :current_sign_in_ip",
      "t.string   :last_sign_in_ip",
      "t.string   :confirmation_token",
      "t.datetime :confirmed_at",
      "t.datetime :confirmation_sent_at",
      "t.string   :unconfirmed_email",
      "t.integer  :failed_attempts",
      "t.string   :unlock_token",
      "t.datetime :locked_at",
      "add_index :users, :confirmation_token",
      "add_index :users, :unlock_token"
    ].each do |line|
      gsub_file migration, "# #{line}", line
    end
  end
  rails_command 'db:migrate'
  generate 'devise:views'

  inject_into_file 'app/controllers/application_controller.rb', before: 'end' do
"
protect_from_forgery with: :exception

before_action :configure_permitted_parameters, if: :devise_controller?

protected
  def configure_permitted_parameters
    added_attrs = %i[email password password_confirmation remember_me]
    devise_parameter_sanitizer.permit :sign_up, keys: added_attrs
    devise_parameter_sanitizer.permit :account_update, keys: added_attrs
  end
"
  end

  inject_into_file 'app/models/user.rb', after: ':validatable' do
    ",\n         :confirmable, :lockable, :timeoutable, :trackable, :omniauthable"
  end

  # find_and_replace_in_file('app/views/devise/sessions/new.html.erb', 'email', 'login')

  # inject_into_file 'app/views/devise/registrations/new.html.erb', before: '<%= f.input :email' do
  #   "\n<%= f.input :username %>\n"
  # end

  # inject_into_file 'app/views/devise/registrations/edit.html.erb', before: '<%= f.input :email' do
  #   "\n<%= f.input :username %>\n"
  # end
end

def setup_authorizations
  generate :model, 'Authorization', 'user_id:integer', 'provider:string', 'uid:string', 'token:string', 'secret:string', 'profile_page:string'
  # in_root do
  #   migration = Dir.glob('db/migrate/*').max_by { |f| File.mtime(f) }
  #   inject_into_file migration, before: 'end' do
  #     "\n  add_index :authorizations, :user_id\n"
  #   end
  # end
  rails_command 'db:migrate'

  inject_into_file 'app/models/authorization.rb', after: 'ApplicationRecord' do
    "\n  belongs_to :user"
  end

  inject_into_file 'app/models/user.rb', after: ':omniauthable' do
    ", omniauth_providers: %i[facebook google_oauth2 twitter linkedin]\n"
  end

  inject_into_file 'app/models/user.rb', after: 'ApplicationRecord' do
    "
  SOCIALS = {
    facebook: 'Facebook',
    google_oauth2: 'Google',
    linkedin: 'Linkedin',
    twitter: 'Twitter'
  }.freeze

  has_many :authorizations
"
  end

  inject_into_file 'app/models/user.rb', before: 'end' do
    "
  def self.from_omniauth(auth, current_user)
    authorization = Authorization.where(:provider => auth.provider, :uid => auth.uid.to_s,
                                        :token => auth.credentials.token,
                                        :secret => auth.credentials.secret).first_or_initialize
    authorization.profile_page = auth.info.urls.first.last unless authorization.persisted?
    if authorization.user.blank?
      user = current_user.nil? ? User.where('email = ?', auth['info']['email']).first : current_user
      if user.blank?
        user = User.new
        user.skip_confirmation!
        user.password = Devise.friendly_token[0, 20]
        user.fetch_details(auth)
        user.save
      end
      authorization.user = user
      authorization.save
    end
    authorization.user
  end

  def fetch_details(auth)
    self.name = auth.info.name
    self.email = auth.info.email
    self.photo = URI.parse(auth.info.image)
  end
"
  end

  omniauth_callbacks_controller = 'app/controllers/omniauth_callbacks_controller.rb'
  FileUtils.touch(omniauth_callbacks_controller)

  append_to_file omniauth_callbacks_controller do
    "
class Users::OmniauthCallbacksController < Devise::OmniauthCallbacksController

  def all
    user = User.from_omniauth(env['omniauth.auth'], current_user)
    if user.persisted?
      sign_in user
      flash[:notice] = t('devise.omniauth_callbacks.success', :kind => User::SOCIALS[params[:action].to_sym])
      # if user.sign_in_count == 1
      #   redirect_to first_login_path
      # else
      #   redirect_to cabinet_path
      # end
    else
      session['devise.user_attributes'] = user.attributes
      redirect_to new_user_registration_url
    end
  end

  User::SOCIALS.each do |k, _|
    alias_method k, :all
  end
end
"
  end

  gsub_file 'config/routes.rb', 'devise_for :users', "devise_for :users, :controllers => { :omniauth_callbacks => 'users/omniauth_callbacks'}"

  inject_into_file 'config/initializers/devise.rb', after: 'Devise.setup do |config|' do
    "
  config.omniauth :facebook, ENV['FACEBOOK_APP_ID'], ENV['FACEBOOK_SECRET']
  config.omniauth :twitter, ENV['TWITTER_KEY'], ENV['TWITTER_SECRET']
  config.omniauth :google_oauth2, ENV['GOOGLE_KEY'], ENV['GOOGLE_SECRET']
  config.omniauth :linkedin, ENV['LINKEDIN_KEY'], ENV['LINKEDIN_SECRET']
"
  end
end

def find_and_replace_in_file(file_name, old_content, new_content)
  text = File.read(file_name)
  new_contents = text.gsub(old_content, new_content)
  File.open(file_name, 'w') { |file| file.write new_contents }
end

def demo_rails_commands
  generate(:controller, 'pages home')
  route "root to: 'pages#home'"
  rails_command 'g scaffold post title:string body:text --no-scaffold-stylesheet'
  rails_command 'db:migrate'
end

def add_bootstrap
  run 'yarn add bootstrap jquery popper.js'
  inject_into_file 'config/webpack/environment.js', before: 'module.exports = environment' do
    "const webpack = require('webpack')
        environment.plugins.append('Provide',
            new webpack.ProvidePlugin({
                $: 'jquery',
                jQuery: 'jquery',
                Popper: ['popper.js', 'default']
            })
        )\n"
  end
  inject_into_file 'app/javascript/packs/application.js', after: '// const imagePath = (name) => images(name, true)' do
    "\nimport 'bootstrap';
        import './stylesheets/application.scss';\n"
  end
  FileUtils.mkdir_p('app/javascript/packs/stylesheets')
  app_scss = 'app/javascript/packs/stylesheets/application.scss'
  FileUtils.touch(app_scss)
  append_to_file app_scss do
    "\n@import '~bootstrap/scss/bootstrap';\n"
  end
end

def add_bootstrap_navbar
  navbar = 'app/views/layouts/_navbar.html.slim'
  FileUtils.touch(navbar)
  gsub_file 'app/views/layouts/application.html.slim', /stylesheet_link_tag/, 'stylesheet_pack_tag'
  gsub_file 'app/views/layouts/application.html.slim', /\= yield/, ''
  inject_into_file 'app/views/layouts/application.html.slim', after: 'body' do
    "
    = render 'layouts/navbar'
    .container
      .mt-3
        = yield
"
  end
  inject_into_file 'app/views/layouts/application.html.slim', before: '= yield' do
    "    "
  end

  append_to_file navbar do
    '
nav.navbar.navbar-expand-lg.navbar-light.bg-light
  .container
    = link_to Rails.application.class.module_parent_name, root_path, class:"navbar-brand"
    button.navbar-toggler[type="button" data-toggle="collapse" data-target="#navbarSupportedContent" aria-controls="navbarSupportedContent" aria-expanded="false" aria-label="Toggle navigation"]
      span.navbar-toggler-icon
    #navbarSupportedContent.collapse.navbar-collapse
      ul.navbar-nav.mr-auto
        li.nav-item.active
          = link_to "Home", root_path, class:"nav-link"
        li.nav-item
          = link_to "Posts", posts_path, class:"nav-link"
      ul.navbar-nav.ml-auto
        - if current_user
          li.nav-item.dropdown
            a#navbarDropdown.nav-link.dropdown-toggle[href="#" role="button" data-toggle="dropdown" aria-haspopup="true" aria-expanded="false"]
              = current_user.email
            .dropdown-menu.dropdown-menu-right[aria-labelledby="navbarDropdown"]
              = link_to "Account Settings", edit_user_registration_path, class:"dropdown-item"
              = link_to "New Post", new_post_path, class:"dropdown-item"
              .dropdown-divider
              = link_to "Logout", destroy_user_session_path, method: :delete, class:"dropdown-item"
        - else
          li.nav-item
            = link_to "Create Account", new_user_registration_path, class:"nav-link"
          li.nav-item
            = link_to "Login", new_user_session_path, class:"nav-link"
'
  end
end

def convert_erb_to_slim
  in_root do
    run 'erb2slim app/views -d'
  end
  devise_view_files = Dir.glob("app/views/devise/**/*").reject { |f| File.directory?(f) }
  devise_view_files.each do |f|
    gsub_file f, /,\n\s*-\s*/, ', '
    gsub_file f, /f.button (.*)$/, 'f.button \1, class: \'btn btn-primary m-1\''
  end
end

def setup_capistrano
  run 'bundle exec cap install'
  gsub_file 'config/deploy.rb', /my_app_name/, APP_NAME
  gsub_file 'config/deploy.rb', /git@example\.com:me\/my_repo\.git/, REPO_URL
  gsub_file 'config/deploy.rb', /# append :linked_dirs/, ' append :linked_dirs,'
  gsub_file 'config/deploy.rb', /"public\/system"/, '"public/system", "public/uploads", "storage"'

  append_to_file 'config/deploy/production.rb' do
"
server '#{DEPLOY_HOST}', user: 'deploy', roles: %w{web app}
set :deploy_to, '/apps/#{APP_NAME}'
set :rails_env, :production
"
  end

  ["rvm", "bundler", "rails/assets", "rails/migrations", "passenger"].each do |cfg|
    gsub_file 'Capfile', "# require \"capistrano/#{cfg}", "require \"capistrano/#{cfg}"
  end

end

def setup_slim
  in_root do
    append_to_file 'config/environments/development.rb' do
      "Slim::Engine.set_options pretty: true, sort_attrs: false"
    end
    append_to_file 'config/environments/test.rb' do
      "Slim::Engine.set_options pretty: true, sort_attrs: false"
    end
  end
end

def remove_master_key_in_gitignore
  gsub_file '.gitignore', /\/config\/master.key/, "# /config/master.key"
end

# def fix_tabs_in_views
#   devise_view_files = Dir.glob("app/**/**/*").reject { |f| File.directory?(f) }
#   devise_view_files.each do |f|
#     gsub_file f, /\t/, ', '
#   end
# end

source_paths

add_gems

after_bundle do
  setup_slim
  setup_mysql
  setup_simple_form
  setup_rspec
  setup_users
  setup_authorizations

  demo_rails_commands

  add_bootstrap
  convert_erb_to_slim
  add_bootstrap_navbar
  setup_capistrano
  remove_master_key_in_gitignore
  #fix_tabs_in_views
end
