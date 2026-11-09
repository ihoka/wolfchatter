# Pins or clusters for the visible map area, as a Turbo Stream that fills #markers.
class MarkersController < ApplicationController
  def index
    @markers = MapMarkers.new(**viewport)
    expires_now
    respond_to do |format|
      format.turbo_stream
      format.any { head :not_acceptable }
    end
  rescue ArgumentError, TypeError, ActionController::ParameterMissing
    head :bad_request
  end

  private

  def viewport
    south = lat_param(:south)
    north = lat_param(:north)
    west = lng_param(:west)
    east = lng_param(:east)
    zoom = Integer(params.require(:zoom), 10)
    raise ArgumentError, "zoom out of range" unless (0..19).cover?(zoom)

    { south: south, west: west, north: north, east: east, zoom: zoom }
  end

  def float_param(key)
    value = Float(params.require(key))
    raise ArgumentError, "#{key} not finite" unless value.finite?

    value
  end

  def lat_param(key)
    float_param(key).clamp(-90.0, 90.0)
  end

  def lng_param(key)
    value = float_param(key)
    raise ArgumentError, "#{key} out of range" unless (-180.0..180.0).cover?(value)

    value
  end
end
