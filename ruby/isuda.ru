#!rackup

require_relative './lib/isuda/web.rb'

require 'stackprof'
use StackProf::Middleware,
  enabled: true,
  mode: :wall,
  raw: true,
  interval: 10,
  save_every: 100
  path: './stackprof'

run Isuda::Web


