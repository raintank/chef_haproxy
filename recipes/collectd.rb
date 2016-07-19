#
# Cookbook Name:: chef_haproxy
# Recipe:: collectd
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

package "ruby"

directory "/usr/share/collectd/plugins" do
  recursive true
  owner 'root'
  group 'root'
  mode '0755'
  only_if { node['use_collectd'] }
end

haproxy_hostname = node.name.sub /\.raintank\.io$/, ''

svcs = node['chef_haproxy']['haproxy_services'].map { |s| s[:tag] }

if node['use_collectd'] && node['collectd']['plugins']['exec']
  execs = []
  svcs.each do |t|
    execs.push %Q("haproxy" "/usr/share/collectd/plugins/haproxy" "-s" "/var/run/haproxy.sock" "-i" "#{haproxy_hostname}" "-n" "#{t}" "-w" "10" "-e" "servers-#{t}" )
  end
  node.set['collectd']['plugins']['exec']['config']['Exec'] = execs
end
cookbook_file "/usr/share/collectd/plugins/haproxy" do
  source 'haproxy.rb'
  owner 'root'
  group 'root'
  mode '0755'
  only_if { node['use_collectd'] }
  action :create  
end

node.set["collectd_personality"] = "haproxy"
include_recipe "chef_base::collectd"
