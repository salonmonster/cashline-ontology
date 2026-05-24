class CreateSobjects < ActiveRecord::Migration[8.1]
  def change
    create_table :sobjects do |t|
      t.references :extraction_run, null: false, foreign_key: true
      t.string :api_name, null: false
      t.string :label
      t.string :namespace_prefix
      t.boolean :custom, null: false, default: false
      t.boolean :is_name_field, null: false, default: false
      t.jsonb :raw_describe, null: false, default: {}
      t.timestamps
    end

    add_index :sobjects, %i[extraction_run_id api_name], unique: true
    add_index :sobjects, :api_name
  end
end
