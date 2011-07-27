module SAM

  def self.generate_config(node, databag)
    config = Hash.new

    config.merge!(node.sa-monitoring.to_hash)

    address = (node.has_key? :ec2) ? node.ec2.public_ipv4 : node.ip_address

    config.merge!({
      :client => {
        :name => node.name,
        :address => address,
        :subscriptions => node.roles
      }
    })

    config.merge!(databag)

    JSON.pretty_generate(config)
  end

end
