require 'puppet/network/http_pool'
require 'json'

class Puppet::Node::Classifier < Puppet::Indirector::Code
  AgentSpecifiedEnvironment = "agent-specified"
  ClassificationConflict = 'classification-conflict'

  def self.load_config
    config_path = File.join(Puppet[:confdir], 'classifier.yaml')

    config = nil
    if File.exists?(config_path)
      config = YAML.load_file(config_path)
    else
      Puppet.warning("Classifier config file '#{config_path}' does not exist, using defaults")
      config = {}
    end

    if config.respond_to?(:to_ary)
      config.map do |service|
        merge_defaults(service)
      end
    else
      service = merge_defaults(config)
      [service]
    end
  end

  def find(request)
    name = request.key
    facts = Puppet::Node::Facts.indirection.find(name, :environment => request.environment)

    fact_values = if facts.nil?
                    {}
                  else
                    facts.sanitize
                    facts.to_data_hash['values']
                  end

    trusted_data = Puppet.lookup(:trusted_information) do
      # This block contains a default implementation for trusted
      # information. It should only get invoked if the node is local
      # (e.g. running puppet apply)
      temp_node = Puppet::Node.new(name)
      temp_node.parameters['clientcert'] = Puppet[:certname]
      Puppet::Context::TrustedInformation.local(temp_node)
    end

    trusted_data_values = if trusted_data.nil?
                            {}
                          else
                            trusted_data.to_h
                          end

    facts = {"fact" => fact_values,
             "trusted" => trusted_data_values}

    if request.options.include?(:transaction_uuid)
      facts["transaction_uuid"] = request.options[:transaction_uuid]
    end

    requested_environment = request.options[:configured_environment] || request.environment

    services.each do |service|
      result = retrieve_classification(name, facts, requested_environment, service)
      if result.is_a? Puppet::Node
        return result
      elsif result.respond_to?(:[]) and result['kind'] == ClassificationConflict
        # got a classification conflict
        msg = result['msg']
        Puppet.err(msg)
        raise Puppet::Error, msg
      end
    end

    # got neither a valid classification nor a classification conflict, so all the services are
    # unreachable or having unforeseen problems
    msg = "Classification of #{name} failed due to a Node Manager service error. Please check /var/log/puppetlabs/console-services/console-services.log on the node(s) running the Node Manager service for more details."
    Puppet.err(msg)
    raise Puppet::Error, msg
  end

  private

  def new_connection(service)
    Puppet::Network::HttpPool.http_instance(service[:server], service[:port])
  end

  # Attempt to retrieve classification from the NC service. Returns the
  # classification if successfully retrieved, the parsed conflict error response
  # in the case of a classification conflict, otherwise nil if the case of
  # a connection error, timeout, or non-conflict 5xx response.
  def retrieve_classification(node_name, node_facts, requested_environment, service)
    begin
      connection = new_connection(service)
      request_path = "#{normalize_prefix(service[:prefix])}/v1/classified/nodes/#{node_name}"

      response = connection.post(request_path,
                                 node_facts.to_json,
                                 {'Content-Type' => 'application/json'},
                                 {:metric_id => [:classifier, :nodes, node_name]})
    rescue SocketError => e
      Puppet.warning("Could not connect to the Node Manager service at #{service_url(service)}: #{e.inspect}")
      return nil
    end

    result = JSON.parse(response.body)

    unless response.is_a? Net::HTTPSuccess
      if result['kind'] == ClassificationConflict
        explanation = result['msg'].sub(" See the `details` key for all conflicts.", "")
        msg = "Classification of #{node_name} failed due to a classification conflict: #{explanation}"
        return result.merge({'msg' => msg})
      else
        Puppet.warning("Received an unexpected error response from the Node Manager service at #{service_url(service)}: #{response.code} #{response.msg}")
        return nil
      end
    end

    result['classes'] = Hash[result['classes'].sort]
    is_agent_specified = (result["environment"] == AgentSpecifiedEnvironment)
    result.delete("environment") if is_agent_specified

    node = Puppet::Node.from_data_hash(result)
    node.environment = requested_environment if is_agent_specified
    node.fact_merge

    dummy_hiera_data(node_facts, {"thing" => "present and accounted for", "this_is" => "working"})

    return node
  end

  def config
    @config ||= Puppet::Node::Classifier.load_config
  end

  def services
    config
  end

  def service_url(service)
    "https://#{service[:server]}:#{service[:port]}#{service[:prefix]}"
  end

  def normalize_prefix(prefix)
    prefix.chomp('/')
  end

  def self.merge_defaults(service)
    {
      :server => service["server"] || 'classifier',
      :port => service["port"] || 1262,
      :prefix => service["prefix"] || '',
    }
  end

  def dummy_hiera_data(node_facts, hiera_data)
    node_name = node_facts['fact']['fqdn'] || 'unknown_node'
    path = '/tmp/' + node_name + '.yaml'
    File.open(path, 'w') { |file| file.write(hiera_data.to_yaml) }

    # Preemptive debugging
    if node_name == 'unknown_node'
      File.open('/tmp/node_data.yaml', 'w') { |file| file.write(node_facts.to_yaml) }
    end

  end

end
