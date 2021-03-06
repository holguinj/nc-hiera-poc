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

  def hiera_data_from_classifier(node)
    name = node.name
    environment = node.environment_name
    node = Puppet::Node.indirection.find(name, :environment => environment)
    return HieraNodeAdapter.get(node).hiera_data
  end

  def classifier_data(options, context)
    node = closure_scope.compiler.node
    hiera_data = HieraNodeAdapter.get(node).hiera_data # will be nil if the node is not adapted
    hiera_data ||= hiera_data_from_classifier(node)
    context.cache_all(hiera_data)
    hiera_data
  end
end
