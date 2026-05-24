class CreateSfields < ActiveRecord::Migration[8.1]
  def change
    create_table :sfields do |t|
      t.references :sobject, null: false, foreign_key: true
      t.string :api_name, null: false
      t.string :label
      t.string :data_type
      t.integer :length
      t.boolean :nillable, null: false, default: true
      t.boolean :calculated, null: false, default: false
      t.text :calculated_formula
      t.boolean :encrypted, null: false, default: false
      t.boolean :name_field, null: false, default: false
      t.string :compound_field_name
      t.integer :picklist_count, null: false, default: 0
      t.integer :references_count, null: false, default: 0
      t.string :namespace_prefix
      t.boolean :accessible, null: false, default: true
      t.boolean :createable, null: false, default: true
      t.boolean :updateable, null: false, default: true
      t.boolean :filterable, null: false, default: true
      t.jsonb :raw_describe, null: false, default: {}
      t.jsonb :tooling_metadata
      t.timestamps
    end

    add_index :sfields, %i[sobject_id api_name], unique: true
    add_index :sfields, :api_name
    add_index :sfields, :calculated
  end
end
