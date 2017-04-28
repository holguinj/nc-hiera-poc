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

  def classifier_data(options, context)
    path = '/tmp/' + context.interpolate('%{fqdn}') + '.yaml' # this is the only substantial change -JHH
    context.cached_file_data(path) do |content|
      begin
        data = YAML.load(content, path)
        # This is where we might want to delete the file at 'path'
        if data.is_a?(Hash)
          Puppet::Pops::Lookup::HieraConfig.symkeys_to_string(data)
        else
          Puppet.warning("#{path}: file does not contain a valid yaml hash")
          {}
        end
      rescue YAML::SyntaxError => ex
        # Psych errors includes the absolute path to the file, so no need to add that
        # to the message
        raise Puppet::DataBinding::LookupError, "Unable to parse #{ex.message}"
      end
    end
  end
end
