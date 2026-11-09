class ChatroomsController < ApplicationController
  rate_limit to: 10, within: 1.minute, only: :create, with: :render_rate_limited

  def index
  end

  def show
    @chatroom = Chatroom.find(params[:id])
  end

  def create
    @chatroom = Chatroom.new(chatroom_params)
    if @chatroom.save
      redirect_to @chatroom, status: :see_other
    else
      render :errors, status: :unprocessable_content
    end
  end

  private

  def render_rate_limited
    response.set_header("Retry-After", "60")
    render :rate_limited, status: :too_many_requests
  end

  def chatroom_params
    params.expect(chatroom: %i[latitude longitude])
  end
end
