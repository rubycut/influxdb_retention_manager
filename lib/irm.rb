require 'rubygems'
require 'bundler/setup'
require 'awesome_print'
require "thor"
require 'json'
require 'yaml'
require 'pp'

class Irm < Thor
  method_option :host, default: "127.0.0.1", aliases: %w[-h]
  method_option :database, required: true, aliases: %w[-d]
  method_option :user, aliases: %w[-u]
  method_option :password, aliases: %w[-p]
  desc "recon", "Connect database and prepare config file"
  def recon
    auth = ""
    if options[:user] and options[:password]
      auth = "-u #{options[:user]}:#{options[:password]}"
    end
    json = `curl #{auth } -G 'http://#{options[:host]}:8086/query?pretty=true' --data-urlencode "db=#{options[:database] }" --data-urlencode "q=show tag keys"`
    hash = JSON.parse(json)
    ap hash
    yaml = {}
    yaml["measurements"] = {}
    hash["results"][0]["series"].collect do |series|
      yaml["measurements"][series["name"]] = {
        "tags" => series["values"].collect { |tag| tag[0]}
      }
    end
    json = `curl #{auth} -G 'http://#{options[:host]}:8086/query?pretty=true' --data-urlencode "db=#{options[:database]}" --data-urlencode "q=show field keys"`
    hash = JSON.parse(json)
    ap hash
    hash["results"][0]["series"].collect do |series|
      yaml["measurements"][series["name"]]["fields"] ||= {}
      series["values"].each { |tag| yaml["measurements"][series["name"]]["fields"][tag[0]] = "mean"}
    end
    yaml["database"] = options[:database]
    yaml["retention_policies"] = [
      {"name" => "biweekly", "duration" => "15d"},
      {"name" => "months3", "duration" => "92d", "precision" => "1m"},
      {"name" => "yearly", "duration" => "366d", "precision" => "5m"}
    ]

    File.open("#{options[:database]}.yaml","w") do |io|
      io << YAML.dump(yaml)
      puts "Recon written to: #{options[:database]}.yaml"
    end
  end
  method_option :database, required: true, aliases: %w[-d]
  desc "create_cq", "Generate influx qcommands"
  def create_cq
    hash = YAML.load_file("#{options[:database]}.yaml")
    hash["retention_policies"].each_index do |retention_policy_index|
      retention_policy = hash["retention_policies"][retention_policy_index]
      command = "CREATE RETENTION POLICY #{retention_policy["name"]} ON #{options[:database]} DURATION #{retention_policy["duration"]} REPLICATION 1"
      command << " DEFAULT" if retention_policy_index == 0
      puts command
    end
    hash["measurements"].each_pair do |measurement,measurement_hash|
      # migrate from DEFAULT retention policy first policy
      retention_policy = hash["retention_policies"][0]
      retention_name = retention_policy["name"]
      retention_time = retention_policy["duration"]
      prefix = "SELECT "
      fields = measurement_hash["fields"].collect do |field, function|
        "#{function}(#{field}) AS #{field}"
      end.join(", ")
      suffix = %Q| INTO #{options[:database]}."#{retention_name}".#{measurement} FROM #{options[:database]}."default".#{measurement} WHERE time > '2016-03-05' AND time < now() |
      tags = ""
      tags = %Q|GROUP BY time(15s), "#{measurement_hash["tags"].join(%Q[", "])}" fill(none)| unless measurement_hash["tags"].to_a.empty?

      puts "#{prefix}#{fields}#{suffix}#{tags}"
      # create CQ for moving data to all other policies
      hash["retention_policies"][1..-1].each_index do |retention_policy_index|
        retention_policy = hash["retention_policies"][retention_policy_index+1]
        retention_name = retention_policy["name"]
        retention_time = retention_policy["precision"]
        prefix = "CREATE CONTINUOUS QUERY #{measurement}_#{retention_name} ON #{options[:database]} BEGIN SELECT "
        fields = measurement_hash["fields"].collect do |field, function|
          "#{function}(#{field}) AS #{field}"
        end.join(", ")
        suffix = %Q| INTO #{options[:database]}."#{retention_name}".#{measurement} FROM #{options[:database]}."#{hash["retention_policies"][retention_policy_index]["name"]}".#{measurement} GROUP BY time(#{retention_time}) |
        tags = ""
        tags = %Q|, "#{measurement_hash["tags"].join(%Q[", "])}"|   unless measurement_hash["tags"].to_a.empty?
        puts "#{prefix}#{fields}#{suffix}#{tags} END"
      end
      puts "#################################### Done with: #{measurement}"
    end
  end
end

Irm.start(ARGV)