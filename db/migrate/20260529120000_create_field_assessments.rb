class CreateFieldAssessments < ActiveRecord::Migration[8.1]
  def change
    create_table :field_assessments do |t|
      t.references :sfield, null: false, foreign_key: true
      t.references :cashline_snapshot, null: false, foreign_key: true
      t.text :role_note
      t.string :disposition
      t.text :disposition_reason
      t.datetime :assessed_at

      t.timestamps
    end

    add_index :field_assessments, [ :sfield_id, :cashline_snapshot_id ], unique: true, name: "index_field_assessments_on_field_and_snapshot"
  end
end
