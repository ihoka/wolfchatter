# Chatrooms visible in a map viewport: individual pins when there are PIN_LIMIT or fewer,
# otherwise counts per cell of a global grid. At most 3 queries. The pins query is capped at
# PIN_LIMIT + 1 rows and uses the (latitude, longitude) index. The cluster GROUP BY returns at
# most PIN_LIMIT cells but reads every room in the box, so at world zoom its cost grows with the
# total number of rooms. The lone-room lookup loads at most PIN_LIMIT rows by primary key.
class MapMarkers
  PIN_LIMIT = 300
  CELL_PX = 80

  Cluster = Data.define(:cell_x, :cell_y, :count, :lat, :lng, :chatroom)

  # Cell edge in degrees: CELL_PX screen pixels on a 256px-tile web map at this zoom.
  def self.cell_size_for(zoom)
    360.0 / 2**zoom * (CELL_PX / 256.0)
  end

  def initialize(south:, west:, north:, east:, zoom:)
    @south = south
    @west = west
    @north = north
    @east = east
    @zoom = zoom
  end

  def mode
    candidate_pins.size <= PIN_LIMIT ? :pins : :clusters
  end

  def pins
    mode == :pins ? candidate_pins : []
  end

  def clusters
    return [] if mode == :pins

    @clusters ||= build_clusters
  end

  # The grid is coarsened (doubled) until the box holds at most PIN_LIMIT cells, so a
  # zoomed-out view never produces an unbounded number of groups.
  def cell_size
    @cell_size ||= begin
      size = self.class.cell_size_for(@zoom)
      size *= 2 while cells_for(size) > PIN_LIMIT
      size
    end
  end

  private

  def in_box
    scope = Chatroom.where(latitude: @south..@north)
    if @west <= @east
      scope.where(longitude: @west..@east)
    else
      scope.where("longitude >= :west OR longitude <= :east", west: @west, east: @east)
    end
  end

  def candidate_pins
    @candidate_pins ||= in_box.select(:id, :latitude, :longitude, :place_name).limit(PIN_LIMIT + 1).to_a
  end

  def cells_for(size)
    east_span = @east - @west
    east_span += 360 if east_span.negative?
    ((east_span / size).ceil + 1) * (((@north - @south) / size).ceil + 1)
  end

  def cell_x_expr
    Arel::Nodes::NamedFunction.new("FLOOR", [ Chatroom.arel_table[:longitude] / Arel::Nodes.build_quoted(cell_size) ])
  end

  def cell_y_expr
    Arel::Nodes::NamedFunction.new("FLOOR", [ Chatroom.arel_table[:latitude] / Arel::Nodes.build_quoted(cell_size) ])
  end

  def build_clusters
    rows = in_box
           .group(cell_x_expr, cell_y_expr)
           .pluck(cell_x_expr, cell_y_expr,
                  Arel.sql("COUNT(*)"), Arel.sql("AVG(latitude)"), Arel.sql("AVG(longitude)"),
                  Arel.sql("MIN(id)"))
    lone_ids = rows.filter_map { |_, _, count, _, _, id| id if count == 1 }
    lone = Chatroom.where(id: lone_ids).index_by(&:id)

    rows.map do |x, y, count, lat, lng, id|
      Cluster.new(cell_x: x.to_i, cell_y: y.to_i, count: count, lat: lat.to_f, lng: lng.to_f,
                  chatroom: count == 1 ? lone[id] : nil)
    end
  end
end
