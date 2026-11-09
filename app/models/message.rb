class Message < ApplicationRecord
  MAX_BODY_LENGTH = 1000

  belongs_to :chatroom

  normalizes :author_name, :body, with: ->(value) { value.strip }

  validates :author_name, presence: true, length: { maximum: 40 }
  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }

  scope :chronological, -> { order(:created_at, :id) }
end
