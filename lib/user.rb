class User < Ohm::Model
  extend Shield::Model

  attribute :email
  attribute :crypted_password

  unique :email

  def self.fetch(identifier)
    with(:email, identifier)
  end

  def password=(password)
    self.crypted_password = Shield::Password.encrypt(password)
  end
end
