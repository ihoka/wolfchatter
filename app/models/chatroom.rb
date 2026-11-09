class Chatroom < ApplicationRecord
  has_many :messages, dependent: :destroy

  after_create_commit do
    # Enqueue first: a failing broadcast must not leave the room without a geocode job.
    GeocodeChatroomJob.perform_later(self)
    broadcast_append_to "chatrooms", target: "live_markers",
                                     partial: "chatrooms/marker",
                                     locals: { chatroom: self, id_suffix: :live_marker }
  end

  after_update_commit if: :saved_change_to_place_name? do
    broadcast_replace_to self, target: ActionView::RecordIdentifier.dom_id(self, :title),
                               partial: "chatrooms/title", locals: { chatroom: self }
    # Fetched pins (in #markers) and live-broadcast pins (in #live_markers) use different element
    # ids, so each gets its own replace. The panel's copy (panel_marker) is not replaced; the map
    # re-titles the existing pin.
    %i[marker live_marker].each do |id_suffix|
      broadcast_replace_to "chatrooms", target: ActionView::RecordIdentifier.dom_id(self, id_suffix),
                                        partial: "chatrooms/marker",
                                        locals: { chatroom: self, id_suffix: id_suffix, role: "set" }
    end
  end

  validates :latitude, presence: true,
                       numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, presence: true,
                        numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }

  validates :place_name, length: { maximum: ReverseGeocoder::MAX_LENGTH }, allow_nil: true

  def recent_messages(limit = 100)
    messages.order(created_at: :desc, id: :desc).limit(limit).reverse
  end

  def title
    place_name.presence || "Chatroom #{id}"
  end
end
