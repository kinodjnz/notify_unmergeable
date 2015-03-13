#!/usr/bin/env ruby
# coding: utf-8

require 'net/https'
require 'io/console'
require 'json'

GITHUB_API_HOST = 'api.github.com'
CHATWORK_API_HOST = 'api.chatwork.com'

def get_pull_requests(owner, repository, user, password)
  begin
    mergeables = {}
    https = Net::HTTP.new(GITHUB_API_HOST, 443)
    https.use_ssl = true
    https.start {
      req = Net::HTTP::Get.new("/repos/#{owner}/#{repository}/pulls?per_page=100")
      req.basic_auth user, password
      response = https.request(req)
      if response.is_a?(Net::HTTPSuccess)
        prs = JSON.parse(response.body)
        prs.each{|pr|
          url = pr['url']
          html_url = pr['html_url']
          puts "#{html_url}"
          req = Net::HTTP::Get.new(url)
          req.basic_auth user, password
          response = https.request(req)
          if response.is_a?(Net::HTTPSuccess)
            pr = JSON.parse(response.body)
            mergeable = pr['mergeable']
            mergeables[html_url] = mergeable
          end
        }
      end
    }
    return mergeables
  rescue
    p $!
    return nil
  end
end

def update_settings(settings_file, settings)
  new_settings = nil
  begin
    File.open(settings_file){|f|
      new_settings = JSON.parse(f.read)
    }
  rescue
    p $!
  end
  if settings == nil
    settings = {}
  elsif new_settings == nil
    return settings
  end
  if not new_settings.has_key?('repositories')
    new_settings['repositories'] = []
  end
  if not new_settings.has_key?('interval')
    new_settings['interval'] = 300
  end
  if not new_settings.has_key?('owner')
    puts "owner not set"
    new_settings['owner'] = ''
  end
  return new_settings
end

def post_chatwork(settings, text)
  if not settings.has_key?('chatwork-room-no') or not settings.has_key?('chatwork-token')
    puts "chatwork token/room is not set"
    return
  end
  begin
    https = Net::HTTP.new(CHATWORK_API_HOST, 443)
    https.use_ssl = true
    https.start {
      room_no = settings['chatwork-room-no']
      req = Net::HTTP::Post.new("/v1/rooms/#{room_no}/messages")
      req['X-ChatWorkToken'] = settings['chatwork-token']
      req.body = "body=#{text}"
      https.request(req)
    }
  rescue
    p $!
  end
end

user = nil
settings_file = nil

if ARGV.length >= 3
  if ARGV[0] == '-u'
    ARGV.shift
    user = ARGV.shift
  end
end
if ARGV.length >= 1
  settings_file = ARGV.shift
end

if user == nil or settings_file == nil
  puts "usage: notify_unmergeable -u username settings_file"
  exit 1
end

print "input password for #{user}: "
password = STDIN.noecho(&:gets).chomp
puts ""

settings = {}
prev_mergeables = {}
prev_mergeables.default_proc = ->(h, k){h[k] = {}}
interval = 300
while true
  settings = update_settings(settings_file, settings)
  settings['repositories'].each{|repo|
    mergeables = get_pull_requests(settings['owner'], repo, user, password)
    p mergeables
    if mergeables != nil
      mergeables.each{|k, v|
        if prev_mergeables[repo].has_key?(k)
          if not v and prev_mergeables[repo][k]
            puts "Pull Requestがマージできなくなりました : #{k}"
            post_chatwork(settings, "[info][title]#{repo}[/title]Pull Requestがマージできなくなりました\r\n#{k}[/info]")
          elsif v and not prev_mergeables[repo][k]
            puts "Pull Requestがマージ可能になりました : #{k}"
          end
        elsif v
          puts "Pull Requestが発行されました : #{k}"
        end
      }
      prev_mergeables[repo] = mergeables
    end
  }
  interval = settings['interval']
  sleep(interval)
end
