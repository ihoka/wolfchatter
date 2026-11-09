# Turns coordinates into a short place name using Nominatim.
# Returns nil on any failure so callers can leave the room unnamed.
class ReverseGeocoder
  ENDPOINT = "https://nominatim.openstreetmap.org/reverse"
  MAX_LENGTH = 120
  LOCALITY_KEYS = %w[city town village municipality county state].freeze
  NETWORK_ERRORS = [
    Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError,
    OpenSSL::SSL::SSLError, JSON::ParserError,
    EOFError, IOError, Net::ProtocolError, Net::HTTPBadResponse,
    Net::HTTPHeaderSyntaxError, Zlib::Error
  ].freeze

  def place_name(latitude, longitude)
    data = fetch(latitude, longitude)
    format_name(data)&.truncate(MAX_LENGTH)
  rescue *NETWORK_ERRORS => e
    Rails.logger.warn("ReverseGeocoder failed: #{e.class}: #{e.message}")
    nil
  end

  private

  def fetch(latitude, longitude)
    uri = URI(ENDPOINT)
    uri.query = URI.encode_www_form(
      format: "jsonv2", lat: latitude, lon: longitude, zoom: 10, addressdetails: 1
    )
    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = Rails.application.config.x.nominatim.user_agent
    request["Accept-Language"] = "en"

    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 2, read_timeout: 3) do |http|
      http.request(request)
    end
    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("ReverseGeocoder got HTTP #{response.code}")
      return nil
    end
    JSON.parse(response.body)
  end

  def format_name(data)
    return nil unless data.is_a?(Hash)
    address = data["address"].is_a?(Hash) ? data["address"] : {}
    locality = LOCALITY_KEYS.filter_map { |key| address[key].presence }.first
    parts = [ locality, address["country"].presence ].compact
    return parts.join(", ") if parts.any?
    data["display_name"].presence
  end
end
