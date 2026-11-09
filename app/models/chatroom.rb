class Chatroom < ApplicationRecord
  has_many :messages, dependent: :destroy

  validates :latitude, presence: true,
                       numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }
  validates :longitude, presence: true,
                        numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }

  def recent_messages(limit = 100)
    messages.order(created_at: :desc, id: :desc).limit(limit).reverse
  end

  def title
    place_name.presence || "Chatroom #{id}"
  end
end
