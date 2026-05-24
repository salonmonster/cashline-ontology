class SpicklistValue < ApplicationRecord
  self.table_name = "spicklist_values"

  belongs_to :sfield
end
