class DisplayNamesController < ApplicationController
  before_action :set_chatroom

  def update
    @display_name = DisplayName.new(params.expect(display_name: :name))
    if @display_name.valid?
      remember_display_name(@display_name.name)
      render_compose name: @display_name.name
    else
      render_compose name: nil, status: :unprocessable_content
    end
  end

  def destroy
    forget_display_name
    render_compose name: nil
  end

  private

  def set_chatroom
    @chatroom = Chatroom.find(params.expect(:chatroom_id))
  end

  # Turbo stream only: the panel frame advances history on redirects, so these
  # forms never redirect. Other formats get 406.
  # The cookie written during this request is not readable until the next one,
  # so the name is passed explicitly.
  def render_compose(name:, status: :ok)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          helpers.dom_id(@chatroom, :compose),
          partial: "chatrooms/compose",
          locals: { chatroom: @chatroom, name: name, display_name: @display_name }
        ), status: status
      end
      format.any { head :not_acceptable }
    end
  end
end
