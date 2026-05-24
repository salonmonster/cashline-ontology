class Srelationship < ApplicationRecord
  self.table_name = "srelationships"

  belongs_to :extraction_run
  belongs_to :source_sobject, class_name: "Sobject"
  belongs_to :target_sobject, class_name: "Sobject", optional: true
  belongs_to :source_field, class_name: "Sfield", optional: true
end
