class MessagesController < ApplicationController
  rate_limit to: 30, within: 1.minute, only: :create, with: :render_rate_limited
  before_action :set_chatroom

  # Turbo stream only: the panel frame advances history on redirects, so this
  # form never redirects. Other formats get 406.
  def create
    return render_name_form if current_display_name.blank?

    @message = @chatroom.messages.new(message_params.merge(author_name: current_display_name.to_s))
    respond_to do |format|
      format.turbo_stream do
        if @message.save
          render turbo_stream: [
            turbo_stream.append(helpers.dom_id(@chatroom, :messages), partial: "messages/message",
                                locals: { message: @message }),
            turbo_stream.replace(helpers.dom_id(@chatroom, :message_form), partial: "messages/form",
                                 locals: { chatroom: @chatroom, autofocus: true })
          ]
        else
          render turbo_stream: turbo_stream.replace(helpers.dom_id(@chatroom, :message_form),
                                                    partial: "messages/form",
                                                    locals: { chatroom: @chatroom, message: @message }),
                 status: :unprocessable_content
        end
      end
      format.any { head :not_acceptable }
    end
  end

  private

  def render_rate_limited
    set_chatroom
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          helpers.dom_id(@chatroom, :message_form),
          partial: "messages/form",
          locals: { chatroom: @chatroom, alert: "You're sending messages too fast — slow down a little." }
        ), status: :too_many_requests
      end
      format.any { head :too_many_requests }
    end
  end

  def render_name_form
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(helpers.dom_id(@chatroom, :compose),
                                                  partial: "chatrooms/compose",
                                                  locals: { chatroom: @chatroom }),
               status: :unprocessable_content
      end
      format.any { head :not_acceptable }
    end
  end

  def set_chatroom
    @chatroom = Chatroom.find(params.expect(:chatroom_id))
  end

  def message_params
    params.expect(message: :body)
  end
end
