# @since 4.8.0
#

# This file is shamelessly ripped off from:
#  lib/puppet/functions/yaml_data.rb
require 'yaml'

Puppet::Functions.create_function(:classifier_data) do
  dispatch :classifier_data do
    param 'Struct[{fuck=>String[1]}]', :options
    param 'Puppet::LookupContext', :context
  end

  def call_classifier_terminus()
    #todo
    {"message" => "hiera_data was nil"}
  end

  def classifier_data(options, context)
    node = closure_scope.compiler.node
    hiera_data = HieraNodeAdapter.get(node).hiera_data # will be nil if the node is not adapted
    hiera_data ||= call_classifier_terminus()
    context.cache_all(hiera_data)
    hiera_data
  end
end
