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
  end

  # Generate per-request nonces for the importmap, inline scripts and inline styles.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src style-src]
end
