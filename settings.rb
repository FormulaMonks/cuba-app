module Settings
  File.read("env.sh").scan(/(.*?)="?(.*)"?$/).each do |key, value|
    ENV[key] ||= value
  end

  MAIL_FROM   = ENV["MAIL_FROM"]
  REDIS_URL   = ENV["REDIS_URL"]
  MALONE_URL  = ENV["MALONE_URL"]
  HOST        = ENV["APP_HOST"]
  NAME        = ENV["APP_NAME"]
  DESCRIPTION = ENV["APP_DESCRIPTION"]
  AUTHOR      = ENV["APP_AUTHOR"]
end
