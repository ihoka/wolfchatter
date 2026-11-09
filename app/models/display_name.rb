class DisplayName
  include ActiveModel::Model
  include ActiveModel::Attributes

  MAX_LENGTH = 40

  attribute :name, :string

  def name=(value)
    super(VisibleText.strip(value))
  end

  validates :name, presence: true, length: { maximum: MAX_LENGTH }
end
