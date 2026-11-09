class Message < ApplicationRecord
  MAX_BODY_LENGTH = 1000

  belongs_to :chatroom

  after_create_commit do
    broadcast_append_to chatroom, target: ActionView::RecordIdentifier.dom_id(chatroom, :messages),
                                  partial: "messages/message", locals: { message: self }
  end

  normalizes :author_name, :body, with: ->(value) { value.strip }

  validates :author_name, presence: true, length: { maximum: DisplayName::MAX_LENGTH }
  validates :body, presence: true, length: { maximum: MAX_BODY_LENGTH }
end
