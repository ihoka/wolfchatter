module DisplayNameCookie
  extend ActiveSupport::Concern

  COOKIE_KEY = :display_name

  included do
    helper_method :current_display_name
  end

  # Nil when the cookie is missing or its signature does not verify.
  def current_display_name
    cookies.signed[COOKIE_KEY].presence
  end

  def remember_display_name(name)
    cookies.permanent.signed[COOKIE_KEY] = { value: name, httponly: true, same_site: :lax }
  end

  def forget_display_name
    cookies.delete(COOKIE_KEY)
  end
end
