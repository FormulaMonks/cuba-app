module Helpers
  def current_user
    authenticated(User)
  end

  def mote_vars(content)
    super.merge(current_user: current_user)
  end
end
