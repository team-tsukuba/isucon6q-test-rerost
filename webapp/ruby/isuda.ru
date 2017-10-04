#!rackup

require_relative './lib/isuda/web.rb'

run Isuda::Web
config.middleware.use Rack::Lineprof
