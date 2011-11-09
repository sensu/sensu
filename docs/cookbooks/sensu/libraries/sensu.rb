module Sensu

  def self.generate_config(node, databag)
    config = Hash.new

    config.merge!(node.sensu.to_hash.reject {|key,value| %w[user version].include? key})

    address = (node.has_key? :ec2) ? node.ec2.public_ipv4 : node.ip_address

    config['client'].merge!({
      :name => node.name,
      :address => address,
      :subscriptions => node.roles
    })

    config.merge!(databag.reject {|key,value| %w[id chef_type data_bag].include? key})

    JSON.pretty_generate(config)
  end

  def self.is_windows(node)
    node.platform == "windows" ? true : false
  end

end
