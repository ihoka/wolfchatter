class Chatroom < ApplicationRecord
  has_many :messages, dependent: :destroy

  after_create_commit do
    # Enqueue first: a failing broadcast must not leave the room without a geocode job.
    GeocodeChatroomJob.perform_later(self)
    broadcast_append_to "chatrooms", target: "markers",
                                     partial: "chatrooms/marker", locals: { chatroom: self }
  end

  after_update_commit if: :saved_change_to_place_name? do
    broadcast_replace_to self, target: ActionView::RecordIdentifier.dom_id(self, :title), partial: "chatrooms/title", locals: { chatroom: self }
    # Replaces the #markers element only; the panel's copy has its own id and the map dedupes by room id.
    broadcast_replace_to "chatrooms", target: ActionView::RecordIdentifier.dom_id(self, :marker),
                                      partial: "chatrooms/marker", locals: { chatroom: self }
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
