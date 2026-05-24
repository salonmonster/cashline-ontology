class CreateSpicklistValues < ActiveRecord::Migration[8.1]
  def change
    create_table :spicklist_values do |t|
      t.references :sfield, null: false, foreign_key: true
      t.string :value, null: false
      t.string :label
      t.boolean :active, null: false, default: true
      t.boolean :default_value, null: false, default: false
      t.timestamps
    end

    add_index :spicklist_values, %i[sfield_id value], unique: true
  end
end
