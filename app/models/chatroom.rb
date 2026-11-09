class Chatroom < ApplicationRecord
  has_many :messages, dependent: :destroy

  after_create_commit do
    broadcast_append_to "chatrooms", target: "markers",
                                     partial: "chatrooms/marker", locals: { chatroom: self }
    GeocodeChatroomJob.perform_later(self)
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
