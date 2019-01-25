# frozen_string_literal: true

# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.

require 'bcrypt'
require 'cuba'
require 'cuba/safe'
require 'cuba/render'
require 'date'
require 'erb'
require 'fileutils'
require 'net/http'
require 'json'
require 'kramdown'
require 'password_blacklist'
require 'securerandom'
require 'sequel'
Cuba.plugin Cuba::Safe
Cuba.plugin Cuba::Render
Cuba.use Rack::MethodOverride
Cuba.use Rack::Static, root: 'public', urls: ['/css']
Cuba.use Rack::Static, root: 'public', urls: ['/imgs']
Cuba.use Rack::Static, root: 'public', urls: ['/js']

Cuba.settings[:render][:template_engine] = 'html.erb'
Cuba.settings[:render][:views] = './views'

module Api
  # Authentication Model
  module Authentication
    # generates user session labeled as
    # `:user_id` which the value is equal to
    # the username given as an arguement

    def generate_user_session(username)
      env['rack.session'][:user_id] = username
    end

    # authenticates username with
    # two arguements given one being the username
    # and two the password of the account

    def authenticate(username, password)
      check_password = BCrypt::Password.new(
        UserTable.where(username: username).get(:password)
      ).is_password?(password)
      if check_password == true
        generate_user_session(username)
        res.redirect("/wiki/user/#{username}")
      elsif check_password == false
        res.status = 401
        res.write view('/login')
      end
    end

    # checks the session against the username given and if the differ
    # redirects to the login page

    def check_authentication_session(username)
      res.redirect('/login') if env['rack.session'][:user_id] != username
    end

    # checks to see where the username is and if the password assoicated
    # with username is the correct password

    def check_password(username, password)
      BCrypt::Password.new(
        UserTable.where(username: username).get(:password)
      ).is_password?(password)
    end

    # shows the value of the `rack.session` `:user_id` key

    def show_user_id
      env['rack.session'][:user_id]
    end

    # checkes to see if the session key `:user_id` is nil?
    # and redirects to the login page if `true`

    def authenticated?
      res.redirect('/login') if env['rack.session'][:user_id].nil?
    end

    # deletes the `:user_id` session key and
    # destroys the session altogether

    def user_logout
      env['rack.session'].delete(:user_id)
      env['rack.session'].destroy
    end
  end
  # Database Transaction Model
  module DatabaseTransactions
    # Puts wiki article into the `data` table
    # takes arguements of the generate_id, username,
    # title, and textarea

    def putwiki_datatable_transaction(generate_id, username, title, textarea)
      DataTable.insert(uuid: generate_id.to_s, username: username.to_s,
                       title: convert_title(title).to_s,
                       created_on: Time.now.to_i, edited_on: Time.now.to_i,
                       textarea: textarea.to_s)
    end

    # Puts wiki article into the `revision` table
    # takes arguements of the generate_id, username,
    # title, and textarea

    def putwiki_revision_transcation(generate_id, username, title, textarea)
      RevisionTable.insert(uuid: generate_id.to_s, username: username.to_s,
                           title: convert_title(title).to_s,
                           created_on: Time.now.to_i, edited_on: Time.now.to_i,
                           textarea: textarea.to_s)
    end

    # Updates wiki article into the `revision` table
    # takes arguements of the title and textarea

    def editwiki_revision_transcation(title, textarea)
      RevisionTable.insert(uuid:
        DataTable.where(title: convert_title(title).to_s).select(:uuid),
                           title: convert_title(title).to_s,
                           textarea: textarea, edited_on: Time.now.to_i,
                           created_on:
                           datatable_get_createdon_transcation(title),
                           username:
                           datatable_select_username_transcation(title))
    end

    # generates an article once the user signs up

    def datatable_generate_first_article
      generate_id = SecureRandom.uuid
      DataTable.insert(uuid: generate_id.to_s, username: show_user_id.to_s,
                       title: generate_id.to_s,
                       created_on: Time.now.to_i, edited_on: Time.now.to_i,
                       textarea: generate_markdown)
      res.redirect("/wiki/user/#{show_user_id}")
    end

    def datatable_get_createdon_transcation(title)
      DataTable.where(title:
        convert_title(title).to_s).get(:created_on)
    end

    def datatable_select_username_transcation(title)
      DataTable.where(title:
        convert_title(title).to_s).select(:username)
    end

    def datatable_where_username_map_articles(username)
      DataTable.where(
        username: username
      ).select_map(:title)
    end

    def datatable_where_converted_title(title)
      DataTable.where(title:
        convert_title(title).to_s)
    end

    def datatable_update_editedon_textarea_transaction(title, textarea)
      DataTable.where(title: convert_title(title).to_s)
               .update(edited_on: Time.now.to_i, textarea: textarea)
    end

    def insert_user_transaction(username, password)
      bcrypted_password = BCrypt::Password.create(password)
      UserTable.insert(username: username, password: bcrypted_password)
    end
  end

  module WikiArticles
    # generates lorem lipsum markdown text using an HTTP API hosted at
    # `https://jaspervdj.be/lorem-markdownum/markdown.txt`

    def generate_markdown
      Net::HTTP.get(URI('https://jaspervdj.be/lorem-markdownum/markdown.txt')).to_s
    end

    # converts titles with a [space] to a [dash]

    def convert_title(title)
      title.downcase.strip.tr(' ', '-').gsub(/[^\w-]/, '')
    end

    # checks whether the title exists

    def check_input_title(title)
      DataTable.where(title: convert_title(title)).get(:title)
    end

    # checks where the title is an gets its value

    def get_title(title)
      DataTable.where(title: title).get(:title)
    end

    # gets the wiki article with a title arguement

    def get_wiki(title)
      article = DataTable.where(title: title).get(:textarea)
      @get_title = get_title(title)
      @markdown2html = Kramdown::Document.new(article).to_html
      @html2markdown = Kramdown::Document.new(@markdown2html, input: 'html')
                                         .to_kramdown
    rescue NoMethodError
      res.status = 404
      res.write view('/404')
    else
      res.write view('messages')
    end

    # gets the wiki revision article with a time arguement

    def get_revision(time)
      article = RevisionTable.where(edited_on: time).get(:textarea)
      @markdown2html = Kramdown::Document.new(article).to_html
      @html2markdown = Kramdown::Document.new(@markdown2html, input: 'html')
                                         .to_kramdown
    rescue NoMethodError
      res.status = 404
      res.write view('/404')
    else
      res.write view('messages')
    end

    def user_name_exists
      @used_username = '<small>* Username already in use </small>'
      res.status = 500
      res.write view('/signup')
    end

    def password_blacklisted
      @blacklist_password = '<small>*
      The password provided is blacklisted </small>'
      res.status = 500
      res.write view('/signup')
    end

    def signup_user(username, password, confirm_password)
      checker = PasswordBlacklist::Checker.new
      if UserTable.where(username: username).first
        user_name_exists
      elsif checker.blacklisted?(password) == true
        password_blacklisted
      elsif confirm_password == password
        insert_user_transaction(username, password)
        authenticate(username, password)
        datatable_generate_first_article
      end
    end
  end
end
Cuba.plugin Api::Authentication
Cuba.plugin Api::DatabaseTransactions
Cuba.plugin Api::WikiArticles
@session = Cuba.use Rack::Session::Cookie, secret: Random.new_seed.to_s,
                                           oldsecret: Random.new_seed.to_s
DB = Sequel.connect('sqlite://db/sqlite.db')
DataTable = DB[:data]
UserTable = DB[:user]
RevisionTable = DB[:datarevisions]

class Root < Cuba; end
Root.define do
  on root do
    @show_user_id = show_user_id
    res.write view('home')
  end
end

class GetMessage < Cuba; end
GetMessage.define do
  on ':title' do |title|
    get_wiki(title)
  end
end

class GetAllUserMessages < Cuba; end
GetAllUserMessages.define do
  on root do
    res.redirect('/login')
  end
  on ':username' do |username|
    check_authentication_session(username)
    @user_messages_title = datatable_where_username_map_articles(username)
    if @user_messages_title.any? || @user_messages_title.empty?
      @array = @user_messages_title.to_a
      @author = username.to_s
      @show_user_id = show_user_id
      res.write view('getallusermessages')
    end
  end
end

class GetRevision < Cuba; end
GetRevision.define do
  on ':time' do |time|
    get_revision(time)
  end
end

  class GetAllTitleRevisions < Cuba; end
  GetAllTitleRevisions.define do
    on ':title' do |title|
      @title_revisions = revision.where(title: title.downcase.strip.tr(' ', '-').gsub(/[^\w-]/, '').to_s)
                                 .select_map(:edited_on)
      if @title_revisions.any?
        @array = @title_revisions.to_a
        res.write view('getallusermessages')
      elsif @title_revisions.empty?
        res.redirect('/404')
      end
    end
  end
  class EditMessage < Cuba; end
  EditMessage.define do
    on root, param('username'), param('password'), param('title'), param('textarea') do |username, password, title, textarea|
      check_password = BCrypt::Password.new(user.where(username: username).get(:password)).is_password?(password)
      if check_password == true
        DB.transaction do
          data.where(title: title.downcase.strip.tr(' ', '-').gsub(/[^\w-]/, '').to_s)
          revision.insert(uuid: data.where(title: title.downcase.strip.tr(' ', '-')
          .gsub(/[^\w-]/, '').to_s).select(:uuid),
                          title: title.downcase.strip.tr(' ', '-').gsub(/[^\w-]/, '').to_s,
                          textarea: textarea, edited_on: Time.now.to_i,
                          created_on: data.where(title: title.downcase.strip.tr(' ', '-')
                          .gsub(/[^\w-]/, '').to_s).get(:created_on),
                          username: data.where(title: title.downcase.strip.tr(' ', '-')
                  .gsub(/[^\w-]/, '').to_s).select(:username))
          data.where(title: title.downcase.strip.tr(' ', '-').gsub(/[^\w-]/, '').to_s)
              .update(edited_on: Time.now.to_i, textarea: textarea)
        end
        res.redirect("/message/get/#{title.downcase.strip.tr(' ', '-').gsub(/[^\w-]/, '')}")
      elsif check_password == false
        res.redirect('/put_error')
      end
    rescue BCrypt::Errors::InvalidHash
      res.redirect('/put_error')
    end
  end
  class DeleteMessage < Cuba; end
  DeleteMessage.define do
    on root, param('title'), param('username'), param('password') do |title, username, password|
      check_password = BCrypt::Password.new(user.where(username: username).get(:password)).is_password?(password)
      if check_password == true
        data.where(title: title, username: username).delete
        res.status = 200
      elsif check_password == false
        res.status = 404
      end
    rescue BCrypt::Error
      res.status = 500
    rescue Standard::Error
      res.status = 404
    end
  end
  class PutMessage < Cuba; end
  PutMessage.define do
    on root, param('username'), param('password'), param('title'), param('textarea') do |username, password, title, textarea|
      generate_id = SecureRandom.uuid
      begin
        check_password = BCrypt::Password.new(user.where(username: username).get(:password)).is_password?(password)
        if check_password == true
          DB.transaction do
            data.insert(uuid: generate_id.to_s, username: username.to_s,
                        title: title.downcase.strip.tr(' ', '-').gsub(/[^\w-]/, ''),
                        created_on: Time.now.to_i, edited_on: 0, textarea: textarea.to_s)
            revision.insert(uuid: generate_id.to_s, username: username.to_s,
                            title: title.downcase.strip.tr(' ', '-').gsub(/[^\w-]/, ''),
                            created_on: Time.now.to_i, edited_on: 0, textarea: textarea.to_s)
          end
          res.redirect("/message/get/#{title.downcase.strip.tr(' ', '-').gsub(/[^\w-]/, '')}")
        elsif check_password == false
          res.redirect('/put_error')
        end
      rescue BCrypt::Errors::InvalidHash
        res.redirect('/put_error')
      end
    end
  end

  class Login < Cuba; end
  API::Login.use Rack::Cerberus, forgot_password_uri: nil, session_key: 'user' do |login, pass|
    check_password = BCrypt::Password.new(user.where(username: login).get(:password)).is_password?(pass)
    if check_password == true
      login == user.where(username: login).get(:username).to_s && BCrypt::Password.new(user.where(username: login).get(:password)).to_s
    elsif check_password == false
      print 'invaild-pass'
    end
  rescue BCrypt::Errors::InvalidHash
    print 'invaild-login'
  end
  Login.define do
    on root do
      res.redirect('/')
    end
    on 'secert' do
      run API::GetMessage
    end
    on 'hello' do
      on root do
        res.write('bye')
      end
    end
  end

  class SignUp < Cuba; end
  SignUp.define do
    on root, param('username'), param('password') do |username, password|
      checker = PasswordBlacklist::Checker.new
      if user.where(username: username).first
        @used_username = '<small> * Username already in use </small>'
        res.status = 500
        res.write view('/signup')
      elsif checker.blacklisted?(password) == true
        @blacklist_password = '<small> * The password provided is blacklisted </small>'
        res.status = 500
        res.write view('/signup')
      else
        bcrypted_password = BCrypt::Password.create(password)
        user.insert(username: username, password: bcrypted_password)
        hit_status = res.status = 200
        res.redirect('/') if hit_status
      end
    end
  end
end
