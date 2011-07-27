module SAM

  def self.generate_config(node, checks)
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

    return config
  end

end
