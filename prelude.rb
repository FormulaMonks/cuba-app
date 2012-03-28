module Prelude
  File.read("env.sh").scan(/(.*?)="?(.*)"?$/).each do |key, value|
    ENV[key] ||= value
  end

  HOST       = ENV["APP_HOST"]
  MAIL_FROM  = ENV["MAIL_FROM"]
  REDIS_URL  = ENV["REDIS_URL"]
  MALONE_URL = ENV["MALONE_URL"]
end
