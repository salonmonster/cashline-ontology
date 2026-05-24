class CreateSrelationships < ActiveRecord::Migration[8.1]
  def change
    create_table :srelationships do |t|
      t.references :extraction_run, null: false, foreign_key: true
      t.references :source_sobject, null: false, foreign_key: { to_table: :sobjects }
      t.references :target_sobject, null: true, foreign_key: { to_table: :sobjects }
      t.references :source_field, null: true, foreign_key: { to_table: :sfields }
      t.string :relationship_name
      t.boolean :cascade_delete, null: false, default: false
      t.boolean :restricted_delete, null: false, default: false
      t.boolean :polymorphic, null: false, default: false
      t.jsonb :reference_to_api_names, null: false, default: []
      t.timestamps
    end

    add_index :srelationships, %i[extraction_run_id source_sobject_id target_sobject_id], name: "idx_srels_run_src_tgt"
    add_index :srelationships, :polymorphic
  end
end
