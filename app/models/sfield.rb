class Sfield < ApplicationRecord
  self.table_name = "sfields"

  belongs_to :sobject
  has_many :spicklist_values, dependent: :destroy

  validates :api_name, presence: true
end
