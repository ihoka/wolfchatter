class ChatroomsController < ApplicationController
  def index
    @chatrooms = Chatroom.order(:id)
  end

  def show
    @chatroom = Chatroom.find(params[:id])
    @chatrooms = Chatroom.order(:id) unless turbo_frame_request?
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

  def chatroom_params
    params.expect(chatroom: %i[latitude longitude])
  end
end
