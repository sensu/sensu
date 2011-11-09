#!/usr/bin/env ruby

require 'json'
puts "Running generate_databag.rb to generate ssl databag"

def process_pem(filename)
  output = ""
  File.open(filename).each_line do |line|
    output << line #unless line.include?("-----")
  end
  output
end

databag_json = {:id => "ssl",
                :server => { :key => process_pem("server/key.pem"),
                             :cert => process_pem("server/cert.pem"),
                             :cacert => process_pem("testca/cacert.pem")},
                :client => { :key => process_pem("client/key.pem"),
                             :cert => process_pem("client/cert.pem")}
               }

File.open("ssl.json","w") { |f| f.puts JSON.pretty_generate(databag_json)}
puts "Note: ssl.json data bag has been created to replace the existing one in dist."
