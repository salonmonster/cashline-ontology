class Cluster < ApplicationRecord
  belongs_to :extraction_run
  has_many :cluster_assignments, dependent: :destroy
  has_many :sobjects, through: :cluster_assignments

  validates :name, presence: true

  def self.slug_for(name)
    name.parameterize
  end

  def slug
    self.class.slug_for(name)
  end
end
