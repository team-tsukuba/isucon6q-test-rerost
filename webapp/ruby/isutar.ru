#!rackup

require_relative './lib/isutar/web.rb'

run Isutar::Web
config.middleware.use Rack::Lineprof
