require 'digest/sha1'
require 'json'
require 'net/http'
require 'uri'

require 'erubis'
require 'mysql2'
require 'mysql2-cs-bind'
require 'rack/utils'
require 'sinatra/base'
require 'tilt/erubis'

require 'dalli'

module Isuda
  class Web < ::Sinatra::Base
    enable :protection
    enable :sessions

    set :erb, escape_html: true
    set :public_folder, File.expand_path('../../../../public', __FILE__)
    set :db_user, ENV['ISUDA_DB_USER'] || 'root'
    set :db_password, ENV['ISUDA_DB_PASSWORD'] || ''
    set :dsn, ENV['ISUDA_DSN'] || 'dbi:mysql:db=isuda'
    set :session_secret, 'tonymoris'
    set :isupam_origin, ENV['ISUPAM_ORIGIN'] || 'http://localhost:5050'
    set :isutar_origin, ENV['ISUTAR_ORIGIN'] || 'http://localhost:5001'

    configure :development do
      require 'sinatra/reloader'

      register Sinatra::Reloader
    end

    set(:set_name) do |value|
      condition {
        @user_id ||= session[:user_id]
        if @user_id 
          @user_name ||= session[:user_name]
          halt(403) unless @user_name
        end
      }
    end

    set(:authenticate) do |value|
      condition {
        halt(403) unless @user_id
      }
    end

    helpers do
      def db
        Thread.current[:db] ||=
          begin
            _, _, attrs_part = settings.dsn.split(':', 3)
            attrs = Hash[attrs_part.split(';').map {|part| part.split('=', 2) }]
            mysql = Mysql2::Client.new(
              username: settings.db_user,
              password: settings.db_password,
              database: attrs['db'],
              encoding: 'utf8mb4',
              init_command: %|SET SESSION sql_mode='TRADITIONAL,NO_AUTO_VALUE_ON_ZERO,ONLY_FULL_GROUP_BY'|,
            )
            mysql.query_options.update(symbolize_keys: true)
            mysql
          end
      end

      def dalli
        Thread.current[:mc] ||= Dalli::Client.new('127.0.0.1:11211')
      end

      def register(name, pw)
        chars = [*'A'..'~']
        salt = 1.upto(20).map { chars.sample }.join('')
        salted_password = encode_with_salt(password: pw, salt: salt)
        db.xquery(%|
          INSERT INTO user (name, salt, password, created_at)
          VALUES (?, ?, ?, NOW())
        |, name, salt, salted_password)
        db.last_id
      end

      def encode_with_salt(password: , salt: )
        Digest::SHA1.hexdigest(salt + password)
      end

      def is_spam_content(content)
        hash = Digest::MD5.hexdigest(content)
        body = dalli.get("isupam_#{hash}")
        if !body
          isupam_uri = URI(settings.isupam_origin)
          res = Net::HTTP.post_form(isupam_uri, 'content' => content)
          body = res.body
          dalli.set("isupam_#{hash}", body)
        end

        validation = JSON.parse(body)
        ! validation['valid']
      end

      def bigram(content)
        characters = content.split(//u)
        return [content] if characters.size <= 2
        return characters.each_cons(2).collect(&:join).uniq
      end

      def htmlify(content)
        chars = bigram(content)
        keywords = db.xquery(%| select `escaped` from keyword where prefix in (?) order by character_length(name) desc |, chars)
        pattern = keywords.map {|k| k[:escaped] }.join('|')

        hash = Digest::MD5.hexdigest(content + pattern)
        html = dalli.get("html_#{hash}")

        if !html
          kw2hash = {}
          hashed_content = content.gsub(/(#{pattern})/) {|m|
            matched_keyword = $1
            "$$#{matched_keyword}$$".tap do |hash|
              kw2hash[matched_keyword] = hash
            end
          }
          escaped_content = Rack::Utils.escape_html(hashed_content)
          kw2hash.each do |(keyword, hash)|
            keyword_url = url("/keyword/#{Rack::Utils.escape_path(keyword)}")
            anchor = '<a href="%s">%s</a>' % [keyword_url, Rack::Utils.escape_html(keyword)]
            escaped_content.gsub!(hash, anchor)
          end

          html = escaped_content.gsub(/\n/, "<br />\n")
          dalli.set("html_#{hash}", html)
        end

        html
      end

      def uri_escape(str)
        Rack::Utils.escape_path(str)
      end

      def load_stars(keyword)
        db.xquery(%| select user_name from star where keyword = ? |, keyword).map { |r| r[:user_name] }
      end

      def load_stars_by_entries(entries)
        stars = {}

        keywords = entries.map { |e| e[:keyword] }.uniq
        keywords.each do |keyword|
          stars[keyword] = []
        end

        db.xquery(%| select user_name, keyword from star where keyword IN (?) |, keywords).each do |star|
          stars[star[:keyword]] << star[:user_name]
        end
        stars
      end

      def redirect_found(path)
        redirect(path, 302)
      end
    end

    get '/initialize' do
      db.xquery(%| DELETE FROM entry WHERE id > 7101 |)
      db.xquery('TRUNCATE star')

      content_type :json
      JSON.generate(result: 'ok')
    end

    get '/insert_escaped_column' do
      db.xquery('SELECT name FROM keyword').to_a.each do |keyword|
        db.xquery(%|
          UPDATE `keyword` SET `escaped` = ? WHERE `name` = ?
        |, Regexp.escape(keyword[:name]), keyword[:name])
      end

      content_type :json
      JSON.generate(result: 'ok')
    end

    get '/', set_name: true do
      per_page = 10
      page = (params[:page] || 1).to_i

      entries = db.xquery(%|
        SELECT * FROM entry
        ORDER BY updated_at DESC
        LIMIT #{per_page}
        OFFSET #{per_page * (page - 1)}
      |)

      stars = load_stars_by_entries(entries)
      entries.each do |entry|
        entry[:html] = htmlify(entry[:description])
        entry[:stars] = stars[entry[:keyword]]
      end

      total_entries = db.xquery(%| SELECT count(*) AS total_entries FROM entry |).first[:total_entries].to_i

      last_page = (total_entries.to_f / per_page.to_f).ceil
      from = [1, page - 5].max
      to = [last_page, page + 5].min
      pages = [*from..to]

      locals = {
        entries: entries,
        page: page,
        pages: pages,
        last_page: last_page,
      }
      erb :index, locals: locals
    end

    get '/robots.txt' do
      halt(404)
    end

    get '/register', set_name: true do
      erb :register
    end

    post '/register' do
      name = params[:name] || ''
      pw   = params[:password] || ''
      halt(400) if (name == '') || (pw == '')

      user_id = register(name, pw)
      session[:user_id] = user_id
      session[:user_name] = name

      redirect_found '/'
    end

    get '/login', set_name: true do
      locals = {
        action: 'login',
      }
      erb :authenticate, locals: locals
    end

    post '/login' do
      name = params[:name]
      user = db.xquery(%| select * from user where name = ? |, name).first
      halt(403) unless user
      halt(403) unless user[:password] == encode_with_salt(password: params[:password], salt: user[:salt])

      session[:user_id] = user[:id]
      session[:user_name] = name

      redirect_found '/'
    end

    get '/logout' do
      session[:user_id] = nil
      session[:user_name] = nil
      redirect_found '/'
    end

    post '/keyword', set_name: true, authenticate: true do
      keyword = params[:keyword] || ''
      halt(400) if keyword == ''
      description = params[:description]
      halt(400) if is_spam_content(keyword) || is_spam_content(description)

      bound = [@user_id, keyword, description] * 2
      db.xquery(%|
        INSERT INTO entry (author_id, keyword, description, created_at, updated_at)
        VALUES (?, ?, ?, NOW(), NOW())
        ON DUPLICATE KEY UPDATE
        author_id = ?, keyword = ?, description = ?, updated_at = NOW()
      |, *bound)

      db.xquery(%|
        INSERT IGNORE INTO `keyword` (`name`, `prefix`, `escaped`) VALUES (?, ?, ?)
      |, keyword, keyword[0, 2], Regexp.escape(keyword))

      redirect_found '/'
    end

    get '/keyword/:keyword', set_name: true do
      keyword = params[:keyword] or halt(400)

      entry = db.xquery(%| select * from entry where keyword = ? |, keyword).first or halt(404)
      entry[:stars] = load_stars(entry[:keyword])
      entry[:html] = htmlify(entry[:description])

      locals = {
        entry: entry,
      }
      erb :keyword, locals: locals
    end

    post '/keyword/:keyword', set_name: true, authenticate: true do
      keyword = params[:keyword] or halt(400)
      is_delete = params[:delete] or halt(400)

      unless db.xquery(%| SELECT * FROM entry WHERE keyword = ? |, keyword).first
        halt(404)
      end

      db.xquery(%| DELETE FROM entry WHERE keyword = ? |, keyword)

      redirect_found '/'
    end

    post '/stars' do
      keyword = params[:keyword]

      # GET /keywords/:keywordをたたいていたところ
      db.xquery(%| select * from entry where keyword = ? |, keyword).first or halt(404)

      user_name = params[:user]
      db.xquery(%|
        INSERT INTO star (keyword, user_name, created_at)
        VALUES (?, ?, NOW())
      |, keyword, user_name)

      content_type :json
      JSON.generate(result: 'ok')
    end
  end
end
