module Github
  def self.included(mod)
    require 'libraries/hirb'
    require 'httparty'
  end

  def github_user(user='cldwalker')
    HTTParty.get("http://github.com/api/v2/json/repos/show/#{user}")
  end

  def github_user_table(user='cldwalker')
    table github_user(user)['repositories'].select {|e| !e['private']}, :fields=>%w{name watchers forks homepage description}
  end
end