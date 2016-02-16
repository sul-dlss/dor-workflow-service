lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

require 'simplecov'
SimpleCov.start do
  add_filter 'spec'
end

require 'dor-workflow-service'
require 'equivalent-xml'
require 'equivalent-xml/rspec_matchers'

# RSpec.configure do |conf|
# end
