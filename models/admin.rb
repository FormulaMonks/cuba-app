class Admin < Sequel::Model
  include Shield::Model

  def self.fetch(identifier)
    filter(email: identifier).first
  end
end
