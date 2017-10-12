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
require 'redis'
require 'json'

#require 'newrelic_rpm'
require 'rack-mini-profiler'
require 'rack-lineprof'

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
      use Rack::MiniProfiler
      use Rack::Lineprof
      use Rack::Logger
    end

    set(:set_name) do |value|
      condition {
        user_id = session[:user_id]
        logger.info session
        if user_id
          user = db.xquery(%| select name from user where id = ? |, user_id).first
          @user_id = user_id
          @user_name = user[:name]
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

      def redis
        Thread.current[:redis] ||=
          begin
            Redis.new()
          end
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
        isupam_uri = URI(settings.isupam_origin)
        res = Net::HTTP.post_form(isupam_uri, 'content' => content)
        validation = JSON.parse(res.body)
        validation['valid']
        ! validation['valid']
      end

      def htmlify(content)
        return redis.get("htmlify:#{content}") if redis.get("htmlify:#{content}") && !redis.get("htmlify:#{content}").empty?
        keywords = redis.get("content") && !redis.get("content").empty? ? JSON.parse(redis.get("content")) : db.xquery(%| select keyword, regrex_escape from entry order by keyword_length desc |)
        pattern = keywords.map {|k| k["regrex_escape"] || k[:regrex_escape] ? k["regrex_escape"] || k[:regrex_escape] : Regexp.escape(k["keyword"] || k[:keyword]) }.join('|')
        kw2hash = {}
        hashed_content = content.gsub(/(#{pattern})/) {|m|
          matched_keyword = $1
          "isuda_#{Digest::SHA1.hexdigest(matched_keyword)}".tap do |hash|
            kw2hash[matched_keyword] = hash
          end
        }
        escaped_content = Rack::Utils.escape_html(hashed_content)
        kw2hash.each do |(keyword, hash)|
          keyword_url = url("/keyword/#{Rack::Utils.escape_path(keyword)}")
          anchor = '<a href="%s">%s</a>' % [keyword_url, Rack::Utils.escape_html(keyword)]
          escaped_content.gsub!(hash, anchor)
        end
        ans = escaped_content.gsub(/\n/, "<br />\n")
        redis.set("htmlify:#{content}", ans)
        ans
      end

      def uri_escape(str)
        Rack::Utils.escape_path(str)
      end

      def load_stars(keyword)
        #db.xquery(%| select user_name from star where keyword = ? |, keyword)
        redis.lrange("star:#{keyword}", 0, -1)
      end

      def redirect_found(path)
        redirect(path, 302)
      end
    end

    get '/initialize' do
      db.xquery(%| DELETE FROM entry WHERE id > 7101 |)
      db.xquery('TRUNCATE star')
      json = db.xquery(%| select keyword, regrex_escape from entry order by keyword_length desc |).to_a.to_json
      redis.set("content", json)
      redis.zremrangebyscore("entries:orderby_updated_at", "-inf", "+inf")
      entries = db.xquery(%|
        SELECT keyword, description, updated_at FROM entry
        WHERE id IN (SELECT id FROM (
            SELECT id
            FROM entry
            ORDER BY updated_at DESC
          ) AS S
        )
      |)
      entries.each { |entry|
        redis.zadd("entries:orderby_updated_at", -1 * entry[:updated_at].to_i, {keyword: entry[:keyword], description: entry[:description]}.to_json)
      }
      json = db.xquery(%| select keyword, regrex_escape from entry order by keyword_length desc |).to_a.to_json
      redis.set("content", json)

      redis.flushall

      content_type :json
      JSON.generate(result: 'ok')
    end

    get '/test' do
      entries = db.xquery(%|
        SELECT keyword, description, updated_at FROM entry
        WHERE id IN (SELECT id FROM (
            SELECT id
            FROM entry
            ORDER BY updated_at DESC
          ) AS S
        )
      |)
      entries.each { |entry|
        redis.zadd("entries:orderby_updated_at", -1 * entry[:updated_at].to_i, {keyword: entry[:keyword], description: entry[:description]}.to_json)
      }
      content_type :json
      JSON.generate(result: 'ok')
    end

    get '/test_remove' do
      redis.zremrangebyscore("entries:orderby_updated_at", "-inf", "+inf")

      content_type :json
      JSON.generate(result: 'ok')
    end

    get '/', set_name: true do
      per_page = 10
      page = (params[:page] || 1).to_i

      entries = redis.zrangebyscore("entries:orderby_updated_at", "-inf", "+inf", limit: [per_page * (page - 1), per_page * page])
      entries = entries.map do |entry|
        entry = JSON.parse(entry)
        entry["html"] = htmlify(entry["description"])
        entry["stars"] = load_stars(entry["keyword"])
        entry
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
      password = params[:password]
      if redis.get("user:#{name}:password:#{password}") && !redis.get("user:#{name}:password:#{password}").empty?
        session[:user_id] = redis.get("user:#{name}:password:#{password}")
      else
        user = db.xquery(%| select id, salt, password from user where name = ?|, name).first
        halt(403) unless user
        halt(403) unless user[:password] == encode_with_salt(password: params[:password], salt: user[:salt])
        redis.set("user:#{name}:password:#{password}", user[:id])
        session[:user_id] = user[:id]
      end

      redirect_found '/'
    end

    get '/logout' do
      session[:user_id] = nil
      redirect_found '/'
    end

    post '/keyword', set_name: true, authenticate: true do
      keyword = params[:keyword] || ''
      halt(400) if keyword == ''
      description = params[:description]
      halt(400) if is_spam_content(description) || is_spam_content(keyword)

      bound = [@user_id, keyword, description, keyword, Regexp.escape(keyword)] * 2
      db.xquery(%|
        INSERT INTO entry (author_id, keyword, description, created_at, updated_at, keyword_length, regrex_escape)
        VALUES (?, ?, ?, NOW(), NOW(), character_length(?), ?)
        ON DUPLICATE KEY UPDATE
        author_id = ?, keyword = ?, description = ?, updated_at = NOW(), keyword_length = character_length(?), regrex_escape = ?
      |, *bound)
      json = db.xquery(%| select keyword, regrex_escape from entry order by keyword_length desc |).to_a.to_json
      redis.set("content", json)

      redis.zadd("entries:orderby_updated_at", -1 * Time.now().to_i, {keyword: keyword, description: description}.to_json)
      redis.del(redis.keys("htmlify:*"))

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

      redis.set("entry:#{keyword}", 1)
      unless db.xquery(%| SELECT * FROM entry WHERE keyword = ? |, keyword).first
        halt(404)
      end

      db.xquery(%| DELETE FROM entry WHERE keyword = ? |, keyword)
      json = db.xquery(%| select keyword, regrex_escape from entry order by keyword_length desc |).to_a.to_json
      redis.set("content", json)

      redirect_found '/'
    end

    # migration from isutar
    get '/stars' do
      keyword = params[:keyword] || ''
      stars = load_stars(keyword)

      content_type :json
      JSON.generate(stars: stars)
    end

    post '/stars', set_name: true do
      keyword = params[:keyword]
      user_name = params[:user]
      halt(404) if db.xquery(%| SELECT COUNT(1) as cnt FROM entry WHERE keyword = ? |, keyword).first[:cnt] == 0
      redis.rpush("star:#{keyword}", user_name)

      content_type :json
      JSON.generate(result: 'ok')
    end
  end
end
