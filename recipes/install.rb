#
# Cookbook Name:: chef_haproxy
# Recipe:: install
#
# Copyright (C) 2016 Raintank, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

include_recipe "haproxy::default"
include_recipe "haproxy::install_package"

local_zone = node['gce']['instance']['zone'] || "root"

node['chef_haproxy']['haproxy_services'].each do |service|
  search_str = service[:search] || "tags:#{service[:tag]} AND chef_environment:#{node.chef_environment}"
  members = search("node", search_str) || []
  next if members.empty?

  members.map! do |member|
    server_ip = begin
      if member.attribute?('cloud_v2')
	if node.attribute?('cloud_v2') && (member['cloud_v2']['provider'] == node['cloud_v2']['provider'])
          if member['cloud_v2']['local_ipv4'].is_a?(Array)
            member['cloud_v2']['local_ipv4'].first
          else
            member['cloud_v2']['local_ipv4']
          end
        else
          member['cloud_v2']['public_ipv4']
        end
      else
        member['ipaddress']
      end
    end
    {:ipaddress => server_ip, :hostname => member['hostname'], :zone => member['gce']['instance']['zone'] || "root"}
  end

  members.sort! do |a,b|
    a[:hostname].downcase <=> b[:hostname].downcase
  end

  servers = members.uniq.map do |s|
    if s[:zone] == local_zone
      "#{s[:hostname]} #{s[:ipaddress]}:#{service[:bind_port]} weight 1 maxconn 300 check"
    elsif !service[:no_backup]
      "#{s[:hostname]} #{s[:ipaddress]}:#{service[:bind_port]} weight 1 maxconn 300 check backup"
    end
  end
  servers.compact!

  fe_bind_port = service[:fe_bind_port] || service[:bind_port]

  unless servers.nil?
    frontend_parms = [ "maxconn #{service[:maxconn]}", "bind 0.0.0.0:#{fe_bind_port}", "default_backend servers-#{service[:tag]}" ]
    frontend_parms += service[:frontend_extra] if !service[:frontend_extra].nil?
    backend_parms = [ "maxconn #{service[:maxconn]}", "balance #{service[:balance]}" ]
    backend_parms += service[:backend_extra] if !service[:backend_extra].nil?

    haproxy_lb service[:tag] do
      type 'frontend'
      mode service[:mode]
      params(
	frontend_parms
      )
    end

    haproxy_lb "servers-#{service[:tag]}" do
      type 'backend'
      mode service[:mode]
      servers servers
      params (
	backend_parms
      )
    end
  end
end

    

template "#{node['haproxy']['conf_dir']}/haproxy.cfg" do
  source "haproxy.cfg.erb"
  cookbook "haproxy"
  owner "root"
  group "root"
  mode 00644
  notifies :reload, "service[haproxy]"
  variables(
    :defaults_options => haproxy_defaults_options,
    :defaults_timeouts => haproxy_defaults_timeouts
  )
end

tag("haproxy")

include_recipe "logrotate"
logrotate_app "haproxy" do
  path "/var/log/haproxy.log"
  frequency "daily"
  options   ['missingok', 'compress', 'delaycompress', 'notifempty']
  rotate 7
  postrotate "invoke-rc.d rsyslog rotate >/dev/null 2>&1 || true"
  enable true
end

service "rsyslog" do
  action :nothing
  supports [ :restart => true ]
end

# remove the default rsyslog config file. The filename needs
# to be prefixed with a number so it runs before the 50-default.conf
file "/etc/rsyslog.d/haproxy.conf" do
  action :delete
  notifies :restart, 'service[rsyslog]', :delayed
end

# put the new rsyslog in place.
cookbook_file '/etc/rsyslog.d/20-haproxy.conf' do
  source "20-haproxy.conf"
  owner 'root'
  group 'root'
  mode '0644'
  action :create
  notifies :restart, 'service[rsyslog]', :delayed
end

