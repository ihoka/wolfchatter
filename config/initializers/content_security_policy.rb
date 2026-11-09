# Be sure to restart your server when you modify this file.

# Content Security Policy. Inline scripts and styles are allowed only through
# the per-request nonce; there is no 'unsafe-inline'. Tiles come from
# OpenStreetMap, everything else from our own origin.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.img_src     :self, :data, "https://tile.openstreetmap.org"
    policy.script_src  :self
    policy.style_src   :self
    policy.connect_src :self
    policy.object_src  :none
    policy.base_uri    :self
    policy.frame_ancestors :none
    policy.form_action :self
  end

  # The nonce is per session, not per request: the browser keeps the CSP header of
  # the first full page load, while Turbo Drive swaps in the csp-nonce meta of each
  # later page. A per-request nonce would not match the kept header. The session id
  # is not used because it is empty for a new visitor; a random value stored in the
  # session is generated once, and writing it makes the session cookie persist.
  config.content_security_policy_nonce_generator = ->(request) { request.session[:csp_nonce] ||= SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
