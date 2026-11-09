# Resolves a new chatroom's place name via Nominatim. The constant key makes
# the concurrency limit global, and the sleep spaces calls out to respect
# Nominatim's 1 request/second policy. No retry_on: the geocoder returns nil
# for expected failures, and the room keeps its fallback title.
class GeocodeChatroomJob < ApplicationJob
  limits_concurrency to: 1, key: "nominatim", duration: 1.minute

  discard_on ActiveJob::DeserializationError

  def perform(chatroom)
    return if chatroom.place_name.present?

    begin
      name = ReverseGeocoder.new.place_name(chatroom.latitude, chatroom.longitude)
      chatroom.update!(place_name: name) if name
    ensure
      sleep Rails.configuration.x.nominatim.throttle
    end
  end
end
